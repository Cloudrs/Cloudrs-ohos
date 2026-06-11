import {
  DirectoryInfo, DirFileInfo, ObjectDetail, ObjectInfo, Policy, ShareLinkInfo
} from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import TransferDatabase from "../../model/TransferDatabase";
import LazyDataSource from "../../utils/LazyDataSource";
import { CloudApi } from "../../model/net/CloudApi";
import { showToast, showToastTips, ToastType } from "../../utils/ToastUtil";
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
import { BusinessError, pasteboard, request } from "@kit.BasicServicesKit";
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
import UserPreferences from "../../model/UserPreferences";
import { DateFormatUtil } from "../../utils/DateFormatUtil";
import { CloudIconButton } from "../../components/CloudIconButton";
import {
  DividerShowType, HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial
} from "@kit.UIDesignKit";
import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import { Downloads, TransferAction } from "../../components/Downloads";
import { Uploads } from "../../components/Uploads";

const TAG = 'TabFiles';
const FILE_THUMB_MAX_CONCURRENT: number = 2
const FILE_THUMB_QUEUE_DELAY_MS: number = 500
const FILE_SHARE_REFRESH_DELAY_MS: number = 650

PersistentStorage.persistProp(Constant.CURRENT_SHOW_TYPE, ShowType.SHOW_ICON)
PersistentStorage.persistProp(Constant.CURRENT_SORT_TYPE, SortType.SORT_BY_NAME)
PersistentStorage.persistProp(Constant.CURRENT_SORT_TYPE_RESERVE, new Map<SortType, boolean>([
  [SortType.SORT_BY_NAME, false], [SortType.SORT_BY_TYPE, false],
  [SortType.SORT_BY_TIME, false], [SortType.SORT_BY_SIZE, false],
]))

class FileThumbSourceCache {
  static data: Map<string, string> = new Map<string, string>()

  static get(key: string): string {
    return FileThumbSourceCache.data.get(key) ?? ''
  }

  static set(key: string, source: string): void {
    FileThumbSourceCache.data.set(key, source)
  }

  static snapshot(scope: string): Map<string, string> {
    const result = new Map<string, string>()
    FileThumbSourceCache.data.forEach((source: string, key: string) => {
      if (key.startsWith(scope)) {
        result.set(key.substring(scope.length), source)
      }
    })
    return result
  }
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
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
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
  @State detailData: DetailData = new DetailData('Unknown', false, new ObjectDetail())
  private currentPath: string = '/'
  private scrollerForList: Scroller = new Scroller()
  @State dirDataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()
  @State fileDataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()
  private objectsInfo: DirFileInfo = new DirFileInfo();
  @State isGridPadding: boolean = false;
  @State showPathSelect: boolean = false
  private objectSelect: ObjectSelect = new ObjectSelect()

  @State downloadingCount: number = 0;
  @State uploadingCount: number = 0;
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
  private inputNewPath: string = '/'
  private inputNewIsDir: boolean = true
  private thumbLoadingIds: Set<string> = new Set<string>()
  private thumbFailedIds: Set<string> = new Set<string>()
  private thumbQueue: ObjectInfo[] = []
  private activeThumbLoads: number = 0
  private thumbQueueTimer: number = -1
  private shareRefreshTimer: number = -1
  private initialFileListRequested: boolean = false
  private loadingFilePath: string = ''

