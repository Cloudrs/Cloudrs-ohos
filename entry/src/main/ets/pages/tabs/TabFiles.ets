import {
  DirectoryInfo, DirFileInfo, HttpCallback, ObjectDetail, ObjectInfo, Policy, ShareLinkInfo
} from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import TransferDatabase from "../../model/TransferDatabase";
import LazyDataSource from "../../utils/LazyDataSource";
import { BatchFailure, BatchOutcome, CloudApi, FileLockConflict } from "../../model/net/CloudApi";
import { showApiFailureToast, showToast, showToastTips, ToastType } from "../../utils/ToastUtil";
import { ApiErrorUtil, NETWORK_ERROR_MESSAGE } from "../../utils/ApiErrorUtil";
import { ObjectItem } from "../../components/ObjectItem";
import { FileSearchParam, ImagePreview, PreviewFile, VideoPreview } from "../../model/Params";
import { FileMenuType, MoreMenuType, ShowType, SortType } from "../../model/MenuModel";
import { filePreview } from "@kit.PreviewKit";
import { DetailData } from "../../model/DetailData";
import { DetailSheet } from "../../components/DetailSheet";
import { CommonUtil, FileType } from "../../utils/CommonUtil";
import { PathSelectSheet } from "../../components/PathSelectSheet";
import { ObjectCopy, ObjectMove, ObjectSrc } from "../../model/net/ObjectParam";
import { common } from "@kit.AbilityKit";
import { BusinessError, deviceInfo, pasteboard, request } from "@kit.BasicServicesKit";
import { uniformTypeDescriptor } from "@kit.ArkData";
import { window } from "@kit.ArkUI";
import { picker } from '@kit.CoreFileKit';
import { TransportObject } from "../../model/TransportObject";
import { requestDownload } from "../../utils/RequestDownload";
import { FileModel, FileModelState } from "../../model/FileModel";
import { SelectFileSheet } from '../../components/SelectFileSheet';
import { uploadManager } from '../../utils/UploadManager';
import { CloudBreakpoint, CloudThemeToken } from "../../model/CloudTheme";
import { EmptyState } from "../../components/EmptyState";
import { FileSystemUtil } from "../../utils/FileSystemUtil";
import AppLogger from "../../utils/AppLogger";
import { showCloudActionDialog, showCloudConfirmDialog } from "../../utils/CloudDialogUtil";
import { CloudRouter } from "../../utils/CloudRouter";
import { TextPreviewEntry } from "../../utils/TextPreviewEntry";
import { ActiveAccount } from "../../utils/ActiveAccount";
import UserPreferences from "../../model/UserPreferences";
import { PhotoBackupSettingsStore } from "../../model/PhotoBackupSettingsStore";
import UploadSessionRelief, { UploadSessionSummary } from "../../utils/UploadSessionRelief";
import { DateFormatUtil } from "../../utils/DateFormatUtil";
import { CloudIconButton } from "../../components/CloudIconButton";
import {
  DividerShowType, HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial
} from "@kit.UIDesignKit";
import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import { Downloads, TransferAction } from "../../components/Downloads";
import { Uploads } from "../../components/Uploads";
import { saveImagesToAlbum, SaveAlbumResult } from "../../utils/PhotoSaveUtil";
import { harmonyShare, systemShare } from "@kit.ShareKit";
import { KnockShareUtil } from "../../utils/KnockShareUtil";
import { FileThumbSourceCache } from "../../utils/FileThumbSourceCache";
import { FileGridLayout } from "../../utils/FileGridLayout";

const TAG = 'TabFiles';
const INPUT_SHEET_TEXT_ID = 'tabFilesInputSheetText';
// bindSheet onAppear（入场动画结束）之后再等一小段，确保焦点系统就绪
const INPUT_SHEET_SELECTION_DELAY = 100;
const DOWNLOAD_FAIL_TOAST_INTERVAL_MS = 2000;
const FILE_THUMB_MAX_CONCURRENT: number = 4
const FILE_THUMB_QUEUE_DELAY_MS: number = 500
// 队列封顶：快速滑过大量图片时只保留最近出现的请求，被丢弃的项重新上屏时
// 会经 LazyDataSource.getData → onDataGet 再次入队，不会漏加载
const FILE_THUMB_QUEUE_MAX: number = 64
const FILE_SHARE_REFRESH_DELAY_MS: number = 650
const FILE_BATCH_MAX_CONCURRENT: number = 4
/**
 * 每个请求塞多少个对象。服务端的删除/移动/复制接口本来就吃 uri 数组，一次
 * 请求处理一整块，4000 个文件的请求数从 4000 降到 80。
 * 不取更大是因为块越大三件事越难受：进度条在一块跑完前不动、取消时已发出的
 * 那批停不下来、单个请求在服务端的事务也越长。50 是这几者之间的折中。
 */
const FILE_BATCH_CHUNK_SIZE: number = 50
/** 冲突确认框在宽屏上的宽度上限，避免在平板上拉成一条 */
const CONFLICT_DIALOG_MAX_WIDTH: number = 420
/**
 * 批量操作面板延迟这么久才出现。删 2-3 个文件通常 200ms 就跑完了，比半模态自身的
 * 开合动画还短，立刻开又立刻关看起来就是闪一下；这段时间内做完的批次干脆不弹面板，
 * 结果由各调用方本来就有的 toast 交代。
 * 判据是耗时而不是数量——网络差时删 2 个文件也可能要十几秒，那时候面板照常出现，
 * 用户仍有进度和取消入口。
 */
const BATCH_SHEET_SHOW_DELAY_MS: number = 400
/** 面板一旦露面就至少驻留这么久，避免刚展开就被收起 */
const BATCH_SHEET_MIN_VISIBLE_MS: number = 500

// Lifecycle phase of a bindSheet, driven by its
// onWillAppear/onAppear/onWillDisappear/onDisappear callbacks.
enum SheetPhase {
  CLOSED,
  OPENING,
  OPEN,
  CLOSING
}

interface BatchItemResult {
  item: ObjectInfo
  success: boolean
  skipped: boolean
  message: string
  lockConflicts?: FileLockConflict[]
}

interface BatchOperationControl {
  canceled: boolean
  paused: boolean
  resumeWaiters: Array<() => void>
}

interface BatchExecutionResult {
  results: BatchItemResult[]
  canceled: boolean
}

enum FileConflictPolicy {
  ASK,
  SKIP_ALL,
  OVERWRITE_ALL
}

enum FileConflictDecision {
  SKIP,
  OVERWRITE
}

interface FileConflictRequest {
  name: string
  size: number
  isDir: boolean
  /** 目标目录，确认框里要让用户看清是往哪儿放 */
  destination: string
  resolve: (decision: FileConflictDecision) => void
}

interface ServerUploadSession {
  remotePath: string
  sessionId: string
}

// Drives a single bindSheet off its real lifecycle phase instead of the bound
// flag (which stays true throughout the close animation). An open request that
// arrives while the sheet is still closing is queued and replayed once it
// finishes closing, instead of re-setting the flag mid-animation — which races
// the close and ends up dismissing the sheet (so the tap does nothing). The
// flag is only re-triggered (false→true) for a genuinely stale flag (true with
// no visible sheet).
class SheetPhaseController {
  private phase: SheetPhase = SheetPhase.CLOSED
  private reopenPending: boolean = false
  /** 排队中的"稍后打开"，requestClose 要能把它撤销 */
  private pendingOpenTimer: number = -1

  requestOpen(getFlag: () => boolean, setFlag: (value: boolean) => void): void {
    if (getFlag() && (this.phase === SheetPhase.OPEN || this.phase === SheetPhase.OPENING)) {
      this.reopenPending = false
      return
    }
    if (this.phase === SheetPhase.CLOSED) {
      this.reopenPending = false
      if (getFlag()) {
        setFlag(false)
        this.clearPendingOpen()
        this.pendingOpenTimer = setTimeout(() => {
          this.pendingOpenTimer = -1
          setFlag(true)
        }, 50)
      } else {
        setFlag(true)
      }
      return
    }
    this.reopenPending = true
    setFlag(false)
  }

  /**
   * 收起面板，并撤销一切待打开的意图。
   *
   * 直接把绑定量设 false 是不够的：requestOpen 可能已经排了个 50ms 后打开的
   * 定时器，或标了 reopenPending，它们会在之后把面板重新拉起来——盖住此刻真正
   * 要给用户看的那一层。想让路就得连意图一起撤掉。
   */
  requestClose(setFlag: (value: boolean) => void): void {
    this.clearPendingOpen()
    this.reopenPending = false
    setFlag(false)
  }

  private clearPendingOpen(): void {
    if (this.pendingOpenTimer >= 0) {
      clearTimeout(this.pendingOpenTimer)
      this.pendingOpenTimer = -1
    }
  }

  onWillAppear(): void {
    this.phase = SheetPhase.OPENING
  }

  onAppear(): void {
    this.phase = SheetPhase.OPEN
  }

  onWillDisappear(): void {
    this.phase = SheetPhase.CLOSING
  }

  onDisappear(setFlag: (value: boolean) => void, onClosed: () => void): void {
    this.phase = SheetPhase.CLOSED
    if (this.reopenPending) {
      this.reopenPending = false
      setTimeout(() => setFlag(true), 50)
    } else {
      onClosed()
    }
  }
}

PersistentStorage.persistProp(Constant.CURRENT_SHOW_TYPE, ShowType.SHOW_ICON)
// 默认按修改时间倒序（最新的在最前）。SORT_BY_TIME 的 reverse=true 才是倒序，见 sortObjects。
PersistentStorage.persistProp(Constant.CURRENT_SORT_TYPE, SortType.SORT_BY_TIME)
PersistentStorage.persistProp(Constant.CURRENT_SORT_TYPE_RESERVE, new Map<SortType, boolean>([
  [SortType.SORT_BY_NAME, false], [SortType.SORT_BY_TYPE, false],
  [SortType.SORT_BY_TIME, true], [SortType.SORT_BY_SIZE, false],
]))

// persistProp 只在"该键尚未持久化"时才写入默认值，所以老用户仍停留在旧的按名称升序。
// 这里做一次性迁移把他们也带到新默认；标记落盘后不再重复，用户之后自己改的排序照常保留。
PersistentStorage.persistProp(Constant.SORT_DEFAULT_TIME_DESC_APPLIED, false)
if (!AppStorage.get<boolean>(Constant.SORT_DEFAULT_TIME_DESC_APPLIED)) {
  AppStorage.setOrCreate(Constant.CURRENT_SORT_TYPE, SortType.SORT_BY_TIME)
  const migratedReverse = new Map<SortType, boolean>(
    AppStorage.get<Map<SortType, boolean>>(Constant.CURRENT_SORT_TYPE_RESERVE) ?? new Map<SortType, boolean>())
  migratedReverse.set(SortType.SORT_BY_TIME, true)
  AppStorage.setOrCreate(Constant.CURRENT_SORT_TYPE_RESERVE, migratedReverse)
  AppStorage.setOrCreate(Constant.SORT_DEFAULT_TIME_DESC_APPLIED, true)
}

enum FilePageState {
  IDLE = 'idle',
  LOADING = 'loading',
  FAILED = 'failed'
}

enum FileInputMode {
  NONE = 'none',
  RENAME = 'rename',
  NEW_OBJECT = 'newObject'
}

enum ShareExpireDays {
  NEVER = 0,
  ONE_DAY = 1,
  SEVEN_DAYS = 7,
  THIRTY_DAYS = 30
}

class ObjectSelect {
  index: number = -1
  type: FileMenuType = FileMenuType.COPY
  selectPathTitle: ResourceStr = ''
  selectPathId: string = ''
  copyMoveObjects: ObjectInfo[] = []

  constructor(type?: FileMenuType, selectPathTitle?: ResourceStr, selectPathId?: string, copyMoveObjects?: ObjectInfo[]) {
    if (type) {
      this.type = type;
    }

    if (selectPathTitle) {
      this.selectPathTitle = selectPathTitle;
    }

    if (selectPathId) {
      this.selectPathId = selectPathId;
    }

    if (copyMoveObjects) {
      this.copyMoveObjects = copyMoveObjects;
    }
  }
}

@Component
export struct TabFiles {
  @Link overLap: boolean
  @Watch('onActiveChanged')
  @Prop isActive: boolean = true
  // 首页常驻，切换账号不会重建本组件，靠这个信号丢弃上一账号的目录数据
  @Watch('onAccountChanged')
  @StorageProp(Constant.ACTIVE_ACCOUNT_SCOPE) accountScope: string = ''
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.KEYBOARD_HEIGHT_VP) keyboardHeightVp: number = 0;
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0;
  @StorageProp(Constant.SIDEBAR_VISIBLE) sidebarVisible: boolean = true;
  @StorageLink(Constant.CURRENT_SHOW_TYPE) showType: ShowType = ShowType.SHOW_ICON
  @StorageLink(Constant.CURRENT_SORT_TYPE) sortType: SortType = SortType.SORT_BY_NAME
  @StorageLink(Constant.CURRENT_SORT_TYPE_RESERVE) sortTypeReverse: Map<SortType, boolean> = new Map([])
  @State policy: Policy|null = null
  @State isRoot: boolean = true
  @State mainTitle: string|Resource = $r('app.string.files_main_title')
  @State subTitle: string|Resource = $r('app.string.files_sub_title')
  @Provide thumbImage: Map<string, PixelMap> = new Map()
  @Provide thumbSource: Map<string, string> = new Map()
  @State isRefreshing:boolean = false
  @State showObjectDetail: boolean = false
  @State visibleSheetCount: number = 0
  private detailSheetCtrl: SheetPhaseController = new SheetPhaseController()
  private selectFileSheetCtrl: SheetPhaseController = new SheetPhaseController()
  private inputSheetCtrl: SheetPhaseController = new SheetPhaseController()
  private shareSheetCtrl: SheetPhaseController = new SheetPhaseController()
  private transportSheetCtrl: SheetPhaseController = new SheetPhaseController()
  private pathSelectSheetCtrl: SheetPhaseController = new SheetPhaseController()
  @State detailData: DetailData = new DetailData('Unknown', false, new ObjectDetail())
  // 详情面板当前展示的对象,供碰一碰分享取当前文件;仅在面板注册监听期间被读取
  private detailKnockObject: ObjectInfo | null = null
  private currentPath: string = '/'
  private scrollerForList: Scroller = new Scroller()
  @State dirDataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()
  @State fileDataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()
  private objectsInfo: DirFileInfo = new DirFileInfo();
  @State isGridPadding: boolean = false;
  @State showPathSelect: boolean = false
  /** 已选好但还没开工的移动/复制目标，等路径选择半模态消失后再启动 */
  private pendingCopyMoveDst: string = ''
  private objectSelect: ObjectSelect = new ObjectSelect()

  @State downloadingCount: number = 0;
  @State uploadingCount: number = 0;
  @State albumSaving: boolean = false;
  @State albumSaveText: string = '';
  @State batchOperationVisible: boolean = false
  @State batchOperationTitle: string = ''
  @State batchOperationTotal: number = 0
  @State batchOperationProcessed: number = 0
  @State batchOperationSucceeded: number = 0
  @State batchOperationSkipped: number = 0
  @State batchOperationFailed: number = 0
  @State batchOperationInFlight: number = 0
  @State batchOperationPaused: boolean = false
  @State batchOperationCancelRequested: boolean = false
  @State batchOperationElapsedSeconds: number = 0
  private batchOperationRunning: boolean = false
  private batchOperationSheetCtrl: SheetPhaseController = new SheetPhaseController()
  private activeBatchOperationControl: BatchOperationControl | null = null
  private batchOperationElapsedTimer: number = -1
  /** 延迟弹面板的定时器；批次在延迟内结束就直接取消，面板不会出现 */
  private batchOperationShowTimer: number = -1
  /** 面板真正请求展开的时刻，用于兑现最短驻留 */
  private batchOperationShownAt: number = 0
  /** 冲突确认框内的"其余同名项目都这样处理" */
  @State fileConflictApplyAll: boolean = false
  /** promptAction 返回的弹窗句柄，-1 表示当前没有打开 */
  private fileConflictDialogId: number = -1
  private fileConflictPolicy: FileConflictPolicy = FileConflictPolicy.ASK
  private fileConflictQueue: FileConflictRequest[] = []
  private activeFileConflict: FileConflictRequest | null = null
  @State downloadObjects: LazyDataSource<TransportObject> = new LazyDataSource()
  @State uploadObjects: LazyDataSource<TransportObject> = new LazyDataSource()
  @State showSelectFileSheet: boolean = false
  @State showInputSheet: boolean = false
  @State filePageState: FilePageState = FilePageState.IDLE
  @State searchKeyword: string = ''
  @State inputMode: FileInputMode = FileInputMode.NONE
  @State inputTitle: string|Resource = ''
  @State inputPlaceholder: string|Resource = ''
  @State inputValue: string = ''
  @State gridWidth: number = 0
  @State isHeaderGlassActive: boolean = false
  @State headerCollapseProgress: number = 0
  @State refreshPullOffset: number = 0
  @State currentUser: string = ''
  @State currentUrl: string = ''
  @State isMultiSelectMode: boolean = false
  @State selectedObjects: ObjectInfo[] = []
  @State multiSelectBarHeight: number = 0
  @State shareLinks: ShareLinkInfo[] = []
  @State sharedPaths: string[] = []
  @State showShareSheet: boolean = false
  @State shareTarget: ObjectInfo | null = null
  @State shareLinkText: string = ''
  @State sharePassword: string = ''
  @State shareExpireDays: number = ShareExpireDays.SEVEN_DAYS
  @State shareBusy: boolean = false
  @State showTransportSheet: boolean = false
  @State showFileMoreMenu: boolean = false
  @State selectCapsuleOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: $r('app.string.task_download') }, { text: $r('app.string.task_upload') }] as SegmentButtonItemTuple,
    multiply: false,
    backgroundBlurStyle: BlurStyle.BACKGROUND_THICK
  })
  @State selectedIndexes: number[] = [CloudThemeToken.primarySegmentIndex]
  private lastHeaderScrollOffset: number = 0
  private inputRenameIndex: number = -1
  private inputRenameItem?: ObjectInfo = undefined
  private inputTextController: TextInputController = new TextInputController()
  private lastDownloadFailToastAt: number = 0
  // 下载完成但尺寸不符（多为直链过期）时已自动换链重试过的任务 id，避免无限重试
  private retriedBadDownloadIds: Set<string> = new Set<string>()
  private inputNewPath: string = '/'
  private inputNewIsDir: boolean = true
  private thumbLoadingIds: Set<string> = new Set<string>()
  private thumbFailedIds: Set<string> = new Set<string>()
  private thumbQueue: ObjectInfo[] = []
  private activeThumbLoads: number = 0
  private thumbQueueTimer: number = -1
  // 新目录首屏按数据顺序 FIFO 加载；用户开始滚动后切到 LIFO，让当前屏优先于已经滑过的项目。
  private prioritizeNewestThumbRequests: boolean = false
  private shareRefreshTimer: number = -1
  private initialFileListRequested: boolean = false
  private loadingFilePath: string = ''
  // 当前列表数据属于哪个账号，用来识别账号切换并丢弃迟到的旧账号响应
  private loadedAccountScope: string = ''
  // 列表在本页不可见时加载完成，缩略图请求被推迟到本页重新变为活动时
  private thumbsDeferredUntilActive: boolean = false

  private onActiveChanged(): void {
    if (!this.isActive) {
      if (this.thumbQueueTimer >= 0) {
        clearTimeout(this.thumbQueueTimer)
        this.thumbQueueTimer = -1
      }
      this.cancelScheduledShareRefresh()
      return
    }
    // 本页不可见时加载完的列表，onDataGet 那一轮的缩略图请求被 isActive 挡掉了，
    // 队列里什么都没有、LazyForEach 也不会自己再要一次数据。重放一次可见项回调补上，
    // 否则用户看到的是一片占位图，得手动下拉刷新才出图。
    if (this.thumbsDeferredUntilActive) {
      this.thumbsDeferredUntilActive = false
      this.applyVisibleObjects()
    }
    if (this.thumbQueue.length > 0) {
      this.scheduleThumbQueue()
    }
    if (this.dirDataSource.totalCount() > 0 || this.fileDataSource.totalCount() > 0) {
      this.scheduleShareLinksRefresh()
    }
  }

  /**
   * 账号切换：本组件常驻不重建，必须主动把上一账号的目录、缩略图、分享标记全部丢掉再回根目录重拉。
   * 退出登录（scope 为空）时首页整体会被登录页替换，不用在这里空跑一次请求。
   */
  private onAccountChanged(): void {
    const scope = this.accountScope
    if (scope.length === 0 || scope === this.loadedAccountScope) {
      return
    }
    AppLogger.info(TAG, `account switched, reload root directory`)
    this.loadedAccountScope = scope
    this.exitMultiSelectMode()
    this.cancelScheduledShareRefresh()
    this.shareLinks = []
    this.sharedPaths = []
    this.resetThumbQueue()
    this.thumbImage = new Map()
    this.dirDataSource.clear()
    this.fileDataSource.clear()
    this.objectsInfo = new DirFileInfo()
    this.searchKeyword = ''
    // loadCurrentUser 顺带按新账号作用域重取缩略图快照，放在清空之后
    this.loadCurrentUser()
    // 旧账号的请求可能还在飞，清掉在途标记并让 getFileList 走"换目录"分支，不保留旧内容
    this.loadingFilePath = ''
    this.currentPath = ''
    this.getFileList(true, '/')
  }

  setThumbData(id: string, pixMap: PixelMap) {
    const updated: Map<string, PixelMap> = new Map(this.thumbImage);
    updated.set(id, pixMap);
    this.thumbImage = updated;
  }

  setThumbSourceData(item: ObjectInfo, source: string) {
    if (source.length === 0) {
      return
    }
    FileThumbSourceCache.set(this.getThumbCacheKey(item), source)
    const updated: Map<string, string> = new Map(this.thumbSource)
    updated.set(item.id, source)
    this.thumbSource = updated
  }

  getThumbData(id: string): PixelMap|undefined {
    if (this.thumbImage.has(id)) {
      return this.thumbImage.get(id)
    }
    return undefined
  }

  getThumbSourceData(id: string): string {
    return this.thumbSource.get(id) ?? ''
  }

  isSortTypeReverse(type: SortType): boolean {
    if (this.sortTypeReverse.has(type)) {
      return this.sortTypeReverse.get(type)!
    }
    return false
  }

  private getTransportCount(): number {
    return this.downloadingCount + this.uploadingCount
  }

  // Dim is driven by sheets actually on screen (onAppear/onDisappear), not by
  // the request flags — a flag can get stuck true when a sheet open request is
  // dropped mid context-menu dismissal, which used to leave the title buttons
  // permanently gray.
  private shouldDimFileTitleActions(): boolean {
    return this.visibleSheetCount > 0
  }

  private markSheetVisible(): void {
    this.visibleSheetCount += 1
  }

  private markSheetHidden(): void {
    this.visibleSheetCount = Math.max(0, this.visibleSheetCount - 1)
  }

  private getFileTitleActionBackground(): ResourceColor {
    return this.shouldDimFileTitleActions() ? '#1AFFFFFF' : CloudThemeToken.surfaceSubtle
  }

  private getFileTitleActionIconColor(): ResourceColor {
    return this.shouldDimFileTitleActions() ? '#33111827' : CloudThemeToken.textPrimary
  }

  private getSearchMenuItem(): HdsNavigationMenuItemOptions {
    return {
      content: {
        icon: $r('app.media.ic_search'),
        label: '搜索',
        action: () => {
          this.openFileSearchPage()
        }
      }
    }
  }

  private getFileTitleMenu(): HdsNavigationMenuItemOptions[] {
    return [
      this.getSearchMenuItem(),
      this.getTransportMenuItem(),
      this.getMoreMenuItem()
    ]
  }

  private getMoreMenuItem(): HdsNavigationMenuItemOptions {
    return {
      content: {
        icon: $r('app.media.ic_dot_grid'),
        label: '更多',
        action: () => {
          this.showFileMoreMenu = !this.showFileMoreMenu
        }
      }
    }
  }

  private getTransportMenuItem(): HdsNavigationMenuItemOptions {
    let item: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('app.media.ic_transport'),
        label: '传输',
        action: () => {
          this.openTransportSheet()
        }
      }
    }
    if (this.getTransportCount() > 0) {
      item.badge = {
        count: this.getTransportCount()
      }
    }
    return item
  }

  private openTransportSheet(): void {
    this.transportSheetCtrl.requestOpen(() => this.showTransportSheet, (value: boolean) => {
      this.showTransportSheet = value
    })
  }

  private isAllSelected(): boolean {
    const total = this.dirDataSource.dataArray.length + this.fileDataSource.dataArray.length
    return total > 0 && this.selectedObjects.length >= total
  }

  private toggleSelectAll(): void {
    if (this.isAllSelected()) {
      this.selectedObjects = []
    } else {
      this.selectAllVisibleObjects()
    }
  }

  private getMultiSelectTitleMenu(): HdsNavigationMenuItemOptions[] {
    return [{
      content: {
        icon: this.isAllSelected() ? $r('sys.symbol.checkmark_square_on_square_fill') : $r('sys.symbol.checkmark_square_on_square'),
        label: '全选',
        action: () => {
          this.toggleSelectAll()
        }
      }
    }, {
      content: {
        icon: $r('sys.symbol.xmark'),
        label: '取消',
        action: () => {
          this.exitMultiSelectMode()
        }
      }
    }]
  }

  private openFileSearchPage(): void {
    const objects = this.objectsInfo.dirObjects.concat(this.objectsInfo.fileObjects)
    CloudRouter.push(Constant.FILE_SEARCH_PAGE, new FileSearchParam(this.currentPath, objects,
      (item: ObjectInfo) => {
        this.onSearchResultOpen(item)
      },
      (item: ObjectInfo, type: FileMenuType) => {
        this.onSearchResultMenuClick(item, type)
      },
      this.showType,
      this.thumbImage,
      this.thumbSource,
      () => {
        this.getFileList(true, this.currentPath)
      }))
  }

  private onSearchResultOpen(item: ObjectInfo): void {
    this.onItemClick(item)
  }

  private onSearchResultMenuClick(item: ObjectInfo, type: FileMenuType): void {
    const index = this.getSearchResultObjectIndex(item)
    this.onMenuClick(index, item, type)
  }

  private getSearchResultObjectIndex(item: ObjectInfo): number {
    const visibleObjects = item.type === Constant.OBJECT_DIR_TYPE ?
    this.dirDataSource.dataArray : this.fileDataSource.dataArray
    const visibleIndex = visibleObjects.findIndex((object: ObjectInfo) => object.id === item.id)
    if (visibleIndex >= CloudThemeToken.zero) {
      return visibleIndex
    }

    const allObjects = item.type === Constant.OBJECT_DIR_TYPE ?
    this.objectsInfo.dirObjects : this.objectsInfo.fileObjects
    return allObjects.findIndex((object: ObjectInfo) => object.id === item.id)
  }

  private getSortIcon(type: SortType): Resource {
    if (this.sortType !== type) {
      return $r('app.media.ic_sort_arrow_up')
    }
    return this.isSortTypeReverse(type) ? $r('app.media.ic_sort_arrow_down') : $r('app.media.ic_sort_arrow_up')
  }

  private toggleFileShowType(): void {
    this.showType = this.showType === ShowType.SHOW_ICON ? ShowType.SHOW_LIST : ShowType.SHOW_ICON
    this.isGridPadding = this.getFolderPaddingCount() > 0
    this.dirDataSource.notifyDataReload()
    this.fileDataSource.notifyDataReload()
  }

  private changeShowType(type: ShowType): void {
    if (this.showType === type) {
      return
    }
    this.showType = type
    this.isGridPadding = this.getFolderPaddingCount() > 0
    this.dirDataSource.notifyDataReload()
    this.fileDataSource.notifyDataReload()
  }

  private closeFileMoreMenu(): void {
    this.showFileMoreMenu = false
  }

  private changeSortType(type: SortType, menuType: MoreMenuType): void {
    let isReverse = this.isSortTypeReverse(type)
    if (this.sortType === type) {
      isReverse = !isReverse
    } else {
      this.sortType = type
      isReverse = false
    }
    let sortTypeReverse = new Map<SortType, boolean>(this.sortTypeReverse)
    sortTypeReverse.set(type, isReverse)
    this.sortTypeReverse = sortTypeReverse
    this.onMoreClick(menuType, isReverse)
  }

  isCurrentDirectoryEmpty(): boolean {
    return this.searchKeyword.trim().length === 0 &&
      this.filePageState === FilePageState.IDLE && !this.isRefreshing &&
      this.dirDataSource.totalCount() === 0 && this.fileDataSource.totalCount() === 0
  }

  isSearchResultEmpty(): boolean {
    return this.searchKeyword.trim().length > 0 &&
      this.filePageState === FilePageState.IDLE && !this.isRefreshing &&
      this.dirDataSource.totalCount() === 0 && this.fileDataSource.totalCount() === 0
  }

  isFilePageLoading(): boolean {
    return this.filePageState === FilePageState.LOADING
  }

  isFilePageFailed(): boolean {
    return this.filePageState === FilePageState.FAILED
  }

  applyVisibleObjects() {
    const keyword = this.searchKeyword.trim().toLowerCase()
    if (keyword.length === 0) {
      this.dirDataSource.dataArray = this.objectsInfo.dirObjects
      this.fileDataSource.dataArray = this.objectsInfo.fileObjects
    } else {
      this.dirDataSource.dataArray = this.objectsInfo.dirObjects.filter((item: ObjectInfo) => {
        return item.name.toLowerCase().includes(keyword)
      })
      this.fileDataSource.dataArray = this.objectsInfo.fileObjects.filter((item: ObjectInfo) => {
        return item.name.toLowerCase().includes(keyword)
      })
    }
    this.dirDataSource.size = this.dirDataSource.dataArray.length
    this.fileDataSource.size = this.fileDataSource.dataArray.length
    this.isGridPadding = this.getFolderPaddingCount() > 0
    this.dirDataSource.notifyDataReload()
    this.fileDataSource.notifyDataReload()
  }

  getGridColumns(): number {
    return FileGridLayout.getColumns(this.gridWidth, this.showType)
  }

  getGridColumnsTemplate(): string {
    return FileGridLayout.getColumnsTemplate(this.gridWidth, this.showType)
  }

  getFolderPaddingCount(): number {
    return FileGridLayout.getPaddingCount(
      this.dirDataSource.totalCount(), this.gridWidth, this.showType)
  }

  getFolderPaddingItems(): number[] {
    const count = this.getFolderPaddingCount()
    let items: number[] = []
    for (let index = 0; index < count; index++) {
      items.push(index)
    }
    return items
  }

  getGridSpacerItems(): number[] {
    const columns = this.getGridColumns()
    let items: number[] = []
    for (let index = 0; index < columns; index++) {
      items.push(index)
    }
    return items
  }

  updateHeaderGlassState(): void {
    const scrollOffset = Math.max(CloudThemeToken.zero, this.scrollerForList.currentOffset().yOffset)
    const collapseDistance = this.getHeaderCollapseDistance()
    const nextProgress = Math.min(CloudThemeToken.fullOpacity, Math.max(CloudThemeToken.zero,
      scrollOffset / collapseDistance))
    this.lastHeaderScrollOffset = scrollOffset
    if (Math.abs(this.headerCollapseProgress - nextProgress) >= CloudThemeToken.scrollProgressUpdateThreshold) {
      this.headerCollapseProgress = nextProgress
    }
    const active = nextProgress > CloudThemeToken.zero
    if (this.isHeaderGlassActive !== active) {
      this.isHeaderGlassActive = active
    }
  }

  resetHeaderScrollState(): void {
    this.isHeaderGlassActive = false
    this.headerCollapseProgress = 0
    this.lastHeaderScrollOffset = 0
  }

  getTopInset(): number {
    return CloudThemeToken.getSafeTopInset(this.topRectHeight)
  }

  getHeaderCollapseDistance(): number {
    return CloudThemeToken.pageTopPadding + CloudThemeToken.iconButtonSize
  }

  getSearchHeaderVisibleProgress(): number {
    return CloudThemeToken.fullOpacity - this.headerCollapseProgress
  }

  getTitleHeaderVisibleProgress(): number {
    if (this.isMultiSelectMode) {
      return CloudThemeToken.zero
    }
    return this.getSearchHeaderVisibleProgress()
  }

  getTitleBarMaterialOpacity(): number {
    if (this.isMultiSelectMode) {
      return CloudThemeToken.fullOpacity
    }
    return this.headerCollapseProgress * CloudThemeToken.filesHeaderGlassMaxOpacity
  }

  getHeaderCollapsedOffset(): number {
    return (CloudThemeToken.iconButtonSize + CloudThemeToken.spacingCard) * this.headerCollapseProgress
  }

  getSearchHeaderBottomGap(): number {
    return CloudThemeToken.spacingCard
  }

  getSearchHeaderTranslateY(): number {
    return -(CloudThemeToken.pageTopPadding + CloudThemeToken.iconButtonSize) * this.headerCollapseProgress
  }

  getTitleHeaderTranslateY(): number {
    return -this.getHeaderCollapsedOffset()
  }

  getTitleHeaderHeight(): number {
    return CloudThemeToken.filesTitleHeight * this.getTitleHeaderVisibleProgress()
  }

  getTitleSearchGap(): number {
    if (this.isMultiSelectMode) {
      return CloudThemeToken.zero
    }
    return CloudThemeToken.spacingCard * this.getSearchHeaderVisibleProgress()
  }

  getHeaderContentHeight(): number {
    return CloudThemeToken.zero
  }

  getHdsTitleBarBaseHeight(): number {
    return this.getTopInset() + CloudThemeToken.rowHeight5xl
  }

  getHeaderContainerHeight(): number {
    return this.getHdsTitleBarBaseHeight() + this.getHeaderContentHeight()
  }

  getExpandedHeaderContainerHeight(): number {
    return this.getHdsTitleBarBaseHeight()
  }

  getGridTopPadding(): number {
    return this.getHeaderContainerHeight() + CloudThemeToken.filesGridTopGap
  }

  getGridTopSpacerHeight(): number {
    return Math.max(CloudThemeToken.zero, this.getGridTopPadding() - CloudThemeToken.gridGap)
  }

  getFileContentTopPadding(): number {
    return this.getExpandedHeaderContainerHeight() + CloudThemeToken.filesGridTopGap
  }

  getTitleBackIcon(): Resource {
    if (this.isMultiSelectMode) {
      return $r('app.media.ic_xmark_bold')
    }
    return $r('app.media.ic_back')
  }

  getFileTitleStackLeftPadding(): number {
    // 返回按钮已经内嵌到 Row 里，padding 只管基础边距 + sidebar 折叠时给折叠按钮让位
    let pad = CloudThemeToken.filesTitleHorizontalPadding
    const bp = CloudThemeToken.getBreakpoint(this.sheetLayoutWidth)
    if (CloudThemeToken.isWideBreakpoint(bp) && !this.sidebarVisible) {
      pad += CloudThemeToken.sideBarToggleSize + CloudThemeToken.spacingCard
    }
    return pad
  }

  // FAB 底部 margin：手机端浮在底部 tab bar 之上 + 间距；wide 端无 tab bar，靠 safe area 即可
  getFabBottomMargin(): number {
    const bp = CloudThemeToken.getBreakpoint(this.sheetLayoutWidth)
    if (this.isMultiSelectMode || CloudThemeToken.isWideBreakpoint(bp)) {
      return this.bottomRectHeight + CloudThemeToken.spacingPage
    }
    return this.bottomRectHeight + CloudThemeToken.hdsTabBarBottomMargin +
      this.tabBarHeight + CloudThemeToken.spacingPage
  }

  getFileTitleStackRightPadding(): number {
    return CloudThemeToken.filesTitleHorizontalPadding + CloudThemeToken.rowHeight5xl * this.getFileTitleMenu().length
  }

  getStorageHeaderTranslateY(): number {
    return -CloudThemeToken.filesHeaderCollapsedContentLift * this.headerCollapseProgress
  }

  getRefreshPullDistance(): number {
    return this.isRefreshing ? CloudThemeToken.refreshOffset : Math.max(CloudThemeToken.zero, this.refreshPullOffset)
  }

  getRefreshHintTop(): number {
    const hintHeight = CloudThemeToken.iconBoxSm
    const centeredOffset = Math.max(CloudThemeToken.zero, this.getRefreshPullDistance() - hintHeight) / 2
    return this.getGridTopPadding() + centeredOffset
  }

  getRefreshHintOpacity(): number {
    if (this.isRefreshing) {
      return CloudThemeToken.fullOpacity
    }
    return Math.min(CloudThemeToken.fullOpacity,
      Math.max(CloudThemeToken.zero, this.refreshPullOffset / CloudThemeToken.refreshOffset))
  }

  shouldShowRefreshHint(): boolean {
    return !this.isFilePageLoading() &&
      (this.isRefreshing || this.refreshPullOffset > CloudThemeToken.spacingSm)
  }

  getHeaderTopPadding(): number {
    return this.getTopInset() + CloudThemeToken.pageTopPadding
  }

  getHeaderBottomPadding(): number {
    return CloudThemeToken.zero
  }

  onBackPressedCallback(): boolean {
    console.debug(TAG, 'onBackPressedCallback ....')
    if (this.currentPath === '/') {
      return false
    }

    this.getFileList(true, CommonUtil.getDirectoryPath((this.currentPath)))
    return true
  }

  aboutToAppear() {
    this.loadCurrentUser()
    this.loadedAccountScope = ActiveAccount.current()
    this.fileDataSource.onDataGet = (index: number, item: ObjectInfo) => {
      //console.debug(TAG, `onDataGet: index:${index}`)
      this.getThumbFile(index, item)
    }
    CloudRouter.setHomeBackHandler(() => {
      return this.onBackPressedCallback()
    })
    if (!this.initialFileListRequested) {
      this.initialFileListRequested = true
      this.getFileList(true, '/')
      this.restoreTransfers()
    }
    this.registerKnockReceive()
  }

  aboutToDisappear(): void {
    this.unregisterKnockReceive()
    // 兜底:组件销毁时详情面板可能未走完关闭流程,监听未及反注册
    harmonyShare.off('knockShare', this.detailKnockShareCallback)
  }

  // ---- 碰一碰沙箱接收(平板/2in1 作为接收端):手机轻碰屏幕,文件进沙箱后自动上传到当前目录 ----

  private knockRecvRegistry: harmonyShare.RecvCapabilityRegistry | null = null

  private async registerKnockReceive(): Promise<void> {
    // dataReceive 仅 PC/2in1/Tablet 作为接收端支持,其他设备注册无响应,这里直接跳过
    if (deviceInfo.deviceType !== 'tablet' && deviceInfo.deviceType !== '2in1') {
      return
    }
    const context = this.getAbilityContext()
    if (!context || this.knockRecvRegistry) {
      return
    }
    try {
      const win = await window.getLastWindow(context)
      const registry: harmonyShare.RecvCapabilityRegistry = {
        windowId: win.getWindowProperties().id,
        capabilities: [
          { utd: uniformTypeDescriptor.UniformDataType.IMAGE, maxSupportedCount: 9 },
          { utd: uniformTypeDescriptor.UniformDataType.VIDEO, maxSupportedCount: 9 },
          { utd: uniformTypeDescriptor.UniformDataType.FILE, maxSupportedCount: 9 }
        ]
      }
      harmonyShare.on('dataReceive', registry, this.knockDataReceiveCallback)
      this.knockRecvRegistry = registry
      AppLogger.info(TAG, 'knock dataReceive registered')
    } catch (err) {
      AppLogger.warn(TAG, `register knock receive failed: ${(err as Error)?.message ?? err}`)
    }
  }

  private unregisterKnockReceive(): void {
    if (!this.knockRecvRegistry) {
      return
    }
    try {
      harmonyShare.off('dataReceive', this.knockRecvRegistry, this.knockDataReceiveCallback)
    } catch (err) {
      AppLogger.warn(TAG, `unregister knock receive failed: ${(err as Error)?.message ?? err}`)
    }
    this.knockRecvRegistry = null
  }

  private knockDataReceiveCallback = (receivableTarget: harmonyShare.ReceivableTarget): void => {
    this.handleKnockDataReceive(receivableTarget)
  }

  private async handleKnockDataReceive(receivableTarget: harmonyShare.ReceivableTarget): Promise<void> {
    try {
      const context = this.getAbilityContext()
      const receiveDir = context ? KnockShareUtil.prepareReceiveDir(context.filesDir) : ''
      if (receiveDir.length === 0) {
        await receivableTarget.reject(harmonyShare.ReceivableErrorCode.NO_RECEIVABLE_ERROR)
        return
      }
      await receivableTarget.receive(FileSystemUtil.getUriFromPath(receiveDir), {
        onDataReceived: (sharedData: systemShare.SharedData) => {
          const uris: string[] = []
          sharedData.getRecords().forEach((record: systemShare.SharedRecord) => {
            if (record.uri && record.uri.length > 0) {
              uris.push(record.uri)
            }
          })
          if (uris.length > 0) {
            showToast(`碰一碰收到 ${uris.length} 个文件，开始上传`)
            this.startUpload(uris)
          }
        },
        onResult: (resultCode: harmonyShare.ShareResultCode) => {
          if (resultCode !== harmonyShare.ShareResultCode.SHARE_SUCCESS &&
            resultCode !== harmonyShare.ShareResultCode.CANCEL_BY_RECEIVER) {
            AppLogger.warn(TAG, `knock receive failed, result=${resultCode}`)
            showToast('碰一碰接收未完成')
          }
        }
      })
    } catch (err) {
      AppLogger.error(TAG, `knock receive failed: ${(err as Error)?.message ?? err}`)
    }
  }

  private loadCurrentUser(): void {
    this.currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string
    this.currentUrl = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string
    this.thumbSource = FileThumbSourceCache.snapshot(this.getThumbScopeKey())
  }

  private getThumbScopeKey(): string {
    return `${this.currentUrl}|${this.currentUser}|`
  }

  private getThumbCacheKey(item: ObjectInfo): string {
    return `${this.getThumbScopeKey()}${item.id}`
  }

  private resetThumbQueue(): void {
    if (this.thumbQueueTimer >= 0) {
      clearTimeout(this.thumbQueueTimer)
      this.thumbQueueTimer = -1
    }
    this.thumbQueue = []
    this.thumbLoadingIds.clear()
    this.thumbFailedIds.clear()
    this.activeThumbLoads = 0
    this.prioritizeNewestThumbRequests = false
  }

  private cancelScheduledShareRefresh(): void {
    if (this.shareRefreshTimer >= 0) {
      clearTimeout(this.shareRefreshTimer)
      this.shareRefreshTimer = -1
    }
  }

  private enterMultiSelectMode(): void {
    this.isMultiSelectMode = true
    this.selectedObjects = []
    this.overLap = false
  }

  private exitMultiSelectMode(): void {
    this.isMultiSelectMode = false
    this.selectedObjects = []
    this.overLap = true
  }

  private isObjectSelected(item: ObjectInfo): boolean {
    return this.selectedObjects.some((selected: ObjectInfo) => selected.id === item.id)
  }

  private toggleObjectSelection(item: ObjectInfo): void {
    if (this.isObjectSelected(item)) {
      this.selectedObjects = this.selectedObjects.filter((selected: ObjectInfo) => selected.id !== item.id)
    } else {
      this.selectedObjects = this.selectedObjects.concat([item])
    }
  }

  private selectAllVisibleObjects(): void {
    this.selectedObjects = this.dirDataSource.dataArray.concat(this.fileDataSource.dataArray)
  }

  // 当前已选 id 集合(按需从 selectedObjects 构造)
  private currentSelectedIds(): Set<string> {
    const s = new Set<string>()
    this.selectedObjects.forEach((o: ObjectInfo) => s.add(o.id))
    return s
  }
  // 用新的已选 id 集合刷新 selectedObjects(只保留当前显示中的项)
  private applySelectionIds(ids: Set<string>): void {
    const all: ObjectInfo[] = this.dirDataSource.dataArray.concat(this.fileDataSource.dataArray)
    this.selectedObjects = all.filter((o: ObjectInfo) => ids.has(o.id))
  }

  // 鼠标框选回调(additive;未进多选时自动进入)
  private onBoxSelect(item: ObjectInfo, isSelected: boolean): void {
    if (!this.isMultiSelectMode) {
      this.enterMultiSelectMode()
    }
    const ids = this.currentSelectedIds()
    if (isSelected) {
      ids.add(item.id)
    } else {
      ids.delete(item.id)
    }
    this.applySelectionIds(ids)
  }
  private getSelectedCountText(): string {
    return `已选 ${this.selectedObjects.length} 项`
  }

  private decodeSharePath(value: string): string {
    let result = value
    for (let index = 0; index < 2; index++) {
      try {
        const decoded = decodeURIComponent(result)
        if (decoded === result) {
          break
        }
        result = decoded
      } catch (err) {
        break
      }
    }
    return result
  }

  private normalizeSharePath(value: string): string {
    let path = (value ?? '').trim()
    if (path.length === 0) {
      return ''
    }
    const queryIndex = path.indexOf('?')
    if (queryIndex >= 0) {
      path = path.substring(0, queryIndex)
    }
    const hashIndex = path.indexOf('#')
    if (hashIndex >= 0) {
      path = path.substring(0, hashIndex)
    }
    if (path.startsWith('cloudreve://')) {
      const rest = path.substring('cloudreve://'.length)
      const myIndex = rest.indexOf('@my')
      if (myIndex >= 0) {
        path = rest.substring(myIndex + 3)
      } else if (rest.startsWith('my')) {
        path = rest.substring(2)
      } else {
        path = rest
      }
    }
    path = this.decodeSharePath(path).split('\\').join('/')
    while (path.startsWith('//')) {
      path = path.substring(1)
    }
    if (!path.startsWith('/')) {
      path = `/${path}`
    }
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1)
    }
    return path
  }

  private getObjectSharePath(item: ObjectInfo): string {
    const rawPath = this.isObjectIdPath(item) ? item.id : CloudApi.getTotalPath(item)
    return this.normalizeSharePath(rawPath)
  }

  private isObjectIdPath(item: ObjectInfo): boolean {
    return item.id.startsWith('/') || item.id.startsWith('cloudreve://')
  }

  private getShareFullPath(link: ShareLinkInfo): string {
    const candidates: string[] = [
      link.source_uri ?? '',
      link.uri ?? '',
      link.path ?? '',
      link.source?.source_uri ?? '',
      link.source?.uri ?? '',
      link.source?.path ?? '',
      link.file?.source_uri ?? '',
      link.file?.uri ?? '',
      link.file?.path ?? '',
      link.object?.source_uri ?? '',
      link.object?.uri ?? '',
      link.object?.path ?? ''
    ]
    for (let index = 0; index < candidates.length; index++) {
      const path = this.normalizeSharePath(candidates[index])
      if (path.length > 0) {
        return this.completeShareFullPath(link, path)
      }
    }
    return ''
  }

  private completeShareFullPath(link: ShareLinkInfo, path: string): string {
    if (!link.name || link.name.length === 0) {
      return path
    }
    const lastSeparator = path.lastIndexOf('/')
    const lastSegment = lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path
    if (lastSegment === link.name) {
      return path
    }
    return path === '/' ? `/${link.name}` : `${path}/${link.name}`
  }

  // For path matching only — returns the canonical full path that should equal
  // the object's id for v4 / cloudreve URIs. Kept for compatibility with existing
  // `sharedPaths` consumers.
  private getSharePath(link: ShareLinkInfo): string {
    return this.getShareFullPath(link)
  }

  private isShareTypeMatched(link: ShareLinkInfo, item: ObjectInfo): boolean {
    const isDir = item.type === Constant.OBJECT_DIR_TYPE
    if (link.source_type === undefined) {
      return true
    }
    const sourceType = `${link.source_type}`.toLowerCase()
    return isDir ? sourceType === '1' || sourceType === 'folder' :
      sourceType === '0' || sourceType === 'file'
  }

  // Whether a share whose source path is unknown (v3, or v4 enrichment failed)
  // should still light up the icon for an item with the same name.
  private isShareNameOnlyMatched(link: ShareLinkInfo, item: ObjectInfo): boolean {
    if (this.getShareFullPath(link).length > 0) {
      return false
    }
    const linkName = (link.name ?? link.source?.name ?? '').trim()
    if (linkName.length === 0) {
      return false
    }
    return linkName === item.name && this.isShareTypeMatched(link, item)
  }

  private getShareForObject(item: ObjectInfo): ShareLinkInfo | undefined {
    const itemFullPath = this.getObjectSharePath(item)
    const itemParent = this.normalizeSharePath(item.path)
    return this.shareLinks.find((link: ShareLinkInfo) => {
      if (!this.isShareTypeMatched(link, item)) {
        return false
      }
      const sharePath = this.getShareFullPath(link)
      if (sharePath.length > 0) {
        if (sharePath === itemFullPath) {
          return true
        }
        // Fallback when source_uri is the parent folder rather than the file
        // path: e.g. v4 file share whose source_uri = `cloudreve://my/folder`
        // and link.name = `file.png` — we then compare parent + name instead.
        const linkName = (link.name ?? '').trim()
        if (linkName.length > 0 && linkName === item.name && sharePath === itemParent) {
          return true
        }
        return false
      }
      // No path info (e.g. v3 shares only expose source.name) — match by name+type.
      return this.isShareNameOnlyMatched(link, item)
    })
  }

  private rebuildSharedPaths(links: ShareLinkInfo[]): string[] {
    const paths: string[] = []
    links.forEach((link: ShareLinkInfo) => {
      const path = this.getShareFullPath(link)
      if (path.length > 0 && !paths.includes(path)) {
        paths.push(path)
      }
    })
    return paths
  }

  private isSharedObject(item: ObjectInfo): boolean {
    return this.getShareForObject(item) !== undefined
  }

  private refreshShareLinks(): void {
    if (!this.isActive && !this.showShareSheet) {
      return
    }
    CloudApi.listShareLinks<ShareLinkInfo[]>({
      onSuccess: (data: ShareLinkInfo[]) => {
        // Keep expired shares too so the file still shows a badge; the share
        // sheet surfaces "已过期" status when the user opens it.
        const links = data ? data.slice() : []
        this.shareLinks = links
        this.sharedPaths = this.rebuildSharedPaths(links)
        AppLogger.debug(TAG, `share links loaded=${links.length}, paths=${this.sharedPaths.join('|')}, ` +
          `names=${links.map((l: ShareLinkInfo) => `${l.name}#${l.source_type}`).join(',')}`)
        if (this.showShareSheet && this.shareTarget) {
          const existing = this.getShareForObject(this.shareTarget)
          if (existing) {
            this.shareLinkText = existing.url ?? ''
          }
        }
      },
      onFailure: (msg: string) => {
        // Keep the last known list — a transient failure (e.g. token refresh
        // race) used to wipe every share badge and made existing shares open
        // as "创建分享".
        AppLogger.warn(TAG, 'share list refresh failed, keeping stale data: ' + msg)
      }
    })
  }

  private scheduleShareLinksRefresh(): void {
    if (!this.isActive && !this.showShareSheet) {
      return
    }
    this.cancelScheduledShareRefresh()
    this.shareRefreshTimer = setTimeout(() => {
      this.shareRefreshTimer = -1
      this.refreshShareLinks()
    }, this.showShareSheet ? 0 : FILE_SHARE_REFRESH_DELAY_MS)
  }

  async getThumbFile(index: number, item: ObjectInfo) {
    if (!this.isActive) {
      return
    }
    if (!item.thumb || this.getThumbData(item.id) || this.getThumbSourceData(item.id).length > 0) {
      return
    }
    const cachedSource = FileThumbSourceCache.get(this.getThumbCacheKey(item))
    if (cachedSource.length > 0) {
      this.setThumbSourceData(item, cachedSource)
      return
    }
    if (this.thumbLoadingIds.has(item.id) || this.thumbFailedIds.has(item.id)) {
      return
    }
    if (this.thumbQueue.find((queued: ObjectInfo) => queued.id === item.id)) {
      return
    }
    this.thumbQueue.push(item)
    if (this.thumbQueue.length > FILE_THUMB_QUEUE_MAX) {
      if (this.prioritizeNewestThumbRequests) {
        this.thumbQueue.shift()
      } else {
        this.thumbQueue.pop()
      }
    }
    this.scheduleThumbQueue()
  }

  private scheduleThumbQueue(): void {
    if (!this.isActive) {
      return
    }
    if (this.thumbQueueTimer >= 0) {
      return
    }
    this.thumbQueueTimer = setTimeout(() => {
      this.thumbQueueTimer = -1
      this.processThumbQueue()
    }, FILE_THUMB_QUEUE_DELAY_MS)
  }

  private processThumbQueue(): void {
    if (!this.isActive) {
      return
    }
    while (this.activeThumbLoads < FILE_THUMB_MAX_CONCURRENT && this.thumbQueue.length > 0) {
      // 首屏还未滚动时 FIFO，保证顶部图片先出现；滚动后 LIFO，避免当前屏被旧请求阻塞。
      const item = this.prioritizeNewestThumbRequests ? this.thumbQueue.pop() : this.thumbQueue.shift()
      if (!item) {
        continue
      }
      if (this.getThumbSourceData(item.id).length > 0 || this.thumbLoadingIds.has(item.id)) {
        continue
      }
      this.activeThumbLoads++
      this.thumbLoadingIds.add(item.id)
      this.loadThumbSource(item)
        .then((source: string) => {
          if (source.length > 0) {
            this.setThumbSourceData(item, source)
          }
          this.finishThumbLoad(item)
        }, (err: Error) => {
          this.thumbFailedIds.add(item.id)
          AppLogger.error(TAG, `Get thumb failed: ${err.message}`)
          this.finishThumbLoad(item)
        })
    }
  }

  private finishThumbLoad(item: ObjectInfo): void {
    this.thumbLoadingIds.delete(item.id)
    this.activeThumbLoads = Math.max(0, this.activeThumbLoads - 1)
    if (this.isActive) {
      this.processThumbQueue()
    }
  }

  private loadThumbSource(item: ObjectInfo): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      CloudApi.getThumb(item.id, {
        onSuccess: (url: string) => {
          resolve(url)
        },
        onFailure: (msg: string) => {
          reject(new Error(msg))
        }
      })
    })
  }

  async getFileList(isRefresh: boolean, path: string, fromPullRefresh: boolean = false) {
    if (this.loadingFilePath === path) {
      return
    }
    this.loadingFilePath = path
    const isSamePath = path === this.currentPath
    if (!isSamePath) {
      AppLogger.info(TAG, `enter dir ${path}`)
      this.exitMultiSelectMode()
    }
    const hasVisibleData = this.dirDataSource.totalCount() > 0 || this.fileDataSource.totalCount() > 0
    const shouldKeepContent = isRefresh && isSamePath && hasVisibleData
    if (path === '/') {
      this.isRoot = true
    }
    else {
      this.isRoot = false
    }
    this.currentPath = path
    this.mainTitle = this.isRoot ? $r('app.string.files_main_title') : CommonUtil.getLastDirectoryName(path)
    // 请求发出后可能被账号切换打断，回来的是上一账号的目录，不能再往界面上写
    const requestScope = this.loadedAccountScope
    CloudApi.getFilesInfo(path, {
      onStart: () => {
        if (requestScope !== this.loadedAccountScope) {
          return
        }
        this.filePageState = shouldKeepContent ? FilePageState.IDLE : FilePageState.LOADING
        if (isRefresh && !shouldKeepContent) {
          this.dirDataSource.clear()
          this.fileDataSource.clear()
          this.thumbImage = new Map()
          this.thumbSource = FileThumbSourceCache.snapshot(this.getThumbScopeKey())
          this.resetThumbQueue()
          this.resetHeaderScrollState()
          this.scrollerForList.scrollEdge(Edge.Start)
        }
      },
      onSuccess: (data: DirectoryInfo) => {
        if (requestScope !== this.loadedAccountScope) {
          AppLogger.info(TAG, 'drop file list response from previous account')
          return
        }
        this.loadingFilePath = ''
        if (!shouldKeepContent) {
          this.searchKeyword = ''
        }
        this.subTitle = data.policy.name
        this.objectsInfo = new DirFileInfo(data.parent, data.objects, data.policy)
        this.objectsInfo.sortObjects(this.sortType, this.isSortTypeReverse(this.sortType))
        this.applyVisibleObjects()
        // 本页不可见时缩略图一律不请求（见 getThumbFile），记账等切回来再补
        this.thumbsDeferredUntilActive = !this.isActive
        this.isRefreshing = false
        this.refreshPullOffset = CloudThemeToken.zero
        this.filePageState = FilePageState.IDLE
        this.scheduleShareLinksRefresh()
        if (fromPullRefresh) {
          showToast('刷新成功')
        }
      },
      onFailure: (msg) => {
        if (requestScope !== this.loadedAccountScope) {
          return
        }
        this.loadingFilePath = ''
        if (ApiErrorUtil.isNetworkMessage(msg)) {
          showToast(NETWORK_ERROR_MESSAGE)
        } else {
          showToastTips($r('app.string.get_failed'), ToastType.Error)
        }
        //决定是否重新登录
        this.isRefreshing = false
        this.refreshPullOffset = CloudThemeToken.zero
        this.filePageState = shouldKeepContent ? FilePageState.IDLE : FilePageState.FAILED
      }
    })
  }

  private beginBatchOperation(title: string, total: number,
    previousSuccessCount: number = 0): BatchOperationControl {
    const control: BatchOperationControl = {
      canceled: false,
      paused: false,
      resumeWaiters: []
    }
    this.batchOperationTitle = title
    this.batchOperationTotal = total
    this.batchOperationProcessed = previousSuccessCount
    this.batchOperationSucceeded = previousSuccessCount
    this.batchOperationSkipped = 0
    this.batchOperationFailed = 0
    this.batchOperationInFlight = 0
    this.batchOperationPaused = false
    this.batchOperationCancelRequested = false
    this.batchOperationElapsedSeconds = 0
    this.activeBatchOperationControl = control
    this.batchOperationRunning = true
    this.batchOperationShownAt = 0
    if (this.batchOperationShowTimer >= 0) {
      clearTimeout(this.batchOperationShowTimer)
    }
    // 跑得够快的批次不弹面板，见 BATCH_SHEET_SHOW_DELAY_MS
    this.batchOperationShowTimer = setTimeout(() => {
      this.batchOperationShowTimer = -1
      // 已取消、或期间弹出了同名冲突确认（那层结束后会自己重新打开），这里都不插手
      if (!this.batchOperationRunning || this.activeBatchOperationControl !== control ||
        control.canceled || this.activeFileConflict) {
        return
      }
      this.batchOperationShownAt = Date.now()
      this.batchOperationSheetCtrl.requestOpen(
        () => this.batchOperationVisible,
        (value: boolean) => {
          this.batchOperationVisible = value
        })
    }, BATCH_SHEET_SHOW_DELAY_MS)
    if (this.batchOperationElapsedTimer >= 0) {
      clearInterval(this.batchOperationElapsedTimer)
    }
    this.batchOperationElapsedTimer = setInterval(() => {
      this.batchOperationElapsedSeconds++
    }, 1000)
    return control
  }

  private finishBatchOperation(control: BatchOperationControl): void {
    if (this.activeBatchOperationControl !== control) {
      return
    }
    this.batchOperationRunning = false
    this.activeBatchOperationControl = null
    if (this.batchOperationElapsedTimer >= 0) {
      clearInterval(this.batchOperationElapsedTimer)
      this.batchOperationElapsedTimer = -1
    }
    // 面板还没到点出现：取消这次显示，用户只会看到结果 toast
    if (this.batchOperationShowTimer >= 0) {
      clearTimeout(this.batchOperationShowTimer)
      this.batchOperationShowTimer = -1
    }
    this.batchOperationPaused = false
    control.resumeWaiters.forEach((resume: () => void) => resume())
    control.resumeWaiters = []
    this.hideBatchOperationSheet()
  }

  /**
   * 收起面板，但兑现最短驻留。
   * 延时期间若又开了新批次（比如解除占用后重试删除），交给新批次自己管，这里不再插手。
   */
  private hideBatchOperationSheet(): void {
    const shownAt = this.batchOperationShownAt
    this.batchOperationShownAt = 0
    const setVisible: (value: boolean) => void = (value: boolean) => {
      this.batchOperationVisible = value
    }
    if (!this.batchOperationVisible) {
      // 面板还没露面也要收：延迟显示的那一枪可能已经上膛了
      this.batchOperationSheetCtrl.requestClose(setVisible)
      return
    }
    const remain = shownAt > 0 ? BATCH_SHEET_MIN_VISIBLE_MS - (Date.now() - shownAt) : 0
    if (remain <= 0) {
      this.batchOperationSheetCtrl.requestClose(setVisible)
      return
    }
    setTimeout(() => {
      if (!this.batchOperationRunning) {
        this.batchOperationSheetCtrl.requestClose(setVisible)
      }
    }, remain)
  }

  private toggleBatchOperationPause(): void {
    const control = this.activeBatchOperationControl
    if (!this.batchOperationVisible || !control || control.canceled) {
      return
    }
    this.batchOperationPaused = !this.batchOperationPaused
    control.paused = this.batchOperationPaused
    if (!this.batchOperationPaused) {
      const waiters = control.resumeWaiters
      control.resumeWaiters = []
      waiters.forEach((resume: () => void) => resume())
    }
  }

  private cancelBatchOperation(): void {
    const control = this.activeBatchOperationControl
    if (!control || control.canceled) {
      return
    }
    control.canceled = true
    control.paused = false
    this.batchOperationCancelRequested = true
    this.batchOperationPaused = false
    const waiters = control.resumeWaiters
    control.resumeWaiters = []
    waiters.forEach((resume: () => void) => resume())
    this.cancelPendingFileConflicts()
    // 停止派发后立即退出半模态；少量已发请求在后台收尾，完成后统一刷新页面和统计结果。
    // 走 requestClose 才能连带撤销待打开的意图，否则面板会自己弹回来。
    this.batchOperationSheetCtrl.requestClose((value: boolean) => {
      this.batchOperationVisible = value
    })
  }

  private cancelPendingFileConflicts(): void {
    const active = this.activeFileConflict
    const queued = this.fileConflictQueue
    this.activeFileConflict = null
    this.fileConflictQueue = []
    this.fileConflictApplyAll = false
    this.closeFileConflictDialog()
    active?.resolve(FileConflictDecision.SKIP)
    queued.forEach((request: FileConflictRequest) => request.resolve(FileConflictDecision.SKIP))
  }

  private waitForBatchOperationResume(control: BatchOperationControl): Promise<void> {
    if (!control.paused || control.canceled) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve: () => void) => {
      control.resumeWaiters.push(resolve)
    })
  }

  /**
   * 分块跑批量操作：每块一个请求，块之间并发。
   *
   * 与 runBatchItems 的区别只在派发粒度——进度、暂停、取消的语义保持一致，
   * 只是取消的最小单位变成一块（已经发出去的那批仍会在服务端跑完）。
   */
  private async runBatchChunks(items: ObjectInfo[], title: string,
    chunkOperation: (chunk: ObjectInfo[]) => Promise<BatchItemResult[]>,
    previousSuccessCount: number = 0): Promise<BatchExecutionResult> {
    // 同一个对象决不能落进两个块：并发的两个请求会同时去删它，服务端给先到的
    // 那个加锁，后到的就撞上 40073 报"被占用"——占用者其实是我们自己。
    // 目录列表分页本来就可能在页边界重复吐同一条（native 的搜索也做了同样的去重）。
    const unique = new Map<string, ObjectInfo>()
    items.forEach((item: ObjectInfo) => {
      if (!unique.has(item.id)) {
        unique.set(item.id, item)
      }
    })
    const deduped: ObjectInfo[] = Array.from(unique.values())
    if (deduped.length !== items.length) {
      AppLogger.info(TAG, `batch dedup: ${items.length} -> ${deduped.length}`)
    }
    items = deduped

    const control = this.beginBatchOperation(title, previousSuccessCount + items.length, previousSuccessCount)
    const chunks: ObjectInfo[][] = []
    for (let index = 0; index < items.length; index += FILE_BATCH_CHUNK_SIZE) {
      chunks.push(items.slice(index, index + FILE_BATCH_CHUNK_SIZE))
    }
    const results: BatchItemResult[] = []
    let nextChunk = 0
    const runWorker = async (): Promise<void> => {
      while (nextChunk < chunks.length) {
        await this.waitForBatchOperationResume(control)
        if (control.canceled) {
          break
        }
        const chunk = chunks[nextChunk]
        nextChunk++
        this.batchOperationInFlight += chunk.length
        let chunkResults: BatchItemResult[]
        try {
          chunkResults = await chunkOperation(chunk)
        } catch (err) {
          const message = (err as Error)?.message ?? String(err)
          AppLogger.error(TAG, `batch chunk threw, size=${chunk.length}, msg=${message}`)
          chunkResults = chunk.map((item: ObjectInfo) =>
            ({ item: item, success: false, skipped: false, message: message } as BatchItemResult))
        }
        this.batchOperationInFlight = Math.max(0, this.batchOperationInFlight - chunk.length)
        chunkResults.forEach((result: BatchItemResult) => {
          results.push(result)
          this.batchOperationProcessed++
          if (result.skipped) {
            this.batchOperationSkipped++
          } else if (result.success) {
            this.batchOperationSucceeded++
          } else {
            this.batchOperationFailed++
          }
        })
      }
    }
    const workers: Promise<void>[] = []
    const workerCount = Math.min(FILE_BATCH_MAX_CONCURRENT, chunks.length)
    for (let index = 0; index < workerCount; index++) {
      workers.push(runWorker())
    }
    await Promise.all(workers)
    this.finishBatchOperation(control)
    return { results: results, canceled: control.canceled }
  }

  /**
   * 把一次批量请求的结果摊回逐项。服务端只点名失败的，所以块内其余项即成功。
   * 匹配用 id：V4 下它就是完整路径，V3 下是对象 id，与提交时用的标识一致。
   */
  private mapBatchOutcome(chunk: ObjectInfo[], outcome: BatchOutcome,
    treatMissingAsSuccess: boolean): BatchItemResult[] {
    const failures = new Map<string, BatchFailure>()
    const failed = outcome.failed ?? []
    failed.forEach((failure: BatchFailure) => failures.set(failure.path, failure))
    return chunk.map((item: ObjectInfo) => {
      const failure = failures.get(item.id)
      if (!failure) {
        return { item: item, success: true, skipped: false, message: '' } as BatchItemResult
      }
      const conflicts: FileLockConflict[] = (failure.tokens ?? []).map((token: string) =>
        ({ path: failure.path, token: token, type: 0 } as FileLockConflict))
      // 删除时"对象不存在"就是想要的结果，按幂等成功处理；移动/复制则不然，
      // 源没了是真失败。
      const missing = treatMissingAsSuccess && this.isObjectMissingMessage(failure.message)
      return {
        item: item,
        success: missing,
        skipped: false,
        message: failure.message,
        lockConflicts: conflicts
      } as BatchItemResult
    })
  }

  /** 整块请求本身就失败了（网络等），块内每项记同一个原因。 */
  private allChunkFailed(chunk: ObjectInfo[], message: string): BatchItemResult[] {
    return chunk.map((item: ObjectInfo) =>
      ({ item: item, success: false, skipped: false, message: message } as BatchItemResult))
  }

  private deleteChunk(chunk: ObjectInfo[]): Promise<BatchItemResult[]> {
    return new Promise<BatchItemResult[]>((resolve: (value: BatchItemResult[]) => void) => {
      const src = new ObjectSrc()
      chunk.forEach((item: ObjectInfo) => {
        if (item.type === Constant.OBJECT_DIR_TYPE) {
          src.dirs.push(item.id)
        } else {
          src.items.push(item.id)
        }
      })
      CloudApi.deleteObjectsBatch(src, {
        onSuccess: (outcome: BatchOutcome) => resolve(this.mapBatchOutcome(chunk, outcome, true)),
        onFailure: (msg: string) => {
          AppLogger.error(TAG, `batch delete chunk failed, size=${chunk.length}, msg=${msg}`)
          resolve(this.allChunkFailed(chunk, msg))
        }
      })
    })
  }

  private transferBatch(items: ObjectInfo[], type: FileMenuType,
    sourcePath: string, dst: string): Promise<BatchItemResult[]> {
    return new Promise<BatchItemResult[]>((resolve: (value: BatchItemResult[]) => void) => {
      const src = new ObjectSrc()
      items.forEach((item: ObjectInfo) => {
        if (item.type === Constant.OBJECT_DIR_TYPE) {
          src.dirs.push(item.id)
        } else {
          src.items.push(item.id)
        }
      })
      const isCopy = type === FileMenuType.COPY
      CloudApi.transferObjectsBatch(src, sourcePath, dst, isCopy, {
        onSuccess: (outcome: BatchOutcome) => resolve(this.mapBatchOutcome(items, outcome, false)),
        onFailure: (msg: string) => {
          AppLogger.error(TAG, `batch ${isCopy ? 'copy' : 'move'} failed, size=${items.length}, msg=${msg}`)
          resolve(this.allChunkFailed(items, msg))
        }
      })
    })
  }

  /**
   * 一块移动/复制。
   *
   * 同名冲突要一个个问用户，但"问"和"做"必须分开：先把整块的决策收齐，再把决定
   * 覆盖的那些整批删掉目标、整批复制过去。若边问边做，选了"全部覆盖"就会退化成
   * 每个文件一删一复制两次请求，几千个文件下来近万次，批量的意义全没了。
   */
  private async transferChunk(chunk: ObjectInfo[], type: FileMenuType, sourcePath: string,
    dst: string, destinationObjects: Map<string, ObjectInfo>): Promise<BatchItemResult[]> {
    const conflicting: ObjectInfo[] = []
    const pending: ObjectInfo[] = []
    chunk.forEach((item: ObjectInfo) => {
      if (destinationObjects.has(item.name)) {
        conflicting.push(item)
      } else {
        pending.push(item)
      }
    })

    const results: BatchItemResult[] = []
    // 覆盖前要清掉的目标同名项，以及它们各自属于哪个源项——删失败时好归因
    const staleTargets: ObjectInfo[] = []
    const targetOwner = new Map<string, ObjectInfo>()

    if (conflicting.length > 0) {
      const decisions: FileConflictDecision[] = await Promise.all(
        conflicting.map((item: ObjectInfo) => this.requestFileConflictDecision(item, dst)))
      conflicting.forEach((item: ObjectInfo, index: number) => {
        if (decisions[index] === FileConflictDecision.SKIP) {
          results.push({ item: item, success: false, skipped: true, message: '已跳过同名项目' })
          return
        }
        const existing = destinationObjects.get(item.name)
        if (existing) {
          staleTargets.push(existing)
          targetOwner.set(existing.id, item)
          destinationObjects.delete(item.name)
        }
        pending.push(item)
      })
    }

    if (staleTargets.length > 0) {
      const removed = await this.deleteChunk(staleTargets)
      const blocked = new Set<string>()
      removed.forEach((result: BatchItemResult) => {
        if (result.success) {
          return
        }
        const owner = targetOwner.get(result.item.id)
        if (!owner) {
          return
        }
        blocked.add(owner.id)
        results.push({
          item: owner,
          success: false,
          skipped: false,
          message: `覆盖前删除目标同名项目失败：${result.message}`
        })
      })
      // 目标没清掉就别复制了，否则服务端还是会以重名顶回来
      for (let index = pending.length - 1; index >= 0; index--) {
        if (blocked.has(pending[index].id)) {
          pending.splice(index, 1)
        }
      }
    }

    if (pending.length > 0) {
      const mapped = await this.transferBatch(pending, type, sourcePath, dst)
      for (let index = 0; index < mapped.length; index++) {
        const result = mapped[index]
        if (!result.success && ApiErrorUtil.isObjectExisted(result.message)) {
          results.push(await this.resolveLateConflict(result.item, type, sourcePath, dst))
        } else {
          results.push(result)
        }
      }
    }
    return results
  }

  /**
   * 预检没看见、被服务端以"已存在"顶回来的重名。
   *
   * 目标目录列表可能被分页截断，所以这条兜底路径仍然需要——但它是少数派，
   * 逐项处理不影响整体。
   */
  private async resolveLateConflict(item: ObjectInfo, type: FileMenuType,
    sourcePath: string, dst: string): Promise<BatchItemResult> {
    const existing = await this.findDestinationObject(item.name, dst)
    if (!existing) {
      return { item: item, success: false, skipped: false, message: '目标位置已存在同名项目' }
    }
    const decision = await this.requestFileConflictDecision(item, dst)
    if (decision === FileConflictDecision.SKIP) {
      return { item: item, success: false, skipped: true, message: '已跳过同名项目' }
    }
    const deleteMessage = await this.deleteDestinationObject(existing)
    if (deleteMessage.length > 0) {
      return { item: item, success: false, skipped: false, message: deleteMessage }
    }
    return this.executeCopyMoveItem(item, type, sourcePath, dst)
  }

  copyMoveObjects(dst: string) {
    const items = this.objectSelect.copyMoveObjects?.slice() ?? []
    if (items.length === 0) {
      return
    }
    const type = this.objectSelect.type
    const sourcePath = this.currentPath
    this.runCopyMoveItems(items, type, sourcePath, dst)
  }

  private async runCopyMoveItems(items: ObjectInfo[], type: FileMenuType,
    sourcePath: string, dst: string): Promise<void> {
    const isCopy = type === FileMenuType.COPY
    const title = isCopy ? '正在复制' : '正在移动'
    const normalizedSource = sourcePath.length > 1 && sourcePath.endsWith('/') ?
      sourcePath.substring(0, sourcePath.length - 1) : sourcePath
    const normalizedDestination = dst.length > 1 && dst.endsWith('/') ?
      dst.substring(0, dst.length - 1) : dst
    if (normalizedSource === normalizedDestination) {
      showToast(isCopy ? '不能复制到当前目录' : '文件已在当前目录')
      return
    }
    this.resetFileConflictState()
    const probeStart = Date.now()
    const destinationObjects = await this.loadDestinationObjects(dst)
    AppLogger.info(TAG, `[timing] destination probe took ${Date.now() - probeStart}ms, ` +
      `entries=${destinationObjects.size}, items=${items.length}`)
    const execution = await this.runBatchChunks(items, title, (chunk: ObjectInfo[]) =>
      this.transferChunk(chunk, type, sourcePath, dst, destinationObjects))
    const results = execution.results
    const succeeded = results.filter((result: BatchItemResult) => result.success)
      .map((result: BatchItemResult) => result.item)
    const skipped = results.filter((result: BatchItemResult) => result.skipped)
      .map((result: BatchItemResult) => result.item)
    const failed = results.filter((result: BatchItemResult) => !result.success && !result.skipped)
      .map((result: BatchItemResult) => result.item)
    if (!isCopy && succeeded.length > 0) {
      this.removeDeletedObjectsFromPage(succeeded)
      this.recordBackupRemoved(
        succeeded.filter((item: ObjectInfo) => item.type !== Constant.OBJECT_DIR_TYPE)
          .map((item: ObjectInfo) => item.name))
      this.recordBackupDirRemoved(
        succeeded.filter((item: ObjectInfo) => item.type === Constant.OBJECT_DIR_TYPE)
          .map((item: ObjectInfo) => this.joinRemotePath(sourcePath, item.name)))
      this.getFileList(true, sourcePath)
    }
    const handledIds = new Set<string>(results.map((result: BatchItemResult) => result.item.id))
    const unprocessed = items.filter((item: ObjectInfo) => !handledIds.has(item.id))
    const remaining = skipped.concat(failed).concat(unprocessed)
    this.selectedObjects = remaining
    this.objectSelect.copyMoveObjects = remaining
    if (remaining.length === 0) {
      this.exitMultiSelectMode()
    }
    const action = isCopy ? '复制' : '移动'
    // 只报成功数。没成的那些仍然留在选中态里，用户在列表上看得见，
    // 不必再用一串数字复述一遍。
    showToast(execution.canceled
      ? `已取消${action}：成功 ${succeeded.length} 项`
      : `${action}成功 ${succeeded.length} 项`)
    this.resetFileConflictState()
  }

  private executeCopyMoveItem(item: ObjectInfo, type: FileMenuType,
    sourcePath: string, dst: string): Promise<BatchItemResult> {
    return new Promise<BatchItemResult>((resolve: (result: BatchItemResult) => void) => {
      const src = new ObjectSrc()
      if (item.type === Constant.OBJECT_DIR_TYPE) {
        src.dirs.push(item.id)
      } else {
        src.items.push(item.id)
      }
      const callback: HttpCallback<null> = {
        onSuccess: (_data: null) => resolve({ item: item, success: true, skipped: false, message: '' }),
        onFailure: (msg: string) => {
          AppLogger.error(TAG, `${type === FileMenuType.COPY ? 'copy' : 'move'} failed id=${item.id}, msg=${msg}`)
          resolve({ item: item, success: false, skipped: false, message: msg })
        }
      }
      if (type === FileMenuType.COPY) {
        CloudApi.copyObjects(new ObjectCopy(sourcePath, src, dst), callback)
      } else {
        CloudApi.moveObjects(new ObjectMove(sourcePath, src, dst), callback)
      }
    })
  }

  private loadDestinationObjects(path: string): Promise<Map<string, ObjectInfo>> {
    return new Promise<Map<string, ObjectInfo>>((resolve: (value: Map<string, ObjectInfo>) => void) => {
      CloudApi.getFilesInfo(path, {
        onSuccess: (data: DirectoryInfo) => {
          const objects = new Map<string, ObjectInfo>()
          const destinationItems = data.objects ?? []
          destinationItems.forEach((item: ObjectInfo) => objects.set(item.name, item))
          resolve(objects)
        },
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `load copy/move destination failed, conflict precheck degraded: ${msg}`)
          resolve(new Map<string, ObjectInfo>())
        }
      })
    })
  }

  private deleteDestinationObject(item: ObjectInfo): Promise<string> {
    return new Promise<string>((resolve: (message: string) => void) => {
      CloudApi.deleteObject(item.id, item.type === Constant.OBJECT_DIR_TYPE, {
        onSuccess: (_data: null) => resolve(''),
        onFailure: (msg: string) => {
          AppLogger.error(TAG, `overwrite delete destination failed id=${item.id}, msg=${msg}`)
          resolve(`覆盖前删除目标同名项目失败：${msg}`)
        }
      })
    })
  }

  private findDestinationObject(name: string, dst: string): Promise<ObjectInfo | null> {
    return new Promise<ObjectInfo | null>((resolve: (item: ObjectInfo | null) => void) => {
      const normalizedDst = dst.length > 1 && dst.endsWith('/') ? dst.substring(0, dst.length - 1) : dst
      CloudApi.searchFiles(name, dst, {
        onSuccess: (objects: ObjectInfo[]) => {
          const found = objects.find((item: ObjectInfo) => {
            const itemPath = item.path.length > 1 && item.path.endsWith('/') ?
              item.path.substring(0, item.path.length - 1) : item.path
            return item.name === name && itemPath === normalizedDst
          })
          resolve(found ?? null)
        },
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `locate copy/move conflict failed name=${name}, msg=${msg}`)
          resolve(null)
        }
      })
    })
  }

  private resetFileConflictState(): void {
    this.fileConflictPolicy = FileConflictPolicy.ASK
    this.fileConflictQueue = []
    this.activeFileConflict = null
    this.fileConflictApplyAll = false
    this.closeFileConflictDialog()
  }

  private requestFileConflictDecision(item: ObjectInfo, dst: string): Promise<FileConflictDecision> {
    if (this.fileConflictPolicy === FileConflictPolicy.SKIP_ALL) {
      return Promise.resolve(FileConflictDecision.SKIP)
    }
    if (this.fileConflictPolicy === FileConflictPolicy.OVERWRITE_ALL) {
      return Promise.resolve(FileConflictDecision.OVERWRITE)
    }
    return new Promise<FileConflictDecision>((resolve: (decision: FileConflictDecision) => void) => {
      this.fileConflictQueue.push({
        name: item.name,
        size: item.size ?? 0,
        isDir: item.type === Constant.OBJECT_DIR_TYPE,
        destination: dst,
        resolve: resolve
      })
      this.showNextFileConflict()
    })
  }

  private showNextFileConflict(): void {
    if (this.activeFileConflict || this.fileConflictQueue.length === 0) {
      return
    }
    if (this.fileConflictPolicy !== FileConflictPolicy.ASK) {
      const decision = this.fileConflictPolicy === FileConflictPolicy.SKIP_ALL ?
        FileConflictDecision.SKIP : FileConflictDecision.OVERWRITE
      const queued = this.fileConflictQueue
      this.fileConflictQueue = []
      queued.forEach((request: FileConflictRequest) => request.resolve(decision))
      return
    }
    this.activeFileConflict = this.fileConflictQueue.shift() ?? null
    if (this.activeFileConflict) {
      this.fileConflictApplyAll = false
      this.openFileConflictDialog()
    }
  }

  /**
   * 冲突确认走系统模态。
   *
   * 早先这里是页面内自绘的一层 Stack 子节点，看得见却点不动：它和同组件里的多个
   * bindSheet 抢同一件事，而两者根本不在一套事件体系里。交给 promptAction 之后，
   * 层级排序由系统负责，也不必再写"冲突时先收起进度面板"这类互斥编排。
   */
  private openFileConflictDialog(): void {
    if (this.fileConflictDialogId >= 0) {
      return
    }
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => {
        this.fileConflictDialog()
      },
      alignment: DialogAlignment.Center,
      // 只能通过按钮决策：点蒙层或返回键溜走会让等待中的 Promise 永远挂起
      autoCancel: false,
      maskColor: 'rgba(0, 0, 0, 0.55)',
      backgroundColor: Color.Transparent,
      cornerRadius: CloudThemeToken.controlRadiusXl,
      width: this.fileConflictDialogWidth()
    })
      .then((dialogId: number) => {
        this.fileConflictDialogId = dialogId
      })
      .catch((err: Error) => {
        AppLogger.error(TAG, `open conflict dialog failed: ${err.message ?? String(err)}`)
      })
  }

  private closeFileConflictDialog(): void {
    const dialogId = this.fileConflictDialogId
    if (dialogId < 0) {
      return
    }
    this.fileConflictDialogId = -1
    this.getUIContext().getPromptAction().closeCustomDialog(dialogId)
  }

  /** 窄屏留边，宽屏封顶，避免平板上拉成一条 */
  private fileConflictDialogWidth(): number {
    return Math.min(this.sheetLayoutWidth * 0.86, CONFLICT_DIALOG_MAX_WIDTH)
  }

  private resolveFileConflict(decision: FileConflictDecision, applyAll: boolean): void {
    if (applyAll) {
      this.fileConflictPolicy = decision === FileConflictDecision.SKIP ?
        FileConflictPolicy.SKIP_ALL : FileConflictPolicy.OVERWRITE_ALL
    }
    const active = this.activeFileConflict
    this.activeFileConflict = null
    this.fileConflictApplyAll = false
    this.closeFileConflictDialog()
    active?.resolve(decision)
    this.showNextFileConflict()
    if (!this.activeFileConflict && this.fileConflictQueue.length === 0 && this.batchOperationRunning &&
      !this.batchOperationCancelRequested) {
      // 冲突确认结束后重新露面，最短驻留重新计时
      this.batchOperationShownAt = Date.now()
      this.batchOperationSheetCtrl.requestOpen(
        () => this.batchOperationVisible,
        (value: boolean) => {
          this.batchOperationVisible = value
        })
    }
  }

  build() {
    HdsNavigation() {
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({alignContent: Alignment.BottomEnd}) {
          Refresh({
            refreshing: $$this.isRefreshing,
            builder: this.hiddenRefreshHint
          }) {
            this.objectGrid()
          }
          .width('100%')
          .height('100%')
          .refreshOffset(CloudThemeToken.refreshOffset)
          .pullToRefresh(true)
          .onOffsetChange((offset: number) => {
            this.refreshPullOffset = Math.max(CloudThemeToken.zero, offset)
          })
          .onRefreshing(async () => {
            await this.getFileList(true, this.currentPath, true);
          })

          if (this.shouldShowRefreshHint()) {
            this.refreshingHintOverlay()
          }

          if (this.isFilePageLoading()) {
            this.loadingState()
          }

          if (this.isFilePageFailed()) {
            this.failedState()
          }

          if (this.isCurrentDirectoryEmpty()) {
            this.emptyDirectoryState()
          }

          if (this.isSearchResultEmpty()) {
            this.searchEmptyState()
          }

          Button() {
            Image($r('app.media.ic_arrowshape_up'))
              .width(CloudThemeToken.icon3xl)
              .height(CloudThemeToken.icon3xl)
              .fillColor(CloudThemeToken.onPrimary)
          }
          .width(CloudThemeToken.iconBox3xl)
          .height(CloudThemeToken.rowHeight4xl)
          .borderRadius(CloudThemeToken.actionRadiusForWidth(this.sheetLayoutWidth,
            CloudThemeToken.controlRadiusRoundXl))
          .backgroundColor(CloudThemeToken.primary)
          .margin({ right: CloudThemeToken.spacingPage, bottom: this.getFabBottomMargin() })
          .onClick(() => { this.openSelectFileSheet() })
        }
        .width('100%')
        .height('100%')

        if (this.isMultiSelectMode) {
          this.multiSelectActionBar()
        }

        if (this.showFileMoreMenu) {
          this.fileMoreMenuOverlay()
        }

        if (this.albumSaving) {
          this.albumSavingOverlay()
        }

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showObjectDetail, this.detailBindSheet(), {
            detents: [SheetSize.FIT_CONTENT],
            title: { title: $r('app.string.detail_title') },
            showClose: true,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onWillAppear: () => {
              this.detailSheetCtrl.onWillAppear()
            },
            onAppear: () => {
              this.markSheetVisible()
              this.detailSheetCtrl.onAppear()
              harmonyShare.on('knockShare', this.detailKnockShareCallback)
            },
            onWillDisappear: () => {
              this.detailSheetCtrl.onWillDisappear()
            },
            onDisappear: () => {
              this.markSheetHidden()
              harmonyShare.off('knockShare', this.detailKnockShareCallback)
              this.detailSheetCtrl.onDisappear((value: boolean) => {
                this.showObjectDetail = value
              }, () => {
                this.showObjectDetail = false
              })
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showSelectFileSheet, this.selectFileSheetBuilder(), {
            detents: [SheetSize.FIT_CONTENT],
            title: { title: $r('app.string.upload') },
            showClose: true,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onWillAppear: () => {
              this.selectFileSheetCtrl.onWillAppear()
            },
            onAppear: () => {
              this.markSheetVisible()
              this.selectFileSheetCtrl.onAppear()
            },
            onWillDisappear: () => {
              this.selectFileSheetCtrl.onWillDisappear()
            },
            onDisappear: () => {
              this.markSheetHidden()
              this.selectFileSheetCtrl.onDisappear((value: boolean) => {
                this.showSelectFileSheet = value
              }, () => {
                this.showSelectFileSheet = false
              })
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showInputSheet, this.inputSheetBuilder(), {
            detents: [SheetSize.FIT_CONTENT],
            title: { title: this.inputTitle },
            showClose: true,
            // 单挡 FIT_CONTENT 下系统避让只保证光标可见，按钮仍被键盘挡住；
            // 改为关闭系统避让，由内容 padding 跟随键盘高度手动避让（见 inputSheetBuilder）
            keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onWillAppear: () => {
              this.inputSheetCtrl.onWillAppear()
            },
            onAppear: () => {
              this.markSheetVisible()
              this.inputSheetCtrl.onAppear()
              // 入场动画结束后再聚焦拉起键盘，动画期间弹键盘会错过 sheet 的避让时机
              this.applyInputSheetSelection()
            },
            onWillDisappear: () => {
              this.inputSheetCtrl.onWillDisappear()
            },
            onDisappear: () => {
              this.markSheetHidden()
              this.inputSheetCtrl.onDisappear((value: boolean) => {
                this.showInputSheet = value
              }, () => {
                this.showInputSheet = false
                this.resetInputSheetState()
              })
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showShareSheet, this.shareSheetBuilder(), {
            detents: [SheetSize.FIT_CONTENT],
            title: { title: this.shareLinkText.length > 0 ? '分享链接' : '创建分享' },
            showClose: true,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onWillAppear: () => {
              this.shareSheetCtrl.onWillAppear()
            },
            onAppear: () => {
              this.markSheetVisible()
              this.shareSheetCtrl.onAppear()
            },
            onWillDisappear: () => {
              this.shareSheetCtrl.onWillDisappear()
            },
            onDisappear: () => {
              this.markSheetHidden()
              this.shareSheetCtrl.onDisappear((value: boolean) => {
                this.showShareSheet = value
              }, () => {
                this.showShareSheet = false
                this.shareTarget = null
                this.shareLinkText = ''
                this.sharePassword = ''
                this.shareBusy = false
              })
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showTransportSheet, this.transportSheetBuilder(), {
            backgroundColor: CloudThemeToken.surface,
            title: { title: $r('app.string.transport_title') },
            showClose: true,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onWillAppear: () => {
              this.transportSheetCtrl.onWillAppear()
            },
            onAppear: () => {
              this.markSheetVisible()
              this.transportSheetCtrl.onAppear()
            },
            onWillDisappear: () => {
              this.transportSheetCtrl.onWillDisappear()
            },
            onDisappear: () => {
              this.markSheetHidden()
              this.transportSheetCtrl.onDisappear((value: boolean) => {
                this.showTransportSheet = value
              }, () => {
                this.showTransportSheet = false
              })
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.batchOperationVisible, this.batchOperationSheet(), {
            detents: [SheetSize.FIT_CONTENT],
            title: {
              title: this.batchOperationTitle,
              // 暂停状态由按钮自己说清楚（它会变成"继续"），不必再复述一遍
              subtitle: this.batchOperationPaused ? '已暂停' : undefined
            },
            showClose: false,
            enableOutsideInteractive: false,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            // 批处理只能由任务完成后主动关闭，避免返回、点击蒙层或下拉误关后失去进度入口。
            shouldDismiss: (_sheetDismiss: SheetDismiss) => {
            },
            onWillAppear: () => {
              this.batchOperationSheetCtrl.onWillAppear()
            },
            onAppear: () => {
              this.markSheetVisible()
              this.batchOperationSheetCtrl.onAppear()
            },
            onWillDisappear: () => {
              this.batchOperationSheetCtrl.onWillDisappear()
            },
            onDisappear: () => {
              this.markSheetHidden()
              this.batchOperationSheetCtrl.onDisappear((value: boolean) => {
                this.batchOperationVisible = value
              }, () => {
                this.batchOperationVisible = false
              })
            }
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.background)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: this.isMultiSelectMode ? this.getSelectedCountText() : ' ',
          subTitle: this.isMultiSelectMode ? '选择文件后操作' : ' '
        },
        menu: {
          value: this.isMultiSelectMode ? this.getMultiSelectTitleMenu() : this.getFileTitleMenu(),
          maxCount: this.isMultiSelectMode ? 2 : 3
        },
        stackBuilder: () => {
          this.fileTitleBarStack()
        },
        divider: {
          showType: DividerShowType.OFF
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary,
              subTitleColor: CloudThemeToken.textSecondary
            },
            backIconStyle: {
              backgroundColor: this.getFileTitleActionBackground(),
              iconColor: this.getFileTitleActionIconColor()
            },
            menuStyle: {
              backgroundColor: this.getFileTitleActionBackground(),
              iconColor: this.getFileTitleActionIconColor(),
              textColor: this.getFileTitleActionIconColor()
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary,
              subTitleColor: CloudThemeToken.textSecondary
            },
            backIconStyle: {
              backgroundColor: this.getFileTitleActionBackground(),
              iconColor: this.getFileTitleActionIconColor()
            },
            menuStyle: {
              backgroundColor: this.getFileTitleActionBackground(),
              iconColor: this.getFileTitleActionIconColor(),
              textColor: this.getFileTitleActionIconColor()
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.scrollerForList])
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder multiSelectTitle() {
    Row({ space: CloudThemeToken.spacingCard }) {
      Button({ type: ButtonType.Normal }) {
        Text('取消')
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontColor(CloudThemeToken.textPrimary)
      }
      .height(CloudThemeToken.iconButtonSize)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .borderRadius(CloudThemeToken.controlRadius)
      .backgroundColor(CloudThemeToken.surfaceSubtle)
      .onClick(() => {
        this.exitMultiSelectMode()
      })

      Text(this.getSelectedCountText())
        .fontSize(CloudThemeToken.filesTitleMainSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button({ type: ButtonType.Normal }) {
        Text('全选')
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontColor(CloudThemeToken.primary)
      }
      .height(CloudThemeToken.iconButtonSize)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .borderRadius(CloudThemeToken.controlRadius)
      .backgroundColor(CloudThemeToken.primarySoft)
      .onClick(() => {
        this.selectAllVisibleObjects()
      })
    }
    .width('100%')
    .height(CloudThemeToken.filesTitleHeight)
    .padding({ left: CloudThemeToken.filesTitleHorizontalPadding, right: CloudThemeToken.filesTitleHorizontalPadding })
    .alignItems(VerticalAlign.Center)
  }

  @Builder multiSelectActionBar() {
    Column({ space: CloudThemeToken.spacingCard }) {
      Row() {
        Text(this.selectedObjects.length > 0 ? this.getSelectedCountText() : '选择文件后操作')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: CloudThemeToken.spacingCard }) {
        this.multiActionButton($r('app.media.ic_copy'), '复制', () => {
          this.startSelectedCopyMove(FileMenuType.COPY)
        })
        this.multiActionButton($r('app.media.ic_move_to'), '移动', () => {
          this.startSelectedCopyMove(FileMenuType.MOVE)
        })
        this.multiActionButton($r('app.media.ic_arrowshape_down'), '下载', () => {
          this.downloadSelectedObjects()
        })
        this.multiActionButton($r('app.media.ic_delete_fill'), '删除', () => {
          this.deleteSelectedObjects()
        }, true)
      }
      .width('100%')
      .height(CloudThemeToken.cardHeightSm)
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingPage,
      right: CloudThemeToken.spacingPage,
      top: CloudThemeToken.spacingSection,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom + CloudThemeToken.spacingSection
    })
    .margin({
      left: CloudThemeToken.zero,
      right: CloudThemeToken.zero,
      bottom: CloudThemeToken.zero
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.surfaceGlassStrong)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .shadow({
      radius: CloudThemeToken.sheetShadowRadius,
      color: CloudThemeToken.sheetShadow,
      offsetY: CloudThemeToken.sheetShadowOffsetY
    })
    .zIndex(CloudThemeToken.overlayZIndex)
    .onAreaChange((_o: Area, n: Area) => {
      this.multiSelectBarHeight = Number(n.height)
    })
  }

@Styles multiActionPressed() {
    .scale({ x: 0.94, y: 0.94 })
    .opacity(0.6)
  }

  @Styles multiActionNormal() {
    .scale({ x: 1.0, y: 1.0 })
    .opacity(1.0)
  }

  @Builder multiActionButton(icon: ResourceStr, title: string, action: () => void, danger: boolean = false) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: CloudThemeToken.spacingXs }) {
        Stack() {
          Image(icon)
            .width(CloudThemeToken.iconXl)
            .height(CloudThemeToken.iconXl)
            .fillColor(this.getMultiActionContentColor(danger))
            .draggable(false)
        }
        .width(CloudThemeToken.iconBoxXl)
        .height(CloudThemeToken.iconBoxXl)
        .borderRadius(CloudThemeToken.actionRadiusForWidth(this.sheetLayoutWidth,
          CloudThemeToken.controlRadiusRoundXl))
        .backgroundColor(this.getMultiActionBackground(danger))
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
        .shadow({
          radius: CloudThemeToken.refreshShadowRadius,
          color: danger ? 'rgba(255, 77, 79, 0.10)' : 'rgba(17, 93, 252, 0.10)',
          offsetY: CloudThemeToken.refreshShadowOffsetY
        })

        Text(title)
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(this.getMultiActionContentColor(danger))
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(CloudThemeToken.cardHeightSm)
    .borderRadius(CloudThemeToken.controlRadiusRoundXl)
    .backgroundColor('rgba(0, 0, 0, 0)')
    .hoverEffect(HoverEffect.None)
    .stateStyles({ pressed: this.multiActionPressed, normal: this.multiActionNormal })
    .enabled(this.selectedObjects.length > 0)
    .onClick(action)
    .opacity(this.selectedObjects.length > 0 ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
  }

  private getMultiActionBackground(danger: boolean): ResourceColor {
    return danger ? 'rgba(255, 77, 79, 0.12)' : 'rgba(17, 93, 252, 0.12)'
  }

  private getMultiActionContentColor(danger: boolean): ResourceColor {
    return danger ? CloudThemeToken.danger : CloudThemeToken.primary
  }

  @Builder fileTitleBarStack() {
    if (!this.isMultiSelectMode) {
      Stack() {
        Row({ space: CloudThemeToken.spacingCard }) {
          if (!this.isRoot) {
            CloudIconButton({
              icon: this.getTitleBackIcon(),
              buttonBackground: CloudThemeToken.surface,
              iconColor: CloudThemeToken.textPrimary,
              buttonRadius: CloudThemeToken.actionRadiusForWidth(this.sheetLayoutWidth,
                CloudThemeToken.controlRadius),
              onAction: () => {
                this.getFileList(true, CommonUtil.getDirectoryPath(this.currentPath))
              }
            })
          }

          Column({ space: CloudThemeToken.spacingTiny }) {
            Text(this.mainTitle)
              .fontSize(CloudThemeToken.textSizeHeadline)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.subTitle)
              .fontSize(CloudThemeToken.textSizeTiny)
              .fontColor(CloudThemeToken.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.None)
        }
        .layoutWeight(1)
        .width('100%')
        .height('100%')
        .padding({
          left: this.getFileTitleStackLeftPadding(),
          right: this.getFileTitleStackRightPadding()
        })
        .alignItems(VerticalAlign.Center)
        .translate({ y: CloudThemeToken.filesTitleBarContentOffsetY })
      }
      .width('100%')
      .height('100%')
      .animation({ duration: CloudThemeToken.filesHeaderTransitionDuration, curve: Curve.EaseOut })
    }
  }

  @Builder fileStorageHeaderOverlay() {
    if (!this.isMultiSelectMode) {
      Column() {
        Column({ space: CloudThemeToken.topBarTextGap }) {
          Text(this.mainTitle)
            .fontSize(CloudThemeToken.filesTitleMainSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.subTitle)
            .fontSize(CloudThemeToken.filesTitleSubtitleSize)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({
          left: CloudThemeToken.filesTitleHorizontalPadding,
          right: CloudThemeToken.filesTitleHorizontalPadding
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .height(this.getHeaderContentHeight())
        .clip(true)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getHdsTitleBarBaseHeight() })
      .opacity(this.getTitleHeaderVisibleProgress())
      .translate({ y: this.getStorageHeaderTranslateY() })
      .hitTestBehavior(HitTestMode.None)
      .zIndex(CloudThemeToken.filesHeaderZIndex)
    }
  }

  @Builder fileMoreMenuOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.transparent)
        .onClick(() => {
          this.closeFileMoreMenu()
        })

      Column() {
        Column() {
          // 用 checklist 图标而不是 ic_selected：后者是行尾表示"当前选中"的对勾，
          // 同一个菜单里拿它当"多选"入口，会被读成"多选这项已被选中"
          this.fileMoreCommonItem($r('app.string.more_multi_select'), $r('app.media.ic_multi_select'), false, () => {
            this.closeFileMoreMenu()
            this.onMoreClick(MoreMenuType.MULTI_SELECT)
          })
        }

        this.fileMoreGroupDivider()

        Column() {
          this.fileMoreCommonItem($r('app.string.more_show_icon'), $r('app.media.ic_grid'),
            this.showType === ShowType.SHOW_ICON, () => {
              this.closeFileMoreMenu()
              this.changeShowType(ShowType.SHOW_ICON)
            })
          this.fileMoreCommonItem($r('app.string.more_show_list'), $r('app.media.ic_list_bullet_circle'),
            this.showType === ShowType.SHOW_LIST, () => {
              this.closeFileMoreMenu()
              this.changeShowType(ShowType.SHOW_LIST)
            })
        }

        this.fileMoreGroupDivider()

        Column() {
          this.fileMoreSortItem($r('app.string.more_sort_by_name'), SortType.SORT_BY_NAME)
          this.fileMoreSortItem($r('app.string.more_sort_by_time'), SortType.SORT_BY_TIME)
          this.fileMoreSortItem($r('app.string.more_sort_by_size'), SortType.SORT_BY_SIZE)
        }

        this.fileMoreGroupDivider()

        Column() {
          this.fileMoreCommonItem($r('app.string.more_new_dir'), $r('app.media.ic_folder_badge_plus'), false, () => {
            this.closeFileMoreMenu()
            this.onMoreClick(MoreMenuType.NEW_DIR)
          })
          this.fileMoreCommonItem($r('app.string.more_new_file'), $r('app.media.ic_doc_badge_plus'), false, () => {
            this.closeFileMoreMenu()
            this.onMoreClick(MoreMenuType.NEW_FILE)
          })
        }

        this.fileMoreGroupDivider()

        Column() {
          this.fileMoreCommonItem($r('app.string.more_upload_file'), $r('app.media.ic_arrowshape_up'), false, () => {
            this.closeFileMoreMenu()
            this.onMoreClick(MoreMenuType.UPLOAD_FILE)
          })
        }
      }
      .width(CloudThemeToken.menuWidth)
      .padding(CloudThemeToken.zero)
      .borderRadius(CloudThemeToken.controlRadiusXl)
      .clip(true)
      .backgroundColor(CloudThemeToken.surface)
      .shadow({
        radius: CloudThemeToken.sheetShadowRadius,
        color: CloudThemeToken.sheetShadow,
        offsetY: CloudThemeToken.refreshShadowOffsetY
      })
      .margin({
        top: this.getHdsTitleBarBaseHeight() - CloudThemeToken.spacingSm,
        right: CloudThemeToken.filesHeaderPadding
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(CloudThemeToken.overlayZIndex)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.9, y: 0.9, centerX: '100%', centerY: '0%' }))
      .animation({ duration: CloudThemeToken.defaultAnimationDuration, curve: Curve.EaseOut }))
  }

  @Builder fileMoreGroupDivider() {
    Blank()
      .width('100%')
      .height(CloudThemeToken.spacingSm)
      .backgroundColor(CloudThemeToken.surfaceSubtle)
  }

  @Builder fileMoreCommonItem(content: ResourceStr, icon: Resource, isSelected: boolean, action: () => void) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Image(icon)
        .width(CloudThemeToken.objectMenuIconSize)
        .height(CloudThemeToken.objectMenuIconSize)
        .fillColor(CloudThemeToken.textPrimary)
        .draggable(false)

      Text(content)
        .fontSize(CloudThemeToken.objectMenuTextSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)
        .height(CloudThemeToken.menuItemLabelHeight)

      Image(isSelected ? $r('app.media.ic_selected') : '')
        .width(CloudThemeToken.objectMenuIconSize)
        .height(CloudThemeToken.objectMenuIconSize)
        .fillColor(CloudThemeToken.primary)
        .draggable(false)
    }
    .padding({
      left: CloudThemeToken.objectMenuHorizontalPadding,
      right: CloudThemeToken.objectMenuHorizontalPadding
    })
    .width('100%')
    .height(CloudThemeToken.menuItemHeight)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .onClick(action)
  }

  @Builder fileMoreSortItem(content: ResourceStr, type: SortType) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Image($r('app.media.ic_sort_arrow_up'))
        .width(CloudThemeToken.objectMenuIconSize)
        .height(CloudThemeToken.objectMenuIconSize)
        .fillColor(CloudThemeToken.textPrimary)
        .draggable(false)

      Text(content)
        .fontSize(CloudThemeToken.objectMenuTextSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)
        .height(CloudThemeToken.menuItemLabelHeight)

      Row({ space: CloudThemeToken.filesSortIconGroupGap }) {
        Image(this.sortType === type ? this.isSortTypeReverse(type) ? $r('app.media.ic_sort_arrow_down') :
        $r('app.media.ic_sort_arrow_up') : '')
          .width(CloudThemeToken.objectMenuIconSize)
          .height(CloudThemeToken.objectMenuIconSize)
          .fillColor(CloudThemeToken.primary)
          .draggable(false)
        Image(this.sortType === type ? $r('app.media.ic_selected') : '')
          .width(CloudThemeToken.objectMenuIconSize)
          .height(CloudThemeToken.objectMenuIconSize)
          .fillColor(CloudThemeToken.primary)
          .draggable(false)
      }
      .width(CloudThemeToken.filesSortIconGroupWidthPercent)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding({
      left: CloudThemeToken.objectMenuHorizontalPadding,
      right: CloudThemeToken.objectMenuHorizontalPadding
    })
    .width('100%')
    .height(CloudThemeToken.menuItemHeight)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .onClick(() => {
      this.closeFileMoreMenu()
      if (type === SortType.SORT_BY_NAME) {
        this.changeSortType(SortType.SORT_BY_NAME, MoreMenuType.SORT_BY_NAME)
      } else if (type === SortType.SORT_BY_TIME) {
        this.changeSortType(SortType.SORT_BY_TIME, MoreMenuType.SORT_BY_TIME)
      } else if (type === SortType.SORT_BY_SIZE) {
        this.changeSortType(SortType.SORT_BY_SIZE, MoreMenuType.SORT_BY_SIZE)
      }
    })
  }

  @Builder transportSheetTitle(title: ResourceStr) {
    Row() {
      Row({ space: CloudThemeToken.topBarActionGap }) {
        Stack()
          .width(CloudThemeToken.iconBoxSm)
          .height(CloudThemeToken.iconBoxSm)
        if (this.hasCompletedTransfers()) {
          Stack()
            .width(CloudThemeToken.iconBoxSm)
            .height(CloudThemeToken.iconBoxSm)
        }
      }

      Text(title)
        .fontSize(CloudThemeToken.filesTransportTitleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Row({ space: CloudThemeToken.topBarActionGap }) {
        if (this.hasCompletedTransfers()) {
          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.ic_trash_close'))
              .width(CloudThemeToken.sheetActionIconSize)
              .height(CloudThemeToken.sheetActionIconSize)
              .fillColor(CloudThemeToken.textSecondary)
              .draggable(false)
          }
          .width(CloudThemeToken.iconBoxSm)
          .height(CloudThemeToken.iconBoxSm)
          .borderRadius(CloudThemeToken.controlRadius)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .onClick(() => {
            this.clearCompletedTransfers()
          })
        }
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private hasCompletedTransfers(): boolean {
    const ds = this.downloadObjects.getDataList()
    for (let i = 0; i < ds.length; i++) {
      if (ds[i].state === FileModelState.COMPLETED) return true
    }
    const us = this.uploadObjects.getDataList()
    for (let i = 0; i < us.length; i++) {
      if (us[i].state === FileModelState.COMPLETED) return true
    }
    return false
  }

  private clearCompletedTransfers(): void {
    TransferDatabase.clearCompleted()
    const completedDownloads = this.downloadObjects.getDataList().filter((o: TransportObject) =>
      o.state === FileModelState.COMPLETED)
    completedDownloads.forEach((o: TransportObject) => this.downloadObjects.deleteDataByItem(o))
    const completedUploads = this.uploadObjects.getDataList().filter((o: TransportObject) =>
      o.state === FileModelState.COMPLETED)
    completedUploads.forEach((o: TransportObject) => this.uploadObjects.deleteDataByItem(o))
  }

  @Builder transportSheetBuilder() {
    Column() {
      SegmentButton({ options: this.selectCapsuleOptions, selectedIndexes: $selectedIndexes })
      Column() {
        if (this.selectedIndexes[CloudThemeToken.primarySegmentIndex] == CloudThemeToken.primarySegmentIndex) {
          Downloads({
            downloadObjects: this.downloadObjects,
            onAction: (object: TransportObject, action: TransferAction) => {
              this.handleDownloadAction(object, action)
            }
          })
        } else {
          Uploads({
            uploadObjects: this.uploadObjects,
            onAction: (object: TransportObject, action: TransferAction) => {
              this.handleUploadAction(object, action)
            }
          })
        }
      }
      .width('100%')
      .margin({ top: CloudThemeToken.filesTransportContentTopMargin })
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.background)
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .padding({
      left: CloudThemeToken.filesHeaderPadding,
      right: CloudThemeToken.filesHeaderPadding,
      top: CloudThemeToken.filesHeaderPadding,
      bottom: this.bottomRectHeight + CloudThemeToken.filesTransportPaddingBottom
    })
    .height('100%')
    .width('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder loadingState() {
    Column({ space: CloudThemeToken.spacingSection }) {
      LoadingProgress()
        .width(CloudThemeToken.iconBoxSm)
        .height(CloudThemeToken.iconBoxSm)
        .color(CloudThemeToken.primary)
      Text('正在加载文件')
        .fontSize(CloudThemeToken.textSizeBody)
        .fontColor(CloudThemeToken.textSecondary)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: this.tabBarHeight + CloudThemeToken.tabContentBottomPadding })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder hiddenRefreshHint() {
    Column()
      .width(CloudThemeToken.zero)
      .height(CloudThemeToken.zero)
      .opacity(CloudThemeToken.zero)
  }

  @Builder refreshingHintOverlay() {
    Column() {
      this.refreshingHint()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getRefreshHintTop() })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .opacity(this.getRefreshHintOpacity())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder refreshingHint() {
    Row({ space: CloudThemeToken.spacingXl }) {
      LoadingProgress()
        .width(CloudThemeToken.iconLg)
        .height(CloudThemeToken.iconLg)
        .color(CloudThemeToken.primary)
      Text('正在刷新')
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontColor(CloudThemeToken.textPrimary)
    }
    .height(CloudThemeToken.iconBoxSm)
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPage })
    .borderRadius(CloudThemeToken.controlRadiusRoundMd)
    .backgroundColor(CloudThemeToken.surface)
    .shadow({
      radius: CloudThemeToken.refreshShadowRadius,
      color: CloudThemeToken.refreshShadow,
      offsetY: CloudThemeToken.refreshShadowOffsetY
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder failedState() {
    Column() {
      EmptyState({
        icon: $r('app.media.ic_icloud_slash_fill'),
        title: '文件加载失败',
        description: '请检查网络或稍后重试。',
        actionText: '重新加载',
        onAction: () => {
          this.getFileList(true, this.currentPath)
        }
      })
    }
    .padding({ left: CloudThemeToken.spacingSheetHorizontal, right: CloudThemeToken.spacingSheetHorizontal, bottom: this.tabBarHeight + CloudThemeToken.tabContentBottomPadding })
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder inputSheetBuilder() {
    Column({ space: CloudThemeToken.spacingSheetTop }) {
      Row() {
        Text(this.inputTitle)
          .fontSize(CloudThemeToken.textSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      TextInput({ text: this.inputValue, placeholder: this.inputPlaceholder, controller: this.inputTextController })
        .width('100%')
        .height(CloudThemeToken.rowHeight2xl)
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontColor(CloudThemeToken.textPrimary)
        .placeholderColor(CloudThemeToken.textSecondary)
        .backgroundColor(CloudThemeToken.surface)
        .borderRadius(CloudThemeToken.controlRadius)
        .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
        .padding({ left: CloudThemeToken.spacingSection, right: CloudThemeToken.spacingSection })
        .id(INPUT_SHEET_TEXT_ID)
        .onChange((value: string) => {
          this.inputValue = value
        })

      Row({ space: CloudThemeToken.spacingSection }) {
        Text($r('app.string.dialog_cancel'))
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .textAlign(TextAlign.Center)
          .height(CloudThemeToken.rowHeightXl)
          .layoutWeight(1)
          .borderRadius(CloudThemeToken.controlRadiusLg)
          .backgroundColor(CloudThemeToken.surface)
          .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
          .align(Alignment.Center)
          .onClick(() => {
            this.closeInputSheet()
          })

        Text($r('app.string.finished'))
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.onPrimary)
          .textAlign(TextAlign.Center)
          .height(CloudThemeToken.rowHeightXl)
          .layoutWeight(1)
          .borderRadius(CloudThemeToken.controlRadiusLg)
          .backgroundColor(CloudThemeToken.primary)
          .align(Alignment.Center)
          .onClick(() => {
            this.confirmInputSheet()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      // 键盘弹出时内容随键盘高度长高（FIT_CONTENT 面板随之抬升），收起时回落到常规底部留白
      bottom: this.keyboardHeightVp > 0
        ? this.keyboardHeightVp + CloudThemeToken.spacingSheetBottom
        : this.bottomRectHeight + CloudThemeToken.hdsTabBarBottomMargin + CloudThemeToken.spacingSheetBottom
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
    .zIndex(1)
  }

  @Builder shareSheetBuilder() {
    Column({ space: CloudThemeToken.spacingSheetTop }) {
      this.shareTargetSummary()

      if (this.shareLinkText.length > 0) {
        this.shareLinkCard()
        this.shareDetailCard()
        Row({ space: CloudThemeToken.spacingSection }) {
          this.shareActionButton($r('app.media.ic_copy'), '复制链接', () => {
            this.copyShareLink()
          })
          this.shareActionButton($r('app.media.ic_delete_fill'), '取消分享', () => {
            this.deleteShareForTarget()
          }, true, this.getCurrentShareId().length > 0 && !this.shareBusy)
        }
        .width('100%')
      } else {
        this.shareCreateOptions()
        Button({ type: ButtonType.Normal }) {
          Row({ space: CloudThemeToken.spacingXl }) {
            if (this.shareBusy) {
              LoadingProgress()
                .width(CloudThemeToken.iconLg)
                .height(CloudThemeToken.iconLg)
                .color(CloudThemeToken.onPrimary)
            } else {
              Image($r('app.media.ic_share'))
                .width(CloudThemeToken.iconLg)
                .height(CloudThemeToken.iconLg)
                .fillColor(CloudThemeToken.onPrimary)
                .draggable(false)
            }
            Text(this.shareBusy ? '正在创建' : '创建分享链接')
              .fontSize(CloudThemeToken.textSizeBodyPlus)
              .fontWeight(FontWeight.Medium)
              .fontColor(CloudThemeToken.onPrimary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(CloudThemeToken.rowHeightXl)
        .borderRadius(CloudThemeToken.controlRadiusLg)
        .backgroundColor(CloudThemeToken.primary)
        .enabled(!this.shareBusy)
        .opacity(this.shareBusy ? CloudThemeToken.disabledOpacity : CloudThemeToken.fullOpacity)
        .onClick(() => {
          this.createShareForTarget()
        })
      }
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: this.bottomRectHeight + CloudThemeToken.hdsTabBarBottomMargin + CloudThemeToken.spacingSheetBottom
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
    .zIndex(1)
  }

  @Builder shareTargetSummary() {
    Row({ space: CloudThemeToken.detailSheetSummaryGap }) {
      Stack() {
        Image(this.shareTarget?.type === Constant.OBJECT_DIR_TYPE ? $r('app.media.folder_fill') :
        CommonUtil.getFileIconInfo(this.shareTarget?.name ?? '').icon)
          .width(CloudThemeToken.detailSheetIconSize)
          .height(CloudThemeToken.detailSheetIconSize)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      .width(CloudThemeToken.detailSheetIconBoxSize)
      .height(CloudThemeToken.detailSheetIconBoxSize)
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.primarySoft)

      Column({ space: CloudThemeToken.detailSheetTextGap }) {
        Text(this.shareTarget?.name ?? '')
          .fontSize(CloudThemeToken.textSizeLargePlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(2)
          .wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.shareTarget ? this.getObjectSharePath(this.shareTarget) : '')
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(CloudThemeToken.detailSheetSummaryPadding)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder shareLinkCard() {
    Column({ space: CloudThemeToken.spacingXl }) {
      Text('当前分享链接')
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontColor(CloudThemeToken.textSecondary)
      Text(this.shareLinkText)
        .fontSize(CloudThemeToken.textSizeBody)
        .fontColor(CloudThemeToken.textPrimary)
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.getCurrentSharePasswordText().length > 0) {
        Text(`提取码：${this.getCurrentSharePasswordText()}`)
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textSecondary)
      }
    }
    .width('100%')
    .padding(CloudThemeToken.spacingSection)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder shareDetailCard() {
    Column({ space: CloudThemeToken.spacingXl }) {
      Text('分享详情')
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontColor(CloudThemeToken.textSecondary)

      this.shareDetailRow('状态', this.getCurrentShareStatusText())
      this.shareDetailRow('有效期', this.getCurrentShareExpireText())
      this.shareDetailRow('创建时间', this.getCurrentShareCreatedText())
      this.shareDetailRow('访问次数', this.getCurrentShareVisitedText())
      this.shareDetailRow('下载次数', this.getCurrentShareDownloadedText())
    }
    .width('100%')
    .padding(CloudThemeToken.spacingSection)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder shareDetailRow(label: string, value: string) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Text(label)
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontColor(CloudThemeToken.textSecondary)
        .width(CloudThemeToken.rowHeight5xl)

      Text(value)
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontColor(CloudThemeToken.textPrimary)
        .maxLines(2)
        .wordBreak(WordBreak.BREAK_ALL)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder shareCreateOptions() {
    Column({ space: CloudThemeToken.spacingSection }) {
      Column({ space: CloudThemeToken.spacingXs }) {
        Text('有效期')
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textSecondary)
        Row({ space: CloudThemeToken.spacingXl }) {
          this.shareExpireChip('永久', ShareExpireDays.NEVER)
          this.shareExpireChip('1天', ShareExpireDays.ONE_DAY)
          this.shareExpireChip('7天', ShareExpireDays.SEVEN_DAYS)
          this.shareExpireChip('30天', ShareExpireDays.THIRTY_DAYS)
        }
        .width('100%')
      }
      .width('100%')

      TextInput({ text: this.sharePassword, placeholder: '提取码（可选）' })
        .width('100%')
        .height(CloudThemeToken.rowHeight2xl)
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontColor(CloudThemeToken.textPrimary)
        .placeholderColor(CloudThemeToken.textSecondary)
        .backgroundColor(CloudThemeToken.surface)
        .borderRadius(CloudThemeToken.controlRadius)
        .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
        .padding({ left: CloudThemeToken.spacingSection, right: CloudThemeToken.spacingSection })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.sharePassword = value
        })
    }
    .width('100%')
  }

  @Builder shareExpireChip(title: string, days: number) {
    Button({ type: ButtonType.Normal }) {
      Text(title)
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.shareExpireDays === days ? CloudThemeToken.onPrimary : CloudThemeToken.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(CloudThemeToken.rowHeightMd)
    .layoutWeight(1)
    .borderRadius(CloudThemeToken.controlRadiusRoundMd)
    .backgroundColor(this.shareExpireDays === days ? CloudThemeToken.primary : CloudThemeToken.surface)
    .border({
      width: CloudThemeToken.lineWidth,
      color: this.shareExpireDays === days ? CloudThemeToken.primary : CloudThemeToken.line
    })
    .onClick(() => {
      this.shareExpireDays = days
    })
  }

  @Builder shareActionButton(icon: Resource, title: string, action: () => void, danger: boolean = false,
    isEnabled: boolean = true) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: CloudThemeToken.spacingXl }) {
        Image(icon)
          .width(CloudThemeToken.iconLg)
          .height(CloudThemeToken.iconLg)
          .fillColor(danger ? CloudThemeToken.danger : CloudThemeToken.primary)
          .draggable(false)
        Text(title)
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(danger ? CloudThemeToken.danger : CloudThemeToken.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .height(CloudThemeToken.rowHeightXl)
    .layoutWeight(1)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .backgroundColor(danger ? CloudThemeToken.dangerSoft : CloudThemeToken.primarySoft)
    .enabled(isEnabled)
    .opacity(isEnabled ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
    .onClick(action)
  }

  @Builder emptyDirectoryState() {
    Column() {
      EmptyState({
        icon: $r('app.media.ic_empty_folder'),
        title: '这里还没有文件',
        description: '上传文件或新建文件夹后，会显示在当前目录。',
        actionText: '上传文件',
        onAction: () => {
          this.openSelectFileSheet()
        }
      })
    }
    .padding({ left: CloudThemeToken.spacingSheetHorizontal, right: CloudThemeToken.spacingSheetHorizontal, bottom: this.tabBarHeight + CloudThemeToken.tabContentBottomPadding })
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder searchEmptyState() {
    Column() {
      EmptyState({
        icon: $r('app.media.ic_line_viewfinder'),
        title: '未找到匹配文件',
        description: '换个关键词试试。',
        actionText: '清空搜索',
        onAction: () => {
          this.searchKeyword = ''
          this.applyVisibleObjects()
        }
      })
    }
    .padding({ left: CloudThemeToken.spacingSheetHorizontal, right: CloudThemeToken.spacingSheetHorizontal, bottom: this.tabBarHeight + CloudThemeToken.tabContentBottomPadding })
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder objectGrid() {
    Grid(this.scrollerForList) {
      ForEach(this.getGridSpacerItems(), (item: number) => {
        GridItem() {
          Row()
            .width('100%')
            .height(this.getGridTopSpacerHeight())
        }
        .selectable(false)
      }, (item: number) => `top-spacer-${item}`)

      LazyForEach(this.dirDataSource, (item: ObjectInfo, index: number) => {
        GridItem() {
          ObjectItem({ index, item, showType: this.showType,
            multiSelectMode: this.isMultiSelectMode,
            selected: this.isObjectSelected(item),
            shared: this.isSharedObject(item),
            onMenuClick : (async (item, type) => {
              await this.onMenuClick(index, item, type)
            })
          })
        }
        .id(item.id)
        .selectable(true)
        .selected(this.isObjectSelected(item))
        .onSelect((isSelected: boolean) => {
          this.onBoxSelect(item, isSelected)
        })
        .onClick(async () => {
          this.onItemClick(item)
        })
      }, (item: ObjectInfo, index: number) => item.id)

      ForEach(this.getFolderPaddingItems(), (item: number) => {
        GridItem()
      }, (item: number) => `folder-padding-${item}`)

      LazyForEach(this.fileDataSource, (item: ObjectInfo, index: number) => {
        GridItem() {
          ObjectItem({ index, item, showType: this.showType,
            multiSelectMode: this.isMultiSelectMode,
            selected: this.isObjectSelected(item),
            shared: this.isSharedObject(item),
            onMenuClick : (async (item, type) => {
              await this.onMenuClick(index, item, type)
            })
          })
        }
        .id(item.id)
        .selectable(true)
        .selected(this.isObjectSelected(item))
        .onSelect((isSelected: boolean) => {
          this.onBoxSelect(item, isSelected)
        })
        .onClick(async () => {
          this.onItemClick(item)
        })
      }, (item: ObjectInfo, index: number) => item.id)

      ForEach(this.getGridSpacerItems(), (item: number) => {
        GridItem() {
          Row()
            .width('100%')
            .height((this.isMultiSelectMode ? this.multiSelectBarHeight : this.tabBarHeight) + CloudThemeToken.tabContentBottomGap)
        }
        .selectable(false)
      }, (item: number) => `bottom-spacer-${item}`)
    }
    .cachedCount(CloudThemeToken.fileGridCachedCount)
    .multiSelectable(true)
    .maxCount(this.getGridColumns())
    .padding({
      left: CloudThemeToken.spacingCard,
      right: CloudThemeToken.spacingCard
    })
    .width('100%')
    .height('100%') //!!!使用lazyforeach必须设置高度才能有效
    .rowsGap(CloudThemeToken.gridGap)
    .columnsGap(CloudThemeToken.gridGap)
    .columnsTemplate(this.getGridColumnsTemplate())
    .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
    .animation({duration: CloudThemeToken.defaultAnimationDuration})
    .scrollBarWidth(CloudThemeToken.strongLineWidth)
    .onDidScroll((_scrollOffset: number, scrollState: ScrollState) => {
      if (scrollState !== ScrollState.Idle) {
        this.prioritizeNewestThumbRequests = true
      }
      this.updateHeaderGlassState()
    })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width)
      if (!Number.isNaN(width) && Math.abs(width - this.gridWidth) >= CloudThemeToken.layoutChangeThreshold) {
        this.gridWidth = width
        this.isGridPadding = this.getFolderPaddingCount() > 0
      }
    })
    .bindSheet($$this.showPathSelect, this.selectPathSheet(), {
      showClose: false,
      backgroundColor: CloudThemeToken.background,
      preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
      width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
      onWillAppear: () => {
        this.pathSelectSheetCtrl.onWillAppear()
      },
      onAppear: () => {
        this.markSheetVisible()
        this.pathSelectSheetCtrl.onAppear()
      },
      onWillDisappear: () => {
        this.pathSelectSheetCtrl.onWillDisappear()
      },
      onDisappear: () => {
        this.markSheetHidden()
        this.pathSelectSheetCtrl.onDisappear((value: boolean) => {
          this.showPathSelect = value
        }, () => {
          this.showPathSelect = false
        })
        this.startPendingCopyMove()
      }
    })
  }

  /**
   * 路径选好之后，等这层半模态真正消失了才开工。
   *
   * 移动/复制中途会弹同名冲突确认层，而那层是页面内的 Stack 子节点。若它在半模态
   * 还盖着页面时被插进去，画面上看得见，却进不了手势响应树——点不动，也就永远关不掉。
   * 所以这里等 onDisappear，确保它是在一个干净的页面上创建的。
   */
  private startPendingCopyMove(): void {
    const dst = this.pendingCopyMoveDst
    if (dst.length === 0) {
      return
    }
    this.pendingCopyMoveDst = ''
    this.copyMoveObjects(dst)
  }

  @Builder selectPathSheet() {
    PathSelectSheet({
      title: this.objectSelect.selectPathTitle,
      filterDirId: this.objectSelect.selectPathId,
      onClose: (isFinished: boolean, path?: string) => {
        this.closePathSelectSheet()
        if (isFinished && path && path != '') {
          console.debug(TAG, 'select path: ' + path)
          // 只记下目标，等这层半模态真的消失了再开工——见 pendingCopyMoveDst
          this.pendingCopyMoveDst = path
        }
    }
    })
  }

  @Builder detailSheet() {
    DetailSheet({detailData: this.detailData})
  }

  @Builder sheetCloseButton(onClose: () => void) {
    Button({ type: ButtonType.Normal }) {
      Image($r('app.media.ic_xmark_bold'))
        .width(CloudThemeToken.sheetActionIconSize)
        .height(CloudThemeToken.sheetActionIconSize)
        .fillColor(CloudThemeToken.textSecondary)
        .draggable(false)
    }
    .width(CloudThemeToken.iconBoxSm)
    .height(CloudThemeToken.iconBoxSm)
    .borderRadius(CloudThemeToken.actionRadiusForWidth(this.sheetLayoutWidth, CloudThemeToken.controlRadius))
    .backgroundColor(CloudThemeToken.surfaceSubtle)
    .onClick(onClose)
  }

  @Builder detailBindSheet() {
    Column() {
      this.detailSheet()
    }
    .width('100%')
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder selectFileOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.overlayScrim)
        .zIndex(0)
        .onClick(() => {
          this.closeFileSheet()
        })

      this.selectFileSheetBuilder()
    }
    .width('100%')
    .height('100%')
    .zIndex(CloudThemeToken.overlayZIndex)
  }

  @Builder inputSheetOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.overlayScrim)
        .zIndex(0)
        .onClick(() => {
          this.closeInputSheet()
        })

      this.inputSheetBuilder()
    }
    .width('100%')
    .height('100%')
    .zIndex(CloudThemeToken.overlayZIndex)
  }

  @Builder shareSheetOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.overlayScrim)
        .zIndex(0)
        .onClick(() => {
          this.closeShareSheet()
        })

      this.shareSheetBuilder()
    }
    .width('100%')
    .height('100%')
    .zIndex(CloudThemeToken.overlayZIndex)
  }

  @Builder selectFileSheetBuilder() {
    SelectFileSheet({
      extraBottomPadding: CloudThemeToken.hdsTabBarBottomMargin,
      onClose: () => {
        this.closeFileSheet()
      },
      onSelectFinished: (uris: string[]) => {
        this.closeFileSheet();
        this.startUpload(uris);
      }
    })
  }

  async onItemClick(item: ObjectInfo) {
    if (this.isMultiSelectMode) {
      this.toggleObjectSelection(item)
      return
    }

    if (item.type == Constant.OBJECT_DIR_TYPE) {
      await this.getFileList(true, CloudApi.getTotalPath(item))
    }
    else {
      let fileType = CommonUtil.getFileType(item.name)
      let fileExtension = CommonUtil.getFileExtention(item.name)
      if (fileType == FileType.IMAGE) {
        const param = this.buildImagePreviewParam(item, fileExtension)
        const pushStarted = Date.now()
        CloudRouter.push(Constant.IAMGE_PREVIEW_PAGE, param)
        AppLogger.info(TAG, `[timing] preview push returned in ${Date.now() - pushStarted}ms`)
      } else if (fileType == FileType.VIDEO) {
        CloudRouter.push(Constant.VIDEO_PREVIEW_PAGE,
          new VideoPreview(item.name, item.id, fileExtension, this.getObjectSharePath(item)))
      } else if (CommonUtil.isTextViewable(fileType)) {
        const dirPath = this.currentPath
        TextPreviewEntry.open(item, () => {
          this.getFileList(true, dirPath)
        })
      } else {
        //filePreview.openPreview(getContext(), {title: item.name, uri: '', mimeType: ''})
        showToast('该类型不支持预览')
      }
    }
  }

  private buildImagePreviewParam(item: ObjectInfo, fileExtension: string): ImagePreview {
    const started = Date.now()
    const images = this.fileDataSource.dataArray
      .filter((file: ObjectInfo) => CommonUtil.getFileType(file.name) === FileType.IMAGE)
      .map((file: ObjectInfo) => new PreviewFile(file.name, file.id, CommonUtil.getFileExtention(file.name)))
    const currentIndex = images.findIndex((file: PreviewFile) => file.fileId === item.id)
    AppLogger.info(TAG, `[timing] preview param built in ${Date.now() - started}ms, ` +
      `scanned=${this.fileDataSource.dataArray.length}, images=${images.length}`)
    return new ImagePreview(item.name, item.id, fileExtension, images, currentIndex >= 0 ? currentIndex : 0)
  }

  async onMenuClick(index: number, item: ObjectInfo, type: FileMenuType) {
    console.debug(TAG, 'onMenuClick type: ' + type)
    switch (type){
      case FileMenuType.PREVIEW:
      case FileMenuType.DIR_ENTER:
        this.onItemClick(item)
        break
      case FileMenuType.MULTI_SELECT:
        this.enterMultiSelectMode()
        this.selectedObjects = [item]
        break
      case FileMenuType.DETAIL:
        this.itemDetail(item)
        break
      case FileMenuType.RENAME:
        this.itemRename(index, item)
        break
      case FileMenuType.COPY:
      case FileMenuType.MOVE:
        this.objectSelect.index = index
        if (type == FileMenuType.COPY) {
          this.objectSelect.selectPathTitle = $r('app.string.copy_to')
        } else if (type == FileMenuType.MOVE) {
          this.objectSelect.selectPathTitle = $r('app.string.move_to')
        }
        this.objectSelect.type = type
        this.objectSelect.copyMoveObjects.splice(0, this.objectSelect.copyMoveObjects.length)
        this.objectSelect.copyMoveObjects.push(item)
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          this.objectSelect.selectPathId = item.id
        }
        else {
          this.objectSelect.selectPathId = ''
        }
        this.openPathSelectSheet()
        break
      case FileMenuType.CREATE_SHARE:
        this.openShareSheet(item)
        break
      case FileMenuType.DOWNLOAD:
        this.itemDownload(index, item)
        break
      case FileMenuType.DELETE:
        this.itemDelete(index, item)
        break
    }
  }

  onMoreClick(type: MoreMenuType, isReserve?: boolean) {
    console.debug(TAG, 'onMoreClick type: ' + type)
    switch (type){
      case MoreMenuType.MULTI_SELECT:
        this.enterMultiSelectMode()
        break;
      case MoreMenuType.SHOW_ICON:
        break
      case MoreMenuType.SHOW_LIST:
        break
      case MoreMenuType.SORT_BY_NAME:
      case MoreMenuType.SORT_BY_TYPE:
      case MoreMenuType.SORT_BY_TIME:
      case MoreMenuType.SORT_BY_SIZE:
        this.objectsInfo.sortObjects(this.sortType, this.isSortTypeReverse(this.sortType))
        this.applyVisibleObjects()
        break
      case MoreMenuType.NEW_DIR:
        this.itemNew(this.currentPath, true)
        break
      case MoreMenuType.NEW_FILE:
        this.itemNew(this.currentPath, false)
        break
      case MoreMenuType.UPLOAD_FILE:
        this.openSelectFileSheet()
        break
    }
  }

  private startSelectedCopyMove(type: FileMenuType): void {
    if (this.selectedObjects.length === 0) {
      return
    }

    this.objectSelect.index = -1
    this.objectSelect.type = type
    this.objectSelect.selectPathTitle = type === FileMenuType.COPY ? $r('app.string.copy_to') : $r('app.string.move_to')
    this.objectSelect.copyMoveObjects = this.selectedObjects.slice()
    const onlySelected = this.selectedObjects.length === 1 ? this.selectedObjects[0] : undefined
    this.objectSelect.selectPathId = onlySelected?.type === Constant.OBJECT_DIR_TYPE ? onlySelected.id : ''
    // 任务对象已快照到 objectSelect，先退出多选，路径选择和后续进度半模态独立展示。
    this.exitMultiSelectMode()
    this.openPathSelectSheet()
  }

  // 沙箱/公共目录路径转为用户可读的保存位置，
  // 如 /storage/Users/currentUser/Download/com.dreamflytech.cloudrs → 下载/Cloudrs
  private formatDownloadDirForDisplay(path: string, stripFileName: boolean = false): string {
    let dir = path
    if (stripFileName) {
      const slash = dir.lastIndexOf('/')
      if (slash > 0) {
        dir = dir.substring(0, slash)
      }
    }
    const userPrefix = '/storage/Users/currentUser/'
    if (dir.startsWith(userPrefix)) {
      dir = dir.substring(userPrefix.length)
    }
    if (dir === 'Download' || dir.startsWith('Download/')) {
      dir = '下载' + dir.substring('Download'.length)
    }
    const context = this.getAbilityContext()
    const bundleName = context?.applicationInfo?.name ?? ''
    if (bundleName.length > 0) {
      dir = dir.replace(bundleName, Constant.APP_DISPLAY_NAME)
    }
    return dir
  }

  private downloadSelectedObjects(): void {
    if (this.selectedObjects.length === 0) {
      return
    }

    const selected = this.selectedObjects.slice()
    this.exitMultiSelectMode()
    const selectedFiles = selected.filter((item: ObjectInfo) => item.type !== Constant.OBJECT_DIR_TYPE)
    if (selectedFiles.length === 0) {
      showToast('已选择的项目中没有可下载文件')
      return
    }

    try {
      const context = this.getAbilityContext()
      if (!context) {
        showToast($r('app.string.get_context_failed'))
        return
      }

      if (CommonUtil.isAllImages(selectedFiles.map((f: ObjectInfo) => f.name))) {
        this.saveImagesFlow(context, selectedFiles)
        return
      }

      const documentSaveOptions = new picker.DocumentSaveOptions()
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD
      const documentPicker = new picker.DocumentViewPicker(context)
      documentPicker.save(documentSaveOptions).then((documentSaveResult: Array<string>) => {
        if (documentSaveResult.length === 0) {
          return
        }
        const targetDirUri = documentSaveResult[Constant.FIRST_ARRAY_INDEX]
        selectedFiles.forEach((item: ObjectInfo) => {
          const filePath = FileSystemUtil.getPathFromUri(targetDirUri + '/' + item.name)
          this.enqueueDownloadTask(context, item, filePath)
        })
        showToast(`已添加${selectedFiles.length}个下载任务，保存至 ${this.formatDownloadDirForDisplay(
          FileSystemUtil.getPathFromUri(targetDirUri))}`, Constant.TOAST_LONG_DURATION_MS)
        // 文件选择器退场后再拉起传输半模态，避免两个系统模态切换时丢失打开请求。
        setTimeout(() => this.openTransportSheet(), CloudThemeToken.defaultAnimationDuration)
      }).catch((err: BusinessError) => {
        AppLogger.error(TAG, `Invoke documentViewPicker.save failed, code is ${err.code}, message is ${err.message}`)
      })
    } catch (error) {
      const err: BusinessError = error as BusinessError
      AppLogger.error(TAG, `Error code: ${err.code}, message: ${err.message}`)
    }
  }

  private deleteSelectedObjects(): void {
    if (this.selectedObjects.length === 0) {
      return
    }

    const selected = this.selectedObjects.slice()
    this.exitMultiSelectMode()
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.delete_confirm'),
      message: selected.length === 1
        ? selected[0].name
        : `将删除 ${selected.length} 个项目`,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        this.deleteSelectedObjectsWithResults(selected)
      }
    })
  }

  private removeDeletedObjectsFromPage(items: ObjectInfo[]): void {
    const deletedIds = new Set<string>(items.map((item: ObjectInfo) => item.id))
    this.dirDataSource.replaceAll(
      this.dirDataSource.dataArray.filter((item: ObjectInfo) => !deletedIds.has(item.id)))
    this.fileDataSource.replaceAll(
      this.fileDataSource.dataArray.filter((item: ObjectInfo) => !deletedIds.has(item.id)))
    this.thumbQueue = this.thumbQueue.filter((item: ObjectInfo) => !deletedIds.has(item.id))
    this.selectedObjects = this.selectedObjects.filter((item: ObjectInfo) => !deletedIds.has(item.id))
    this.objectSelect.copyMoveObjects =
      this.objectSelect.copyMoveObjects.filter((item: ObjectInfo) => !deletedIds.has(item.id))
    this.isGridPadding = this.getFolderPaddingCount() > 0
  }

  private async deleteSelectedObjectsWithResults(items: ObjectInfo[],
    previousSuccessCount: number = 0): Promise<void> {
    AppLogger.info(TAG, `counted batch delete start, count=${items.length}`)
    const execution = await this.runBatchChunks(items, '正在删除',
      (chunk: ObjectInfo[]) => this.deleteChunk(chunk), previousSuccessCount)
    const results = execution.results
    const deleted = results.filter((result: BatchItemResult) => result.success)
      .map((result: BatchItemResult) => result.item)
    const failed = results.filter((result: BatchItemResult) => !result.success)
    if (failed.length > 0) {
      const reasons = new Map<string, number>()
      failed.forEach((result: BatchItemResult) => {
        const key = result.message.length > 0 ? result.message : '(empty)'
        reasons.set(key, (reasons.get(key) ?? 0) + 1)
      })
      reasons.forEach((count: number, reason: string) => {
        AppLogger.warn(TAG, `delete failure x${count}: ${reason}`)
      })
    }
    const successCount = previousSuccessCount + deleted.length
    if (deleted.length > 0) {
      this.removeDeletedObjectsFromPage(deleted)
      this.recordBackupRemoved(
        deleted.filter((item: ObjectInfo) => item.type !== Constant.OBJECT_DIR_TYPE)
          .map((item: ObjectInfo) => item.name))
      this.recordBackupDirRemoved(
        deleted.filter((item: ObjectInfo) => item.type === Constant.OBJECT_DIR_TYPE)
          .map((item: ObjectInfo) => this.joinRemotePath(this.currentPath, item.name)))
      this.getFileList(true, this.currentPath)
    }
    if (execution.canceled) {
      const unprocessedCount = Math.max(0, items.length - results.length)
      showToast(`已取消删除：成功 ${successCount} 项，失败 ${failed.length} 项，未处理 ${unprocessedCount} 项`)
      return
    }
    if (failed.length === 0) {
      this.exitMultiSelectMode()
      showToast(`删除成功 ${successCount} 项`)
      return
    }
    showToast(`删除成功 ${successCount} 项，失败 ${failed.length} 项`)
    this.offerRelieveFailedDeleteSessions(failed, successCount)
  }

  private offerRelieveFailedDeleteSessions(failed: BatchItemResult[], successCount: number): void {
    const nonNetworkFailures = failed.filter((result: BatchItemResult) =>
      !ApiErrorUtil.isNetworkMessage(result.message))
    if (nonNetworkFailures.length === 0) {
      return
    }
    const failedItems = nonNetworkFailures.map((result: BatchItemResult) => result.item)
    const filePaths: string[] = []
    const dirPaths: string[] = []
    failedItems.forEach((item: ObjectInfo) => {
      const remotePath = this.joinRemotePath(this.currentPath, item.name)
      if (item.type === Constant.OBJECT_DIR_TYPE) {
        dirPaths.push(remotePath)
      } else {
        filePaths.push(remotePath)
      }
    })
    const summary: UploadSessionSummary = UploadSessionRelief.summarize(filePaths, dirPaths)
    const serverSessions: ServerUploadSession[] = []
    failedItems.forEach((item: ObjectInfo) => {
      const sessionId = item.metadata?.['sys:upload_session_id'] ?? ''
      if (sessionId.length > 0) {
        serverSessions.push({
          remotePath: this.joinRemotePath(this.currentPath, item.name),
          sessionId: sessionId
        })
      }
    })
    const tokenSet = new Set<string>()
    let hasServerLockConflict = false
    nonNetworkFailures.forEach((result: BatchItemResult) => {
      if (ApiErrorUtil.isLockConflict(result.message) || (result.lockConflicts?.length ?? 0) > 0) {
        hasServerLockConflict = true
      }
      const conflicts = result.lockConflicts ?? []
      conflicts.forEach((conflict: FileLockConflict) => {
        if (conflict.token && conflict.token.length > 0) {
          tokenSet.add(conflict.token)
        }
      })
    })
    const lockTokens = Array.from(tokenSet)
    if (summary.count === 0 && lockTokens.length === 0 && serverSessions.length === 0) {
      if (hasServerLockConflict) {
        showCloudConfirmDialog(this.getUIContext(), {
          title: $r('app.string.upload_occupied_title'),
          message: '服务器确认文件正被上传、备份或在线编辑任务占用，但当前账号没有可解除的锁。' +
            '请先结束占用任务，或在创建该任务的设备上取消后重试。',
          confirmText: '知道了',
          onConfirm: () => {}
        })
      }
      return
    }
    const details: string[] = []
    if (lockTokens.length > 0) {
      details.push(`${lockTokens.length} 个云端文件锁`)
    }
    if (summary.count > 0) {
      details.push(`${summary.count} 个本机未完成上传会话`)
    }
    if (serverSessions.length > 0) {
      details.push(`${serverSessions.length} 个服务器上传会话`)
    }
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.upload_occupied_title'),
      message: `删除失败的 ${failedItems.length} 项中检测到${details.join('和')}。` +
        '解除占用会终止对应的上传、备份或在线编辑任务，是否解除后重试删除？',
      confirmText: $r('app.string.upload_occupied_relieve'),
      onConfirm: () => {
        this.relieveLocksAndRetry(summary, filePaths, dirPaths, lockTokens, serverSessions,
          () => this.deleteSelectedObjectsWithResults(failedItems, successCount))
      }
    })
  }

  private async relieveLocksAndRetry(summary: UploadSessionSummary, filePaths: string[],
    dirPaths: string[], lockTokens: string[], serverSessions: ServerUploadSession[],
    retry: () => void): Promise<void> {
    await UploadSessionRelief.relieve(summary, filePaths, dirPaths)
    let releasedServerSessions = 0
    if (serverSessions.length > 0) {
      releasedServerSessions = await this.releaseServerUploadSessions(serverSessions)
    }
    if (lockTokens.length > 0) {
      const unlocked = await this.unlockCloudFileLocks(lockTokens, releasedServerSessions > 0)
      if (!unlocked && releasedServerSessions === 0) {
        return
      }
    }
    // 删除服务器上传会话会同时释放其文件锁，此时删除响应携带的旧 token 再解锁会返回 40001。
    // 只要至少一个上传会话已成功取消，就以重试删除的结果作为最终判定。
    retry()
  }

  private async releaseServerUploadSessions(sessions: ServerUploadSession[]): Promise<number> {
    let releasedCount = 0
    for (const session of sessions) {
      await new Promise<void>((resolve: () => void) => {
        CloudApi.deleteUploadSession(session.remotePath, session.sessionId, {
          onSuccess: () => {
            releasedCount++
            AppLogger.info(TAG, `released listed upload session id=${session.sessionId}`)
            resolve()
          },
          onFailure: (msg: string) => {
            AppLogger.warn(TAG, `delete listed upload session failed id=${session.sessionId}, msg=${msg}`)
            resolve()
          }
        })
      })
    }
    return releasedCount
  }

  private unlockCloudFileLocks(tokens: string[], allowStaleFailure: boolean = false): Promise<boolean> {
    return new Promise<boolean>((resolve: (unlocked: boolean) => void) => {
      CloudApi.unlockFiles(tokens, {
        onSuccess: () => resolve(true),
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `force unlock failed${allowStaleFailure ? ' after upload session release' : ''}: ${msg}`)
          if (!allowStaleFailure) {
            showApiFailureToast(msg, '解除文件占用失败')
          }
          resolve(false)
        }
      })
    })
  }

  private isObjectMissingMessage(msg: string): boolean {
    const lower = (msg ?? '').toLowerCase()
    return lower.includes('not found') || lower.includes('notfound') ||
      lower.includes('not exist') || lower.includes('no such') ||
      lower.includes('404') || lower.includes('不存在') || lower.includes('找不到')
  }

  itemDetail(item: ObjectInfo) {
    CloudApi.getObjectDetail(item.id, item.type == Constant.OBJECT_DIR_TYPE, {
      onSuccess: (data) => {
        this.detailData = new DetailData(item.name, item.type == Constant.OBJECT_DIR_TYPE, data)
        this.detailKnockObject = item
        this.detailSheetCtrl.requestOpen(() => this.showObjectDetail, (value: boolean) => {
          this.showObjectDetail = value
        })
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, '获取详细信息失败 msg: ' + msg)
        showApiFailureToast(msg, $r('app.string.get_detail_failed'))
      }
    })
  }

  private detailKnockShareCallback = (sharableTarget: harmonyShare.SharableTarget): void => {
    this.handleDetailKnockShare(sharableTarget)
  }

  // 详情面板打开期间的碰一碰分享,分层策略:已下载文件分享本体,未下载分享下载直链(对端浏览器在线看/下载)。
  private async handleDetailKnockShare(sharableTarget: harmonyShare.SharableTarget): Promise<void> {
    try {
      const item = this.detailKnockObject
      if (!item || item.type === Constant.OBJECT_DIR_TYPE) {
        await sharableTarget.clarifyNonShare({ message: '文件夹不支持碰一碰分享' })
        return
      }
      const localUri = KnockShareUtil.findLocalDownloadUri(item.id)
      if (localUri.length > 0) {
        await sharableTarget.share(KnockShareUtil.buildFileShareData(item.name, localUri))
        return
      }
      if (KnockShareUtil.useShareLink()) {
        const link = await KnockShareUtil.createOrReuseShareLink(item.id, this.getObjectSharePath(item))
        if (link) {
          await sharableTarget.share(KnockShareUtil.buildLinkShareData(item.name, link.url, link.password))
          if (link.password.length > 0) {
            showToast(`分享链接提取码：${link.password}`)
          }
        } else {
          await sharableTarget.reject(harmonyShare.SharableErrorCode.NO_INTERNET_ERROR)
        }
        return
      }
      const url = await this.fetchKnockDownloadUrl(item.id)
      if (url.length > 0) {
        await sharableTarget.share(KnockShareUtil.buildLinkShareData(item.name, url))
      } else {
        await sharableTarget.reject(harmonyShare.SharableErrorCode.NO_INTERNET_ERROR)
      }
    } catch (err) {
      AppLogger.error(TAG, `detail knock share failed: ${(err as Error)?.message ?? err}`)
    }
  }

  private fetchKnockDownloadUrl(fileId: string): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void) => {
      CloudApi.getDownloadUri(fileId, {
        onSuccess: (url: string) => {
          resolve((url.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
            url.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) ? url : CloudApi.getBaseURL() + url)
        },
        onFailure: (msg: string) => {
          AppLogger.error(TAG, `knock share get download uri failed: ${msg}`)
          resolve('')
        }
      })
    })
  }

  itemRename(index: number, item: ObjectInfo) {
    this.inputMode = FileInputMode.RENAME
    this.inputTitle = $r('app.string.rename')
    this.inputPlaceholder = $r('app.string.rename')
    this.inputValue = item.name
    this.inputRenameIndex = index
    this.inputRenameItem = item
    this.openInputSheet()
  }

  // 入场动画结束后聚焦拉起键盘；重命名时默认只选中主文件名，
  // 避免连扩展名一起改掉，目录或无扩展名时全选
  private applyInputSheetSelection(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(INPUT_SHEET_TEXT_ID)
      } catch (err) {
        AppLogger.warn(TAG, 'requestFocus input sheet failed: ' + JSON.stringify(err))
      }
      if (this.inputMode !== FileInputMode.RENAME) {
        return
      }
      const isFile = this.inputRenameItem?.type !== Constant.OBJECT_DIR_TYPE
      const dotIndex = this.inputValue.lastIndexOf('.')
      const selectionEnd = (isFile && dotIndex > 0) ? dotIndex : this.inputValue.length
      this.inputTextController.setTextSelection(0, selectionEnd)
    }, INPUT_SHEET_SELECTION_DELAY)
  }

  itemNew(path: string, isDir: boolean) {
    this.inputMode = FileInputMode.NEW_OBJECT
    this.inputTitle = isDir ? $r('app.string.more_new_dir') : $r('app.string.more_new_file')
    this.inputPlaceholder = isDir ? $r('app.string.new_dir_placeholder') : $r('app.string.new_file_placeholder')
    this.inputValue = ''
    this.inputNewPath = path
    this.inputNewIsDir = isDir
    this.openInputSheet()
  }

  private openSelectFileSheet(): void {
    this.selectFileSheetCtrl.requestOpen(() => this.showSelectFileSheet, (value: boolean) => {
      this.showSelectFileSheet = value
    })
  }

  private openInputSheet(): void {
    this.inputSheetCtrl.requestOpen(() => this.showInputSheet, (value: boolean) => {
      this.showInputSheet = value
    })
  }

  private openShareSheet(item: ObjectInfo): void {
    const share = this.getShareForObject(item)
    this.shareTarget = item
    this.shareLinkText = share?.url ?? ''
    this.sharePassword = ''
    this.shareExpireDays = ShareExpireDays.SEVEN_DAYS
    this.shareBusy = false
    this.shareSheetCtrl.requestOpen(() => this.showShareSheet, (value: boolean) => {
      this.showShareSheet = value
    })
    this.refreshShareLinks()
  }

  private closeFileSheet(): void {
    this.showSelectFileSheet = false
  }

  private closeInputSheet(): void {
    this.showInputSheet = false
  }

  private closeShareSheet(): void {
    this.showShareSheet = false
  }

  private closeDetailSheet(): void {
    this.showObjectDetail = false
  }

  private openPathSelectSheet(): void {
    this.pathSelectSheetCtrl.requestOpen(() => this.showPathSelect, (value: boolean) => {
      this.showPathSelect = value
    })
  }

  private closePathSelectSheet(): void {
    this.showPathSelect = false
  }

  private getCurrentShare(): ShareLinkInfo | undefined {
    if (!this.shareTarget) {
      return undefined
    }
    return this.getShareForObject(this.shareTarget)
  }

  private getCurrentShareId(): string {
    return this.getCurrentShare()?.id ?? ''
  }

  private getCurrentSharePasswordText(): string {
    const share = this.getCurrentShare()
    return share?.password ?? ''
  }

  private formatShareDate(value: string | undefined): string {
    if (!value || value.length === 0) {
      return '-'
    }
    const date = new Date(value)
    const formatted = DateFormatUtil.format(date, 'yyyy-MM-dd HH:mm')
    return formatted === '-' ? value : formatted
  }

  private getCurrentShareStatusText(): string {
    const share = this.getCurrentShare()
    if (!share) {
      return '-'
    }
    if (share.expired === true) {
      return '已过期'
    }
    const expireText = share.expires ?? share.expired_at ?? ''
    if (expireText.length > 0 && new Date(expireText).getTime() <= Date.now()) {
      return '已过期'
    }
    return share.password_protected === true || (share.password?.length ?? 0) > 0 ? '私密分享' : '公开分享'
  }

  private getCurrentShareExpireText(): string {
    const share = this.getCurrentShare()
    if (!share) {
      return '-'
    }
    const expireText = share.expires ?? share.expired_at ?? ''
    if (expireText.length === 0) {
      return '永久有效'
    }
    return this.formatShareDate(expireText)
  }

  private getCurrentShareCreatedText(): string {
    return this.formatShareDate(this.getCurrentShare()?.created_at)
  }

  private getCurrentShareVisitedText(): string {
    const visited = this.getCurrentShare()?.visited
    return visited === undefined ? '-' : `${visited} 次`
  }

  private getCurrentShareDownloadedText(): string {
    const downloaded = this.getCurrentShare()?.downloaded
    return downloaded === undefined ? '-' : `${downloaded} 次`
  }

  private buildGeneratedShareExpires(expireDays: number): string | undefined {
    if (expireDays <= 0) {
      return undefined
    }
    const date = new Date()
    date.setDate(date.getDate() + expireDays)
    return date.toISOString()
  }

  private createShareForTarget(): void {
    if (!this.shareTarget || this.shareBusy) {
      return
    }
    const target = this.shareTarget
    const path = this.getObjectSharePath(target)
    this.shareBusy = true
    AppLogger.info(TAG, `share create, expireDays=${this.shareExpireDays}, withPassword=${this.sharePassword.trim().length > 0}`)
    CloudApi.createShareLink(path, this.shareExpireDays, this.sharePassword.trim(), {
      onSuccess: (url: string) => {
        const generatedShare: ShareLinkInfo = {
          id: '',
          name: target.name,
          url: url,
          source_uri: path,
          expired: false,
          source_type: target.type === Constant.OBJECT_DIR_TYPE ? 1 : 0,
          expires: this.buildGeneratedShareExpires(this.shareExpireDays),
          created_at: new Date().toISOString(),
          password: this.sharePassword.trim().length > 0 ? this.sharePassword.trim() : undefined
        }
        const targetPath = this.getObjectSharePath(target)
        const targetParent = this.normalizeSharePath(target.path)
        this.shareLinks = this.shareLinks
          .filter((link: ShareLinkInfo) => {
            const linkPath = this.getShareFullPath(link)
            if (linkPath.length > 0) {
              if (linkPath === targetPath) {
                return false
              }
              const linkName = (link.name ?? '').trim()
              if (linkName.length > 0 && linkName === target.name && linkPath === targetParent &&
                this.isShareTypeMatched(link, target)) {
                return false
              }
              return true
            }
            return !this.isShareNameOnlyMatched(link, target)
          })
          .concat([generatedShare])
        this.sharedPaths = this.rebuildSharedPaths(this.shareLinks)
        this.shareLinkText = url
        this.shareBusy = false
        this.refreshShareLinks()
        showToast('分享链接已创建')
      },
      onFailure: (msg: string) => {
        AppLogger.error(TAG, '创建分享失败 msg: ' + msg)
        this.shareBusy = false
        showToast(msg.includes('require V4') ? '当前站点暂不支持分享链接' : '创建分享失败')
      }
    })
  }

  private deleteShareForTarget(): void {
    const share = this.getCurrentShare()
    if (!share || share.id.length === 0 || this.shareBusy) {
      return
    }
    const sharePath = this.getSharePath(share)
    this.shareBusy = true
    AppLogger.info(TAG, `share delete`)
    CloudApi.deleteShareLink(share.id, {
      onSuccess: () => {
        this.shareLinks = this.shareLinks.filter((link: ShareLinkInfo) => link.id !== share.id)
        this.sharedPaths = this.rebuildSharedPaths(this.shareLinks)
        this.shareLinkText = ''
        this.shareBusy = false
        if (sharePath.length > 0) {
          this.sharedPaths = this.sharedPaths.filter((path: string) => path !== sharePath)
        }
        this.refreshShareLinks()
        showToast('已取消分享')
      },
      onFailure: (msg: string) => {
        AppLogger.error(TAG, '取消分享失败 msg: ' + msg)
        this.shareBusy = false
        showToast('取消分享失败')
      }
    })
  }

  private copyShareLink(): void {
    if (this.shareLinkText.length === 0) {
      return
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareLinkText)
      pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
        showToast($r('app.string.copy_success'))
      }).catch((err: Error) => {
        AppLogger.error(TAG, 'copy share link failed: ' + err.message)
        showToast($r('app.string.copy_failed'))
      })
    } catch (err) {
      AppLogger.error(TAG, 'copy share link failed: ' + JSON.stringify(err))
      showToast($r('app.string.copy_failed'))
    }
  }

  private resetInputSheetState(): void {
    this.inputMode = FileInputMode.NONE
    this.inputValue = ''
    this.inputRenameIndex = -1
    this.inputRenameItem = undefined
  }

  private confirmInputSheet(): void {
    const content = this.inputValue.trim()
    if (content.length === 0) {
      return
    }

    if (this.inputMode === FileInputMode.RENAME) {
      this.confirmRename(content)
    } else if (this.inputMode === FileInputMode.NEW_OBJECT) {
      this.confirmNewObject(content)
    }
  }

  private confirmRename(content: string): void {
    const item = this.inputRenameItem
    const index = this.inputRenameIndex
    if (!item || index < 0) {
      this.closeInputSheet()
      return
    }

    if (item.name === content) {
      this.closeInputSheet()
      return
    }

    AppLogger.info(TAG, `rename ${item.type === Constant.OBJECT_DIR_TYPE ? 'dir' : 'file'}`)
    CloudApi.renameObject(item.id, content, item.type == Constant.OBJECT_DIR_TYPE, {
      onSuccess: (data) => {
        item.name = content
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          console.info(TAG, 'index dir ' + index)
          this.dirDataSource.deleteData(index)
          this.dirDataSource.addData(index, item)
        } else {
          console.info(TAG, 'index file ' + index)
          this.fileDataSource.deleteData(index)
          this.fileDataSource.addData(index, item)
        }
        // 修改名称需要重新排序
        if (this.sortType == SortType.SORT_BY_NAME) {
          this.objectsInfo.sortObjects(this.sortType, this.isSortTypeReverse(this.sortType))
          this.dirDataSource.notifyDataReload()
          this.fileDataSource.notifyDataReload()
        }
        this.closeInputSheet()
        showToast($r('app.string.rename_success'))
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, '重命名失败 msg: ' + msg)
        if (ApiErrorUtil.isObjectExisted(msg)) {
          showToast(`已存在同名${item.type == Constant.OBJECT_DIR_TYPE ? '文件夹' : '文件'}`)
        } else {
          showApiFailureToast(msg, $r('app.string.rename_failed'))
        }
      }
    })
  }

  /**
   * 新建文本文件后直接打开编辑器。
   * 服务端刚建好的文件还没回到列表里，这里用已知的路径和文件名自己拼一个
   * ObjectInfo；大小为 0，编辑器按空文件加载。
   */
  private openNewTextFile(dirPath: string, fileName: string): void {
    const sep = dirPath.endsWith('/') ? '' : '/'
    const fullPath = `${dirPath}${sep}${fileName}`
    const created: ObjectInfo = {
      id: fullPath, name: fileName, path: dirPath,
      thumb: false, size: 0, type: Constant.OBJECT_FILE_TYPE,
      date: '', create_date: '', source_enabled: false
    }
    const refreshPath = this.currentPath
    TextPreviewEntry.open(created, () => {
      this.getFileList(true, refreshPath)
    })
  }

  private confirmNewObject(content: string): void {
    AppLogger.info(TAG, `new ${this.inputNewIsDir ? 'dir' : 'file'} under ${this.inputNewPath}`)
    CloudApi.newObject(`${this.inputNewPath}/${content}`, this.inputNewIsDir, {
      onSuccess: (data) => {
        const createdPath = this.inputNewPath
        const isDir = this.inputNewIsDir
        this.closeInputSheet()
        this.getFileList(true, this.currentPath)
        showToast(`新建${content}成功`)
        // 新建的文本文件直接进编辑器：建完一个空文件却没处填内容，等于没建
        if (!isDir && CommonUtil.isTextViewable(CommonUtil.getFileType(content))) {
          this.openNewTextFile(createdPath, content)
        }
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, '新建文件/文件夹失败 msg: ' + msg)
        if (ApiErrorUtil.isObjectExisted(msg)) {
          showToast(`已存在同名${this.inputNewIsDir ? '文件夹' : '文件'}`)
        } else {
          showApiFailureToast(msg, `新建${content}失败`)
        }
      }
    })
  }

  // App 内从备份目录删除/移出文件后，记录文件名；相册变为活动时精确撤销这些图的已备份标记（小云朵）。
  private recordBackupRemoved(names: string[]): void {
    if (names.length > 0 && PhotoBackupSettingsStore.isBackupPath(this.currentPath)) {
      PhotoBackupSettingsStore.markRemoteRemoved(names)
    }
  }

  // App 内删掉整个目录后：若删的目录就是备份目录或其祖先，置全量撤销标志——
  // 相册变为活动时一次性把所有"已备份"云朵撤掉，不用等逐张点开单点核查。
  private recordBackupDirRemoved(dirPaths: string[]): void {
    if (dirPaths.some((p: string) => PhotoBackupSettingsStore.coversBackupPath(p))) {
      PhotoBackupSettingsStore.markRemoteRemovedAll()
    }
  }

  private basename(path: string): string {
    const idx = path.lastIndexOf('/')
    return idx >= 0 ? path.substring(idx + 1) : path
  }

  itemDelete(index: number, item: ObjectInfo) {
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.delete_confirm'),
      message: item.name,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        AppLogger.info(TAG, `delete ${item.type === Constant.OBJECT_DIR_TYPE ? 'dir' : 'file'}`)
        const remotePath = this.joinRemotePath(this.currentPath, item.name)
        const filePaths: string[] = item.type === Constant.OBJECT_DIR_TYPE ? [] : [remotePath]
        const dirPaths: string[] = item.type === Constant.OBJECT_DIR_TYPE ? [remotePath] : []
        const finishDelete = (): void => {
          if (item.type == Constant.OBJECT_DIR_TYPE) {
            this.dirDataSource.deleteData(index)
            this.isGridPadding = this.getFolderPaddingCount() > 0
            this.recordBackupDirRemoved(dirPaths)
          } else {
            this.fileDataSource.deleteData(index)
            this.recordBackupRemoved([item.name])
          }
          this.getFileList(true, this.currentPath)
          showToast($r('app.string.delete_success'))
        }
        const performDelete = (): void => {
          CloudApi.deleteObjectLockAware(item.id, item.type == Constant.OBJECT_DIR_TYPE, remotePath, {
            onSuccess: () => finishDelete(),
            onFailure: (msg: string, conflicts: FileLockConflict[]) => {
              // 取消服务器上传会话可能会一并移除尚未完成的零字节占位文件。
              // 后续删除返回“不存在”时应按幂等成功收口，避免继续使用旧 metadata 反复弹解除占用。
              if (this.isObjectMissingMessage(msg)) {
                AppLogger.info(TAG, `delete target already removed after relieving upload session id=${item.id}`)
                finishDelete()
                return
              }
              AppLogger.error(TAG, '删除失败 msg: ' + msg)
              this.tryRelieveOccupiedAndRetry(filePaths, dirPaths, performDelete, msg, conflicts)
            }
          })
        }
        performDelete()
      }
    })
  }

  /** 拼服务端 remote 路径，用于跟 upload session 的 remotePath 精确/前缀比对 */
  private joinRemotePath(dir: string, name: string): string {
    const base = dir.endsWith('/') ? dir : dir + '/'
    return base + name
  }

  /**
   * 删除失败兜底：查两处 session 源（相册备份 + 文件上传）是否有匹配本次目标路径的会话；
   * 有则弹对话框问用户是否解除占用；用户确认后逐个 deleteUploadSession + 清本地记录 + 重试删除。
   * 无匹配 session 则回退到通用「删除失败」toast——避免把服务端其它类型的失败（权限/网络）
   * 误导成「被占用」。文案里给出会话计数让用户明确解除的是哪批任务。
   */
  private tryRelieveOccupiedAndRetry(filePaths: string[], dirPaths: string[], retry: () => void,
    failureMessage: string = '', conflicts: FileLockConflict[] = []): void {
    const summary: UploadSessionSummary = UploadSessionRelief.summarize(filePaths, dirPaths)
    const serverSessions: ServerUploadSession[] = []
    const selectedPath = filePaths.length > 0 ? filePaths[0] : (dirPaths.length > 0 ? dirPaths[0] : '')
    const selectedName = selectedPath.length > 0 ? this.basename(selectedPath) : ''
    const selectedItem = this.objectsInfo.objects.find((item: ObjectInfo) => item.name === selectedName)
    const listedSessionId = selectedItem?.metadata?.['sys:upload_session_id'] ?? ''
    if (listedSessionId.length > 0 && selectedPath.length > 0) {
      serverSessions.push({ remotePath: selectedPath, sessionId: listedSessionId })
    }
    const lockTokens = Array.from(new Set<string>(conflicts
      .filter((conflict: FileLockConflict) => !!conflict.token && conflict.token.length > 0)
      .map((conflict: FileLockConflict) => conflict.token ?? '')))
    const hasServerLockConflict = ApiErrorUtil.isLockConflict(failureMessage) || conflicts.length > 0
    if (summary.count === 0 && lockTokens.length === 0 && serverSessions.length === 0) {
      if (hasServerLockConflict) {
        showCloudConfirmDialog(this.getUIContext(), {
          title: $r('app.string.upload_occupied_title'),
          message: '服务器确认该文件正被上传、备份或在线编辑任务占用，但当前账号没有可解除的锁。' +
            '请先结束占用任务，或在创建该任务的设备上取消后重试。',
          confirmText: '知道了',
          onConfirm: () => {}
        })
        return
      }
      showToast($r('app.string.delete_failed'))
      return
    }
    const total = filePaths.length + dirPaths.length
    const targetHint = total === 1 ? '该项' : `所选 ${total} 项`
    const details: string[] = []
    if (lockTokens.length > 0) {
      details.push(`${lockTokens.length} 个云端文件锁`)
    }
    if (summary.count > 0) {
      details.push(`${summary.count} 个本机未完成上传会话`)
    }
    if (serverSessions.length > 0) {
      details.push(`${serverSessions.length} 个服务器上传会话`)
    }
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.upload_occupied_title'),
      message: `${targetHint}检测到${details.join('和')}。解除占用会终止对应的上传、备份或在线编辑任务，` +
        '是否解除后重试删除？',
      confirmText: $r('app.string.upload_occupied_relieve'),
      onConfirm: () => {
        this.relieveLocksAndRetry(summary, filePaths, dirPaths, lockTokens, serverSessions, retry)
      }
    })
  }

  private handleDownloadAction(object: TransportObject, action: TransferAction): void {
    const id = object.item.id
    switch (action) {
      case TransferAction.PAUSE:
        requestDownload.pause(id)
        break
      case TransferAction.RESUME:
        if (object.state == FileModelState.FAILED) {
          const ctx = this.getAbilityContext()
          if (ctx) {
            const item = object.item
            const filePath = object.path
            const cachePath = `${ctx.cacheDir}/${item.name}`
            const partialBytes = FileSystemUtil.getFileSize(cachePath)
            AppLogger.info(TAG, `retry failed task: cache partial=${partialBytes} bytes`)
            this.downloadObjects.deleteDataByItem(object)
            TransferDatabase.deleteDownload(id)
            this.enqueueDownloadTask(ctx, item, filePath, partialBytes > 0 ? partialBytes : 0)
          }
        } else if (requestDownload.getTaskTid(id).length > 0) {
          requestDownload.resume(id)
        } else {
          const ctx = this.getAbilityContext()
          if (ctx) {
            this.restoreDownloadAndResume(ctx, object)
          }
        }
        break
      case TransferAction.CANCEL:
        const wasActive = object.state != FileModelState.COMPLETED &&
          object.state != FileModelState.FAILED &&
          object.state != FileModelState.REMOVED
        requestDownload.deleteTask(id)
        if (object.state != FileModelState.COMPLETED) {
          const ctx = this.getAbilityContext()
          if (ctx) {
            FileSystemUtil.unlinkIfExists(`${ctx.cacheDir}/${object.item.name}`)
          }
        }
        TransferDatabase.deleteDownload(id)
        object.state = FileModelState.REMOVED
        this.downloadObjects.deleteDataByItem(object)
        if (wasActive) {
          this.downloadingCount = Math.max(0, this.downloadingCount - 1)
        }
        break
      case TransferAction.CLEAR_COMPLETED:
        this.clearCompletedDownloads()
        break
    }
  }

  private clearCompletedDownloads(): void {
    const completed = this.downloadObjects.dataArray.filter(
      (o: TransportObject) => o.state == FileModelState.COMPLETED)
    for (const obj of completed) {
      this.handleDownloadAction(obj, TransferAction.CANCEL)
    }
  }

  private handleUploadAction(object: TransportObject, action: TransferAction): void {
    switch (action) {
      case TransferAction.PAUSE:
        if (object.state == FileModelState.RUNNING || object.state == FileModelState.WAITING) {
          object.state = FileModelState.PAUSED
          TransferDatabase.updateUploadState(object.id, FileModelState.PAUSED)
        }
        break
      case TransferAction.RESUME:
        const ctx = this.getAbilityContext()
        if (ctx) {
          uploadManager.resume(object, ctx, () => this.refreshIfCurrentDir(object), () => {})
        }
        break
      case TransferAction.CANCEL:
        const wasUploadActive = object.state != FileModelState.COMPLETED &&
          object.state != FileModelState.FAILED &&
          object.state != FileModelState.REMOVED
        uploadManager.cancel(object)
        this.uploadObjects.deleteDataByItem(object)
        if (wasUploadActive) {
          this.uploadingCount = Math.max(0, this.uploadingCount - 1)
        }
        break
      case TransferAction.CLEAR_COMPLETED:
        this.clearCompletedUploads()
        break
    }
  }

  private clearCompletedUploads(): void {
    const completed = this.uploadObjects.dataArray.filter(
      (o: TransportObject) => o.state == FileModelState.COMPLETED)
    for (const obj of completed) {
      this.handleUploadAction(obj, TransferAction.CANCEL)
    }
  }

  private refreshIfCurrentDir(object: TransportObject): void {
    const parent = object.item.path
    if (parent === this.currentPath) {
      this.getFileList(true, this.currentPath)
    }
  }

  private mapAgentStateToModel(state: request.agent.State): FileModelState {
    switch (state) {
      case request.agent.State.INITIALIZED:
      case request.agent.State.WAITING:
        return FileModelState.WAITING
      case request.agent.State.RUNNING:
        return FileModelState.RUNNING
      case request.agent.State.RETRYING:
        return FileModelState.RETRYING
      case request.agent.State.PAUSED:
        return FileModelState.PAUSED
      case request.agent.State.STOPPED:
        return FileModelState.STOPPED
      case request.agent.State.COMPLETED:
        return FileModelState.COMPLETED
      case request.agent.State.FAILED:
        return FileModelState.FAILED
      default:
        return FileModelState.STOPPED
    }
  }

  async restoreTransfers(): Promise<void> {
    const ctx = this.getAbilityContext()
    if (!ctx) {
      AppLogger.warn(TAG, 'restoreTransfers: ctx is null')
      return
    }
    TransferDatabase.resetAllUploadsToPaused()

    const downloads = TransferDatabase.listDownloads()
    AppLogger.info(TAG, `restoreTransfers: ${downloads.length} downloads, ${TransferDatabase.listUploads().length} uploads`)
    for (const record of downloads) {
      const object = new TransportObject(record.item, record.path, record.url, record.id)
      object.trans = record.trans
      object.total = record.total
      object.progress = record.total > 0 ?
        Math.min(Constant.BACKGROUND_TASK_COMPLETE_PERCENT,
          Math.floor(record.trans / record.total * Constant.BACKGROUND_TASK_COMPLETE_PERCENT)) : 0

      if (record.state === FileModelState.COMPLETED || record.state === FileModelState.FAILED) {
        object.state = record.state
        this.downloadObjects.pushData(object)
        continue
      }

      if (record.tid.length === 0) {
        object.state = FileModelState.PAUSED
        TransferDatabase.updateDownloadProgress(record.id, record.trans, FileModelState.PAUSED)
        this.downloadObjects.pushData(object)
        continue
      }

      const taskInfo = await requestDownload.showTask(record.tid)
      if (!taskInfo) {
        AppLogger.warn(TAG, `restoreTransfers: task ${record.tid} not found, marking FAILED`)
        object.state = FileModelState.FAILED
        TransferDatabase.updateDownloadProgress(record.id, record.trans, FileModelState.FAILED)
        this.downloadObjects.pushData(object)
        continue
      }

      const realState = this.mapAgentStateToModel(taskInfo.progress.state)
      const realTrans = Number(taskInfo.progress.processed.toString())
      AppLogger.info(TAG, `restoreTransfers: tid=${record.tid}, agentState=${taskInfo.progress.state}, modelState=${realState}, trans=${realTrans}`)

      object.trans = realTrans
      object.progress = object.total > 0 ?
        Math.min(Constant.BACKGROUND_TASK_COMPLETE_PERCENT,
          Math.floor(realTrans / object.total * Constant.BACKGROUND_TASK_COMPLETE_PERCENT)) : 0
      object.state = realState
      TransferDatabase.updateDownloadProgress(record.id, realTrans, realState)

      if (realState === FileModelState.RUNNING || realState === FileModelState.WAITING ||
        realState === FileModelState.RETRYING) {
        const fileModel = this.buildDownloadFileModel(ctx, record.item, record.path, record.url, object)
        requestDownload.restoreTask(record.id, ctx, record.tid, fileModel, false)
        this.downloadingCount++
      } else if (realState === FileModelState.COMPLETED) {
        const restoredCache = `${ctx.cacheDir}/${object.item.name}`
        const actualSize = FileSystemUtil.getFileSize(restoredCache)
        if (object.total > 0 && actualSize !== object.total) {
          // 系统任务声称完成但缓存尺寸不符（直链过期返回错误响应），按失败处理
          AppLogger.warn(TAG,
            `restoreTransfers: completed but size mismatch, actual=${actualSize}, expect=${object.total}, mark FAILED`)
          object.state = FileModelState.FAILED
          TransferDatabase.updateDownloadProgress(record.id, record.trans, FileModelState.FAILED)
          FileSystemUtil.unlinkIfExists(restoredCache).catch((err: Error) => {
            AppLogger.error(TAG, `restoreTransfers cleanup failed: ${err}`)
          })
        } else {
          FileSystemUtil.moveFile(restoredCache, record.path, 0).catch((err: Error) => {
            AppLogger.error(TAG, `restoreTransfers move failed: ${err}`)
          })
        }
      }

      this.downloadObjects.pushData(object)
    }

    uploadManager.restoreFromPersistence(this.uploadObjects)
  }

  private restoreDownloadAndResume(context: common.UIAbilityContext, object: TransportObject): void {
    const records = TransferDatabase.listDownloads()
    const record = records.find(r => r.id === object.id)
    const cachePath = `${context.cacheDir}/${object.item.name}`
    const partialBytes = FileSystemUtil.getFileSize(cachePath)
    // 跨会话恢复时旧下载直链通常已过期，复用旧系统任务会把服务端的错误响应当成下载内容；
    // 统一移除旧任务，用新直链按缓存中已下载的字节数重新续传
    if (record && record.tid.length > 0) {
      requestDownload.removeSystemTask(record.tid)
    }
    AppLogger.info(TAG, `restoreDownloadAndResume: re-enqueue id=${object.id} with fresh url, begins=${partialBytes}`)
    this.downloadObjects.deleteDataByItem(object)
    TransferDatabase.deleteDownload(object.id)
    this.enqueueDownloadTask(context, object.item, object.path, partialBytes > 0 ? partialBytes : 0)
  }

  private buildDownloadFileModel(context: common.UIAbilityContext, item: ObjectInfo,
                                  filePath: string, url: string, object: TransportObject): FileModel {
    let isCounted = true
    let lastPersistAt = 0
    let tidPersisted = ''
    return new FileModel(item.id, filePath, url, undefined, (trans, state) => {
      if (state == FileModelState.COMPLETED) {
        // 直链过期等场景服务端会返回小体积错误响应并正常结束请求，completed 不可盲信；
        // 校验缓存文件实际大小，尺寸不符则按失败处理并清掉脏文件
        const cachePath = `${context.cacheDir}/${object.item.name}`
        const actualSize = FileSystemUtil.getFileSize(cachePath)
        if (item.size > 0 && actualSize !== item.size) {
          AppLogger.warn(TAG,
            `download completed but size mismatch, actual=${actualSize}, expect=${item.size}, id=${item.id}`)
          FileSystemUtil.unlinkIfExists(cachePath).catch((err: Error) => {
            AppLogger.error(TAG, `cleanup bad download failed: ${err}`)
          })
          // 大概率是直链过期被服务端塞了错误响应：自动换新直链重下一次
          if (!this.retriedBadDownloadIds.has(item.id)) {
            this.retriedBadDownloadIds.add(item.id)
            AppLogger.info(TAG, `auto retry download with fresh url, id=${item.id}`)
            this.downloadObjects.deleteDataByItem(object)
            TransferDatabase.deleteDownload(object.id)
            if (isCounted) {
              this.downloadingCount = Math.max(0, this.downloadingCount - 1)
              isCounted = false
            }
            this.enqueueDownloadTask(context, item, filePath, 0)
            return
          }
          state = FileModelState.FAILED
        } else {
          this.retriedBadDownloadIds.delete(item.id)
        }
      }
      // RequestDownload already suppresses progress callbacks while a download is paused
      // (via userPausedTids), so any RUNNING signal that reaches here is a real resume.
      // Force the state out of PAUSED/STOPPED before delegating to update(), which would
      // otherwise gate the transition to protect the user-pause intent.
      if (state == FileModelState.RUNNING &&
        (object.state == FileModelState.PAUSED || object.state == FileModelState.STOPPED)) {
        object.state = FileModelState.RUNNING
      }
      object.update(trans, state)
      if (state == FileModelState.COMPLETED) {
        FileSystemUtil.moveFile(`${context.cacheDir}/${object.item.name}`, filePath, 0).catch((err: Error) => {
          AppLogger.error(TAG, `err: ${err}`)
        })
      }
      if (isCounted && (state == FileModelState.COMPLETED || state == FileModelState.FAILED)) {
        this.downloadingCount = Math.max(0, this.downloadingCount - 1)
        isCounted = false
      }
      if (tidPersisted.length === 0) {
        const tid = requestDownload.getTaskTid(item.id)
        if (tid.length > 0) {
          TransferDatabase.updateDownloadTid(item.id, tid)
          tidPersisted = tid
        }
      }
      const now = new Date().getTime()
      const isTerminal = state == FileModelState.COMPLETED || state == FileModelState.FAILED
      const isPauseLike = state == FileModelState.PAUSED || state == FileModelState.STOPPED
      if (isTerminal || isPauseLike || state == FileModelState.RUNNING && now - lastPersistAt > Constant.TRANSFER_PERSIST_INTERVAL_MS) {
        TransferDatabase.updateDownloadProgress(item.id, trans, state)
        lastPersistAt = now
      }
    })
  }

  private enqueueDownloadTask(context: common.UIAbilityContext, item: ObjectInfo, filePath: string,
                               begins: number = 0): void {
    CloudApi.getDownloadUri(item.id, {
      onSuccess: (data) => {
        let url = (data.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
          data.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) ? data : CloudApi.getBaseURL() + data
        let object: TransportObject = new TransportObject(item, filePath, url)
        if (begins > 0) {
          object.trans = begins
          object.progress = item.size > 0 ?
            Math.min(Constant.BACKGROUND_TASK_COMPLETE_PERCENT,
              Math.floor(begins / item.size * Constant.BACKGROUND_TASK_COMPLETE_PERCENT)) : 0
        }
        this.downloadObjects.addData(0, object)
        this.downloadingCount++

        AppLogger.info(TAG, `enqueueDownloadTask: persisting id=${item.id}, path=${filePath}, begins=${begins}`)
        TransferDatabase.upsertDownload({
          id: item.id,
          item,
          path: filePath,
          url,
          tid: '',
          trans: begins,
          total: item.size,
          state: FileModelState.WAITING,
          createdAt: new Date().getTime()
        })

        this.attachDownloadFileModel(context, item, filePath, url, object, begins)
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, 'get download uri failed, msg: ' + msg)
        // 批量下载时多个任务可能同时失败，节流避免连环弹窗
        const now = new Date().getTime()
        if (now - this.lastDownloadFailToastAt > DOWNLOAD_FAIL_TOAST_INTERVAL_MS) {
          this.lastDownloadFailToastAt = now
          showApiFailureToast(msg, `${item.name} 获取下载链接失败`)
        }
      }
    })
  }

  private attachDownloadFileModel(context: common.UIAbilityContext, item: ObjectInfo,
                                   filePath: string, url: string, object: TransportObject,
                                   begins: number = 0): void {
    const fileModel = this.buildDownloadFileModel(context, item, filePath, url, object)
    // 直链短时效：批量下载排队久了会过期，任务真正启动时再换一条新链
    fileModel.refreshUrl = () => new Promise<string>((resolve: (url: string) => void, reject: (err: Error) => void) => {
      CloudApi.getDownloadUri(item.id, {
        onSuccess: (data: string) => {
          const fresh = (data.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
            data.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) ? data : CloudApi.getBaseURL() + data
          resolve(fresh)
        },
        onFailure: (msg: string) => reject(new Error(msg))
      })
    })
    requestDownload.downloadFileBackground(fileModel, context, begins)
  }

  @Builder albumSavingOverlay() {
    Column() {
      Blank()
      Column({ space: CloudThemeToken.spacingSection }) {
        Row()
          .width(CloudThemeToken.iconBoxXs)
          .height(CloudThemeToken.strongLineWidth)
          .borderRadius(CloudThemeToken.controlRadiusRoundLg)
          .backgroundColor(CloudThemeToken.line)
        Row({ space: CloudThemeToken.spacingCard }) {
          LoadingProgress()
            .width(CloudThemeToken.iconBoxMd)
            .height(CloudThemeToken.iconBoxMd)
            .color(CloudThemeToken.primary)
          Column({ space: CloudThemeToken.spacingXs }) {
            Text('正在保存图片')
              .fontSize(CloudThemeToken.textSizeTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary)
            Text(this.albumSaveText)
              .fontSize(CloudThemeToken.textSizeBody)
              .fontColor(CloudThemeToken.textSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .padding({
        left: CloudThemeToken.spacingPage,
        right: CloudThemeToken.spacingPage,
        top: CloudThemeToken.spacingSm,
        bottom: this.bottomRectHeight + CloudThemeToken.spacingPage
      })
      .borderRadius({
        topLeft: CloudThemeToken.controlRadiusXl,
        topRight: CloudThemeToken.controlRadiusXl
      })
      .backgroundColor(CloudThemeToken.surface)
      .shadow({
        radius: CloudThemeToken.spacingSection,
        color: 'rgba(0,0,0,0.22)',
        offsetX: 0,
        offsetY: -CloudThemeToken.spacingXs
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.24)')
    .hitTestBehavior(HitTestMode.Block)
  }

  @Builder batchOperationSheet() {
    Column({ space: CloudThemeToken.spacingPage }) {
      Column({ space: CloudThemeToken.spacingCard }) {
        // 进度是这里唯一真正被关心的信息，交给数字本身去承担
        Row({ space: CloudThemeToken.spacingMd }) {
          Text(`${this.batchOperationProcessed}`)
            .fontSize(CloudThemeToken.textSizeMetric)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
          Text(`/ ${this.batchOperationTotal}`)
            .fontSize(CloudThemeToken.textSizeLargePlus)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        Progress({
          value: this.batchOperationProcessed,
          total: Math.max(this.batchOperationTotal, 1),
          type: ProgressType.Capsule
        })
          .width('100%')
          .height(CloudThemeToken.spacingSm)
          .color(this.batchOperationPaused ? CloudThemeToken.textSecondary : CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        // 跳过和失败通常都是 0，没内容时整行不占位
        if (this.batchOperationSkipped > 0 || this.batchOperationFailed > 0) {
          Text(this.batchOperationOutcomeText())
            .width('100%')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(this.batchOperationFailed > 0
              ? CloudThemeToken.danger : CloudThemeToken.textSecondary)
            .textAlign(TextAlign.Start)
        }
      }
      .width('100%')

      Row({ space: CloudThemeToken.spacingCard }) {
        Button(this.batchOperationPaused ? '继续' : '暂停')
          .layoutWeight(1)
          .height(CloudThemeToken.rowHeightXl)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.batchOperationPaused ? CloudThemeToken.onPrimary : CloudThemeToken.primary)
          .backgroundColor(this.batchOperationPaused
            ? CloudThemeToken.primary : CloudThemeToken.primarySoft)
          .onClick(() => {
            this.toggleBatchOperationPause()
          })
        Button('取消')
          .layoutWeight(1)
          .height(CloudThemeToken.rowHeightXl)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.danger)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .onClick(() => {
            this.cancelBatchOperation()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingPage,
      right: CloudThemeToken.spacingPage,
      top: CloudThemeToken.spacingCard,
      // bindSheet 覆盖应用底栏，但操作按钮仍需避开系统手势条/三键导航区。
      // 与详情、分享、路径选择等系统半模态保持同一套底部安全间距。
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
  }

  /** 只讲非零的那部分——全部成功时这行根本不出现 */
  private batchOperationOutcomeText(): string {
    const parts: string[] = []
    if (this.batchOperationSkipped > 0) {
      parts.push(`已跳过 ${this.batchOperationSkipped}`)
    }
    if (this.batchOperationFailed > 0) {
      parts.push(`失败 ${this.batchOperationFailed}`)
    }
    return parts.join(' · ')
  }

  @Builder fileConflictDialog() {
    Column({ space: CloudThemeToken.spacingPanel }) {
      Text('目标位置已有同名文件')
        .width('100%')
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .textAlign(TextAlign.Start)

      // 文件本身是主角：判断要不要覆盖，靠的正是名字、大小和去向
      Row({ space: CloudThemeToken.spacingCard }) {
        Text(this.fileConflictTypeLabel())
          .width(CloudThemeToken.rowHeightMd)
          .height(CloudThemeToken.rowHeightMd)
          .borderRadius(CloudThemeToken.controlRadiusSm)
          .backgroundColor(CloudThemeToken.primarySoft)
          .fontSize(CloudThemeToken.textSizeMicro)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.primary)
          .textAlign(TextAlign.Center)
        Column({ space: CloudThemeToken.spacingTiny }) {
          Text(this.activeFileConflict?.name ?? '')
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(CloudThemeToken.textSizeLargePlus)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
          Text(this.fileConflictMeta())
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(CloudThemeToken.spacingCard)
      .borderRadius(CloudThemeToken.controlRadiusMd)
      .backgroundColor(CloudThemeToken.surfaceSubtle)
      .alignItems(VerticalAlign.Center)

      // "全部"是这个决策的作用范围，不是另外两个选项
      Row({ space: CloudThemeToken.spacingXl }) {
        Checkbox()
          .select(this.fileConflictApplyAll)
          .selectedColor(CloudThemeToken.primary)
          .width(CloudThemeToken.spacingSheetHorizontal)
          .height(CloudThemeToken.spacingSheetHorizontal)
          .onChange((value: boolean) => {
            this.fileConflictApplyAll = value
          })
        Text('其余同名项目都这样处理')
          .layoutWeight(1)
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textPrimary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.fileConflictApplyAll = !this.fileConflictApplyAll
      })

      Row({ space: CloudThemeToken.spacingCard }) {
        Button(this.fileConflictApplyAll ? '全部覆盖' : '覆盖')
          .layoutWeight(1)
          .height(CloudThemeToken.rowHeightXl)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.fileConflictApplyAll ? CloudThemeToken.onPrimary : CloudThemeToken.danger)
          .backgroundColor(this.fileConflictApplyAll ? CloudThemeToken.danger : CloudThemeToken.dangerSoft)
          .onClick(() => this.resolveFileConflict(FileConflictDecision.OVERWRITE, this.fileConflictApplyAll))
        // 跳过占主位：它是这里的高频选择，也是安全的那个
        Button(this.fileConflictApplyAll ? '全部跳过' : '跳过')
          .layoutWeight(1)
          .height(CloudThemeToken.rowHeightXl)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.primarySoft)
          .onClick(() => this.resolveFileConflict(FileConflictDecision.SKIP, this.fileConflictApplyAll))
      }
      .width('100%')

      Text('覆盖会先删除目标位置的同名项目。')
        .width('100%')
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding(CloudThemeToken.spacingSheetHorizontal)
    .borderRadius(CloudThemeToken.controlRadiusXl)
    .backgroundColor(CloudThemeToken.surface)
  }

  /** 图标位上的类型角标：文件夹给"目录"，文件给扩展名 */
  private fileConflictTypeLabel(): string {
    const request = this.activeFileConflict
    if (!request) {
      return ''
    }
    if (request.isDir) {
      return '目录'
    }
    const ext = CommonUtil.getFileExtention(request.name).toUpperCase()
    return ext.length > 0 && ext.length <= 4 ? ext : '文件'
  }

  private fileConflictMeta(): string {
    const request = this.activeFileConflict
    if (!request) {
      return ''
    }
    const action = this.objectSelect.type === FileMenuType.COPY ? '复制到' : '移动到'
    if (request.isDir) {
      return `${action} ${request.destination}`
    }
    return `${CommonUtil.formatBytes(request.size)} · ${action} ${request.destination}`
  }

  private async saveImagesFlow(context: common.UIAbilityContext, images: ObjectInfo[]): Promise<void> {
    if (images.length === 0) {
      return
    }
    this.albumSaving = true
    this.albumSaveText = `正在保存到相册 0/${images.length}`
    const result: SaveAlbumResult = await saveImagesToAlbum(images, context, (done: number, total: number) => {
      this.albumSaveText = `正在保存到相册 ${done}/${total}`
    })
    this.albumSaving = false
    if (result.canceled) {
      showToast('已取消保存')
    } else if (result.failed === 0) {
      showToast(`已保存 ${result.success} 张到相册`)
    } else {
      showToast(`已保存 ${result.success} 张，${result.failed} 张失败`)
    }
  }

  itemDownload(index: number, item: ObjectInfo) {
    try {
      const context = this.getAbilityContext();
      if (!context) {
        showToast($r('app.string.get_context_failed'));
        return;
      }
      if (CommonUtil.getFileType(item.name) === FileType.IMAGE) {
        this.saveImagesFlow(context, [item]);
        return;
      }
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD
      let documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.save(documentSaveOptions).then((documentSaveResult: Array<string>) => {
        if (documentSaveResult.length === 0) {
          return
        }
        let filePath = FileSystemUtil.getPathFromUri(documentSaveResult[Constant.FIRST_ARRAY_INDEX] + '/' + item.name);
        console.debug(TAG, 'documentViewPicker.save to file succeed and uris are:' + filePath);
        this.enqueueDownloadTask(context, item, filePath)
        showToast(`已开始下载，保存至 ${this.formatDownloadDirForDisplay(filePath, true)}`, Constant.TOAST_LONG_DURATION_MS)
      }).catch((err: BusinessError) => {
        AppLogger.error(TAG, `Invoke documentViewPicker.save failed, code is ${err.code}, message is ${err.message}`);
      })
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      AppLogger.error(TAG, `Error code: ${err.code}, message: ${err.message}`);
    }
  }

  startUpload(uris: string[]): void {
    if (uris.length === 0) return;

    const context = this.getAbilityContext();
    if (!context) {
      showToast($r('app.string.get_context_failed'));
      return;
    }
    const uploadPath = this.currentPath;
    const onDirChanged = () => { this.getFileList(true, uploadPath); };
    const onTaskEnd = () => { if (this.uploadingCount > 0) this.uploadingCount--; };

    const existingNames = new Set<string>(this.objectsInfo.fileObjects.map(f => f.name));
    // Set 去重：多选里出现同名文件时冲突列表不重复展示同一个名字
    const conflictNames = Array.from(new Set(uris
      .map(uri => { try { return uploadManager.extractFileName(uri); } catch { return ''; } })
      .filter(name => name.length > 0 && existingNames.has(name))));

    if (conflictNames.length === 0) {
      this.uploadingCount += uris.length;
      uploadManager.enqueue(uris, this.currentPath, false, context, this.uploadObjects, onDirChanged, onTaskEnd);
      return;
    }

    // 冲突过多时只展示前若干个，避免弹窗被文件名撑爆
    const maxShown = 5
    const conflictMessage = conflictNames.length > maxShown
      ? conflictNames.slice(0, maxShown).join('\n') + `\n……等 ${conflictNames.length} 个文件`
      : conflictNames.join('\n')

    showCloudActionDialog(this.getUIContext(), {
      title: $r('app.string.upload_conflict_title'),
      message: conflictMessage,
      primaryText: $r('app.string.upload_skip_existing'),
      secondaryText: $r('app.string.upload_overwrite_all'),
      onPrimary: () => {
        const conflictSet = new Set<string>(conflictNames);
        const filteredUris = uris.filter(uri => {
          try {
            return !conflictSet.has(uploadManager.extractFileName(uri));
          } catch {
            return true;
          }
        });
        if (filteredUris.length > 0) {
          this.uploadingCount += filteredUris.length;
          uploadManager.enqueue(filteredUris, this.currentPath, false, context, this.uploadObjects, onDirChanged, onTaskEnd);
        }
      },
      onSecondary: () => {
        this.uploadingCount += uris.length;
        uploadManager.enqueue(uris, this.currentPath, true, context, this.uploadObjects, onDirChanged, onTaskEnd);
      }
    });
  }

  private getAbilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext) {
      return hostContext as common.UIAbilityContext;
    }
    return undefined;
  }
}