  private onActiveChanged(): void {
    if (!this.isActive) {
      if (this.thumbQueueTimer >= 0) {
        clearTimeout(this.thumbQueueTimer)
        this.thumbQueueTimer = -1
      }
      this.cancelScheduledShareRefresh()
      return
    }
    if (this.thumbQueue.length > 0) {
      this.scheduleThumbQueue()
    }
    if (this.dirDataSource.totalCount() > 0 || this.fileDataSource.totalCount() > 0) {
      this.scheduleShareLinksRefresh()
    }
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

  private shouldDimFileTitleActions(): boolean {
    return this.showObjectDetail ||
      this.showPathSelect ||
      this.showSelectFileSheet ||
      this.showInputSheet ||
      this.showShareSheet ||
      this.showTransportSheet
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
          this.showTransportSheet = true
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

  private getMultiSelectTitleMenu(): HdsNavigationMenuItemOptions[] {
    return [{
      content: {
        icon: $r('app.media.ic_selected'),
        label: '全选',
        action: () => {
          this.selectAllVisibleObjects()
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
      this.thumbSource))
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
    if (this.showType !== ShowType.SHOW_ICON) {
      return CloudThemeToken.singleColumnMaxCount
    }
    if (this.gridWidth >= CloudThemeToken.content4xlBreakpoint) {
      return CloudThemeToken.fileGrid4xlColumns
    }
    if (this.gridWidth >= CloudThemeToken.content3xlBreakpoint) {
      return CloudThemeToken.fileGrid3xlColumns
    }
    if (this.gridWidth >= CloudThemeToken.contentXxlBreakpoint) {
      return CloudThemeToken.fileGridXxlColumns
    }
    if (this.gridWidth >= CloudThemeToken.contentXlBreakpoint) {
      return CloudThemeToken.fileGridXlColumns
    }
    if (this.gridWidth >= CloudThemeToken.wideBreakpoint) {
      return CloudThemeToken.fileGridWideColumns
    }
    if (this.gridWidth >= CloudThemeToken.tabletBreakpoint) {
      return CloudThemeToken.fileGridTabletColumns
    }
    if (this.gridWidth >= CloudThemeToken.twoColumnBreakpoint) {
      return CloudThemeToken.fileGridMediumColumns
    }
    return CloudThemeToken.fileGridPhoneColumns
  }

  getGridColumnsTemplate(): string {
    const columns = this.getGridColumns()
    let templates: string[] = []
    for (let index = 0; index < columns; index++) {
      templates.push(CloudThemeToken.singleColumnTemplate)
    }
    return templates.join(' ')
  }

  getFolderPaddingCount(): number {
    if (this.showType !== ShowType.SHOW_ICON) {
      return CloudThemeToken.zero
    }
    const columns = this.getGridColumns()
    const remainder = this.dirDataSource.totalCount() % columns
    return remainder === 0 ? 0 : columns - remainder
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
    if (CloudThemeToken.isWideBreakpoint(bp)) {
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

  private addObjectSharePath(paths: string[], value: string): void {
    const path = this.normalizeSharePath(value)
    if (path.length > 0 && !paths.includes(path)) {
      paths.push(path)
    }
  }

  private getObjectSharePaths(item: ObjectInfo): string[] {
    const paths: string[] = []
    const hasPathId = this.isObjectIdPath(item)
    if (hasPathId) {
      this.addObjectSharePath(paths, item.id)
    }
    if (item.type === Constant.OBJECT_DIR_TYPE || !hasPathId) {
      this.addObjectSharePath(paths, CloudApi.getTotalPath(item))
    }
    return paths
  }

  private getSharePath(link: ShareLinkInfo): string {
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
        return this.getShareObjectPath(link, path)
      }
    }
    return ''
  }

  private getShareObjectPath(link: ShareLinkInfo, path: string): string {
    if (!this.isShareFileType(link) || !link.name || link.name.length === 0) {
      return path
    }
    const lastSeparator = path.lastIndexOf('/')
    const lastSegment = lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path
    if (lastSegment === link.name) {
      return path
    }
    return path === '/' ? `/${link.name}` : `${path}/${link.name}`
  }

  private isShareFileType(link: ShareLinkInfo): boolean {
    if (link.source_type === undefined) {
      return false
    }
    const sourceType = `${link.source_type}`.toLowerCase()
    return sourceType === '0' || sourceType === 'file'
  }

  private isShareTypeMatched(link: ShareLinkInfo, item: ObjectInfo): boolean {
    const isDir = item.type === Constant.OBJECT_DIR_TYPE
    if (link.source_type === undefined) {
      return true
    }
    const sourceType = `${link.source_type}`
    return isDir ? sourceType === '1' || sourceType.toLowerCase() === 'folder' :
      sourceType === '0' || sourceType.toLowerCase() === 'file'
  }

  private isShareNameMatched(link: ShareLinkInfo, item: ObjectInfo): boolean {
    return this.getSharePath(link).length === 0 &&
      link.name === item.name &&
      this.isShareTypeMatched(link, item)
  }

  private getShareForObject(item: ObjectInfo): ShareLinkInfo | undefined {
    const objectPaths = this.getObjectSharePaths(item)
    return this.shareLinks.find((link: ShareLinkInfo) => {
      if (link.expired === true) {
        return false
      }
      const sharePath = this.getSharePath(link)
      return sharePath.length > 0 ? objectPaths.includes(sharePath) : this.isShareNameMatched(link, item)
    })
  }

  private rebuildSharedPaths(links: ShareLinkInfo[]): string[] {
    const paths: string[] = []
    links.forEach((link: ShareLinkInfo) => {
      const path = this.getSharePath(link)
      if (path.length > 0 && !paths.includes(path) && link.expired !== true) {
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
        const links = data ? data.filter((link: ShareLinkInfo) => link.expired !== true) : []
        this.shareLinks = links
        this.sharedPaths = this.rebuildSharedPaths(links)
        console.debug(TAG, `share links loaded=${links.length}, mapped=${this.sharedPaths.join(',')}`)
        if (this.showShareSheet && this.shareTarget) {
          const existing = this.getShareForObject(this.shareTarget)
          if (existing) {
            this.shareLinkText = existing.url ?? ''
          }
        }
      },
      onFailure: (msg: string) => {
        console.debug(TAG, 'share list unavailable: ' + msg)
        this.shareLinks = []
        this.sharedPaths = []
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
      const item = this.thumbQueue.shift()
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

  async getFileList(isRefresh: boolean, path: string) {
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
    CloudApi.getFilesInfo(path, {
      onStart: () => {
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
        this.loadingFilePath = ''
        if (!shouldKeepContent) {
          this.searchKeyword = ''
        }
        this.subTitle = data.policy.name
        this.objectsInfo = new DirFileInfo(data.parent, data.objects, data.policy)
        this.objectsInfo.sortObjects(this.sortType, this.isSortTypeReverse(this.sortType))
        this.applyVisibleObjects()
        this.isRefreshing = false
        this.refreshPullOffset = CloudThemeToken.zero
        this.filePageState = FilePageState.IDLE
        this.scheduleShareLinksRefresh()
      },
      onFailure: (msg) => {
        this.loadingFilePath = ''
        showToastTips($r('app.string.get_failed'), ToastType.Error)
        //决定是否重新登录
        this.isRefreshing = false
        this.refreshPullOffset = CloudThemeToken.zero
        this.filePageState = shouldKeepContent ? FilePageState.IDLE : FilePageState.FAILED
      }
    })
  }

  dataSourceDelete() {
    let objects = this.objectSelect.copyMoveObjects
    if (objects.length > 1) {
      objects.forEach((item) => {
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          this.dirDataSource.deleteDataByItem(item)
          this.isGridPadding = this.getFolderPaddingCount() > 0
        } else {
          this.fileDataSource.deleteDataByItem(item)
        }
      })
    } else if (this.objectSelect.index !== -1) {
      if (objects[Constant.FIRST_ARRAY_INDEX].type == Constant.OBJECT_DIR_TYPE) {
        this.dirDataSource.deleteData(this.objectSelect.index)
        this.isGridPadding = this.getFolderPaddingCount() > 0
      } else {
        this.fileDataSource.deleteData(this.objectSelect.index)
      }
    }
  }

  copyMoveObjects(dst: string) {
    if (this.objectSelect.copyMoveObjects?.length > 0) {
      let src: ObjectSrc = new ObjectSrc()
      this.objectSelect.copyMoveObjects.forEach((item, index) => {
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          src.dirs.push(item.id)
        } else {
          src.items.push(item.id)
        }
      })

      if (this.objectSelect.type == FileMenuType.COPY) {
        let param: ObjectCopy = new ObjectCopy(this.currentPath, src, dst)
        CloudApi.copyObjects(param, {
          onSuccess: (data) => {
            showToast($r('app.string.copy_success'))
            this.exitMultiSelectMode()
          },
          onFailure: (msg) => {
            AppLogger.error(TAG, 'copy failed, msg: ' + msg)
            showToast($r('app.string.copy_failed'))
          }
        })
      } else if (this.objectSelect.type == FileMenuType.MOVE) {
        let param: ObjectMove = new ObjectMove(this.currentPath, src, dst)
        CloudApi.moveObjects(param, {
          onSuccess: (data) => {
            this.dataSourceDelete()
            this.exitMultiSelectMode()
            showToast($r('app.string.move_success'))
          },
          onFailure: (msg) => {
            AppLogger.error(TAG, 'move failed, msg: ' + msg)
            showToast($r('app.string.move_failed'))
          }
        })
      }
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
            await this.getFileList(true, this.currentPath);
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
          .borderRadius(CloudThemeToken.controlRadiusRoundXl)
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

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showObjectDetail, this.detailBindSheet(), {
            detents: [SheetSize.FIT_CONTENT],
            showClose: false,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onDisappear: () => {
              this.showObjectDetail = false
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showSelectFileSheet, this.selectFileSheetBuilder(), {
            detents: [SheetSize.FIT_CONTENT],
            showClose: false,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onDisappear: () => {
              this.showSelectFileSheet = false
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showInputSheet, this.inputSheetBuilder(), {
            detents: [SheetSize.FIT_CONTENT],
            showClose: false,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onDisappear: () => {
              this.showInputSheet = false
              this.resetInputSheetState()
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showShareSheet, this.shareSheetBuilder(), {
            detents: [SheetSize.FIT_CONTENT],
            showClose: false,
            backgroundColor: CloudThemeToken.background,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onDisappear: () => {
              this.showShareSheet = false
              this.shareTarget = null
              this.shareLinkText = ''
              this.sharePassword = ''
              this.shareBusy = false
            }
          })

        Column()
          .width(CloudThemeToken.zero)
          .height(CloudThemeToken.zero)
          .bindSheet($$this.showTransportSheet, this.transportSheetBuilder(), {
            backgroundColor: CloudThemeToken.surface,
            title: this.transportSheetTitle($r('app.string.transport_title')),
            showClose: false,
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onDisappear: () => {
              this.showTransportSheet = false
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
          maxCount: this.isMultiSelectMode ? 1 : 3
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
  }

  @Builder multiActionButton(icon: ResourceStr, title: string, action: () => void, danger: boolean = false) {
    Button({ type: ButtonType.Normal }) {
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
        .borderRadius(CloudThemeToken.controlRadiusRoundXl)
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
          this.fileMoreCommonItem($r('app.string.more_multi_select'), $r('app.media.ic_selected'), false, () => {
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
          this.fileMoreCommonItem($r('app.string.more_new_file'), $r('app.media.ic_doc_text_badge_arrow_up'), false, () => {
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
        this.sheetCloseButton(() => {
          this.showTransportSheet = false
        })
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

        this.sheetCloseButton(() => {
          this.closeInputSheet()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      TextInput({ text: this.inputValue, placeholder: this.inputPlaceholder })
        .width('100%')
        .height(CloudThemeToken.rowHeight2xl)
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontColor(CloudThemeToken.textPrimary)
        .placeholderColor(CloudThemeToken.textSecondary)
        .backgroundColor(CloudThemeToken.surface)
        .borderRadius(CloudThemeToken.controlRadius)
        .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
        .padding({ left: CloudThemeToken.spacingSection, right: CloudThemeToken.spacingSection })
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
      bottom: this.bottomRectHeight + CloudThemeToken.hdsTabBarBottomMargin + CloudThemeToken.spacingSheetBottom
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
    .zIndex(1)
  }

  @Builder shareSheetBuilder() {
    Column({ space: CloudThemeToken.spacingSheetTop }) {
      this.shareSheetHeader()
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

  @Builder shareSheetHeader() {
    Row() {
      Text(this.shareLinkText.length > 0 ? '分享链接' : '创建分享')
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      this.sheetCloseButton(() => {
        this.closeShareSheet()
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
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
        .onClick(async () => {
          this.onItemClick(item)
        })
      }, (item: ObjectInfo, index: number) => item.id)

      ForEach(this.getGridSpacerItems(), (item: number) => {
        GridItem() {
          Row()
            .width('100%')
            .height(this.tabBarHeight + CloudThemeToken.tabContentBottomGap)
        }
        .selectable(false)
      }, (item: number) => `bottom-spacer-${item}`)
    }
    .cachedCount(CloudThemeToken.fileGridCachedCount)
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
    .onDidScroll(() => {
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
      onDisappear: () => {
        this.showPathSelect = false
      }
    })
  }

  @Builder selectPathSheet() {
    PathSelectSheet({
      title: this.objectSelect.selectPathTitle,
      filterDirId: this.objectSelect.selectPathId,
      onClose: (isFinished: boolean, path?: string) => {
        this.closePathSelectSheet()
        if (isFinished && path && path != '') {
          console.debug(TAG, 'select path: ' + path)
          this.copyMoveObjects(path)
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
    .borderRadius(CloudThemeToken.controlRadius)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
    .onClick(onClose)
  }

  @Builder detailBindSheet() {
    Column() {
      Row() {
        Blank()
          .layoutWeight(1)
        this.sheetCloseButton(() => {
          this.closeDetailSheet()
        })
      }
      .height(CloudThemeToken.rowHeight2xl)
      .width('100%')
      .padding({ left: CloudThemeToken.spacingSheetHorizontal, right: CloudThemeToken.spacingPage, top: CloudThemeToken.spacingXl })

      this.detailSheet()
    }
    .width('100%')
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder detailOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.overlayScrim)
        .onClick(() => {
          this.showObjectDetail = false
          this.overLap = true
        })

      Column() {
        Row() {
          Blank()
            .layoutWeight(1)
          this.sheetCloseButton(() => {
            this.showObjectDetail = false
            this.overLap = true
          })
        }
        .height(CloudThemeToken.rowHeight2xl)
        .width('100%')
        .padding({ left: CloudThemeToken.spacingSheetHorizontal, right: CloudThemeToken.spacingPage, top: CloudThemeToken.spacingXl })

        this.detailSheet()
      }
      .width('100%')
      .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
      .backgroundColor(CloudThemeToken.background)
      .shadow({
        radius: CloudThemeToken.sheetShadowRadius,
        color: CloudThemeToken.sheetShadow,
        offsetY: CloudThemeToken.sheetShadowOffsetY
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(CloudThemeToken.overlayZIndex)
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
        CloudRouter.push(Constant.IAMGE_PREVIEW_PAGE, this.buildImagePreviewParam(item, fileExtension))
      } else if (fileType == FileType.VIDEO) {
        CloudRouter.push(Constant.VIDEO_PREVIEW_PAGE, new VideoPreview(item.name, item.id, fileExtension))
      } else {
        //filePreview.openPreview(getContext(), {title: item.name, uri: '', mimeType: ''})
        showToast('该类型不支持预览')
      }
    }
  }

  private buildImagePreviewParam(item: ObjectInfo, fileExtension: string): ImagePreview {
    const images = this.fileDataSource.dataArray
      .filter((file: ObjectInfo) => CommonUtil.getFileType(file.name) === FileType.IMAGE)
      .map((file: ObjectInfo) => new PreviewFile(file.name, file.id, CommonUtil.getFileExtention(file.name)))
    const currentIndex = images.findIndex((file: PreviewFile) => file.fileId === item.id)
    return new ImagePreview(item.name, item.id, fileExtension, images, currentIndex >= 0 ? currentIndex : 0)
  }

  async onMenuClick(index: number, item: ObjectInfo, type: FileMenuType) {
    console.debug(TAG, 'onMenuClick type: ' + type)
    switch (type){
      case FileMenuType.PREVIEW:
      case FileMenuType.DIR_ENTER:
        this.onItemClick(item)
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
    this.openPathSelectSheet()
  }

  private downloadSelectedObjects(): void {
    if (this.selectedObjects.length === 0) {
      return
    }

    const selectedFiles = this.selectedObjects.filter((item: ObjectInfo) => item.type !== Constant.OBJECT_DIR_TYPE)
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
        this.exitMultiSelectMode()
        showToast(`已添加${selectedFiles.length}个下载任务`)
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
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.delete_confirm'),
      message: selected.map((item: ObjectInfo) => item.name).join('\n'),
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        const src = new ObjectSrc()
        selected.forEach((item: ObjectInfo) => {
          if (item.type === Constant.OBJECT_DIR_TYPE) {
            src.dirs.push(item.id)
          } else {
            src.items.push(item.id)
          }
        })
        CloudApi.deleteObjects(src, {
          onSuccess: () => {
            this.objectSelect.copyMoveObjects = selected
            this.dataSourceDelete()
            this.exitMultiSelectMode()
            showToast($r('app.string.delete_success'))
          },
          onFailure: (msg) => {
            AppLogger.error(TAG, '批量删除失败 msg: ' + msg)
            showToast($r('app.string.delete_failed'))
          }
        })
      }
    })
  }

  itemDetail(item: ObjectInfo) {
    CloudApi.getObjectDetail(item.id, item.type == Constant.OBJECT_DIR_TYPE, {
      onSuccess: (data) => {
        this.detailData = new DetailData(item.name, item.type == Constant.OBJECT_DIR_TYPE, data)
        this.showObjectDetail = true
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, '获取详细信息失败 msg: ' + msg)
        showToast($r('app.string.get_detail_failed'))
      }
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
    this.showSelectFileSheet = true
  }

  private openInputSheet(): void {
    this.showInputSheet = true
  }

  private openShareSheet(item: ObjectInfo): void {
    const share = this.getShareForObject(item)
    this.shareTarget = item
    this.shareLinkText = share?.url ?? ''
    this.sharePassword = ''
    this.shareExpireDays = ShareExpireDays.SEVEN_DAYS
    this.shareBusy = false
    this.showShareSheet = true
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
    this.showPathSelect = true
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
        const targetPaths = this.getObjectSharePaths(target)
        this.shareLinks = this.shareLinks
          .filter((link: ShareLinkInfo) => {
            const linkPath = this.getSharePath(link)
            return linkPath.length > 0 ? !targetPaths.includes(linkPath) : !this.isShareNameMatched(link, target)
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
        showToast($r('app.string.rename_failed'))
      }
    })
  }

  private confirmNewObject(content: string): void {
    AppLogger.info(TAG, `new ${this.inputNewIsDir ? 'dir' : 'file'} under ${this.inputNewPath}`)
    CloudApi.newObject(`${this.inputNewPath}/${content}`, this.inputNewIsDir, {
      onSuccess: (data) => {
        this.closeInputSheet()
        this.getFileList(true, this.currentPath)
        showToast(`新建${content}成功`)
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, '新建文件/文件夹失败 msg: ' + msg)
        showToast(`新建${content}失败`)
      }
    })
  }

  itemDelete(index: number, item: ObjectInfo) {
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.delete_confirm'),
      message: item.name,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        AppLogger.info(TAG, `delete ${item.type === Constant.OBJECT_DIR_TYPE ? 'dir' : 'file'}`)
        CloudApi.deleteObject(item.id, item.type == Constant.OBJECT_DIR_TYPE, {
          onSuccess: (data) => {
            if (item.type == Constant.OBJECT_DIR_TYPE) {
              this.dirDataSource.deleteData(index)
              this.isGridPadding = this.getFolderPaddingCount() > 0
            } else {
              this.fileDataSource.deleteData(index)
            }
            showToast($r('app.string.delete_success'))
          },
          onFailure: (msg) => {
            AppLogger.error(TAG, '删除失败 msg: ' + msg)
            showToast($r('app.string.delete_failed'))
          }
        })
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
          this.downloadingCount--
        }
        break
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
          this.uploadingCount--
        }
        break
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
        FileSystemUtil.moveFile(`${ctx.cacheDir}/${object.item.name}`, record.path, 0).catch((err: Error) => {
          AppLogger.error(TAG, `restoreTransfers move failed: ${err}`)
        })
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
    if (!record || record.tid.length === 0) {
      AppLogger.warn(TAG, `restoreDownloadAndResume: no tid for id=${object.id}, re-enqueue with begins=${partialBytes}`)
      this.downloadObjects.deleteDataByItem(object)
      TransferDatabase.deleteDownload(object.id)
      this.enqueueDownloadTask(context, object.item, object.path, partialBytes > 0 ? partialBytes : 0)
      return
    }

    const fileModel = this.buildDownloadFileModel(context, object.item, object.path, object.url, object)
    requestDownload.restoreTask(object.id, context, record.tid, fileModel, true).then((ok) => {
      if (!ok) {
        AppLogger.warn(TAG, `restoreTask failed, fall back to re-enqueue with begins=${partialBytes}, id=${object.id}`)
        this.downloadObjects.deleteDataByItem(object)
        TransferDatabase.deleteDownload(object.id)
        this.enqueueDownloadTask(context, object.item, object.path, partialBytes > 0 ? partialBytes : 0)
      } else {
        this.downloadingCount++
      }
    })
  }

  private buildDownloadFileModel(context: common.UIAbilityContext, item: ObjectInfo,
                                  filePath: string, url: string, object: TransportObject): FileModel {
    let isCounted = true
    let lastPersistAt = 0
    let tidPersisted = ''
    return new FileModel(item.id, filePath, url, undefined, (trans, state) => {
      object.update(trans, state)
      if (state == FileModelState.COMPLETED) {
        FileSystemUtil.moveFile(`${context.cacheDir}/${object.item.name}`, filePath, 0).catch((err: Error) => {
          AppLogger.error(TAG, `err: ${err}`)
        })
      }
      if (isCounted && (state == FileModelState.COMPLETED || state == FileModelState.FAILED)) {
        this.downloadingCount--
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
        this.downloadObjects.pushData(object)
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
      }
    })
  }

  private attachDownloadFileModel(context: common.UIAbilityContext, item: ObjectInfo,
                                   filePath: string, url: string, object: TransportObject,
                                   begins: number = 0): void {
    const fileModel = this.buildDownloadFileModel(context, item, filePath, url, object)
    requestDownload.downloadFileBackground(fileModel, context, begins)
  }

  itemDownload(index: number, item: ObjectInfo) {
    try {
      const context = this.getAbilityContext();
      if (!context) {
        showToast($r('app.string.get_context_failed'));
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
    const conflictNames = uris
      .map(uri => { try { return uploadManager.extractFileName(uri); } catch { return ''; } })
      .filter(name => name.length > 0 && existingNames.has(name));

    if (conflictNames.length === 0) {
      this.uploadingCount += uris.length;
      uploadManager.enqueue(uris, this.currentPath, false, context, this.uploadObjects, onDirChanged, onTaskEnd);
      return;
    }

    showCloudActionDialog(this.getUIContext(), {
      title: $r('app.string.upload_conflict_title'),
      message: conflictNames.join('\n'),
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
