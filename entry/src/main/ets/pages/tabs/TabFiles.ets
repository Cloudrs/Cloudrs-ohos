import { DirectoryInfo, DirFileInfo, ObjectDetail, ObjectInfo, Policy } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import LazyDataSource from "../../utils/LazyDataSource";
import { TabFilesTitle } from "../../components/TabFilesTitle";
import { CloudApi } from "../../model/net/CloudApi";
import { showToast, showToastTips, ToastType } from "../../utils/ToastUtil";
import { image } from "@kit.ImageKit";
import { http } from '@kit.NetworkKit';
import { ObjectItem } from "../../components/ObjectItem";
import { TabFilesHeader } from "../../components/TabFilesHeader";
import { HMRouterMgr } from "@hadss/hmrouter";
import { ImagePreview } from "../../model/Params";
import { ExitLifecycle } from "../../lifecycle/ExitLifecycle";
import { FileMenuType, MoreMenuType, ShowType, SortType } from "../../model/MenuModel";
import { filePreview } from "@kit.PreviewKit";
import { DetailData } from "../../model/DetailData";
import { DetailSheet } from "../../components/DetailSheet";
import { CommonUtil, FileType } from "../../utils/CommonUtil";
import { PathSelectSheet } from "../../components/PathSelectSheet";
import { ObjectCopy, ObjectMove, ObjectSrc } from "../../model/net/ObjectParam";
import { common } from "@kit.AbilityKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { picker } from '@kit.CoreFileKit';
import { TransportObject } from "../../model/TransportObject";
import { requestDownload } from "../../utils/RequestDownload";
import { FileModel, FileModelState } from "../../model/FileModel";
import { SelectFileSheet } from '../../components/SelectFileSheet';
import { uploadManager } from '../../utils/UploadManager';
import { CloudThemeToken } from "../../model/CloudTheme";
import { EmptyState } from "../../components/EmptyState";
import { FileSystemUtil } from "../../utils/FileSystemUtil";
import { showCloudActionDialog, showCloudConfirmDialog } from "../../utils/CloudDialogUtil";

const TAG = 'TabFiles';

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

enum FileSheetMode {
  NONE = 'none',
  SELECT_FILE = 'selectFile',
  INPUT = 'input'
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
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.CURRENT_SHOW_TYPE) showType: ShowType = ShowType.SHOW_ICON
  @StorageProp(Constant.CURRENT_SORT_TYPE) sortType: SortType = SortType.SORT_BY_NAME
  @StorageProp(Constant.CURRENT_SORT_TYPE_RESERVE) sortTypeReverse: Map<SortType, boolean> = new Map([])
  @State policy: Policy|null = null
  @State isRoot: boolean = true
  @State mainTitle: string|Resource = $r('app.string.files_main_title')
  @State subTitle: string|Resource = $r('app.string.files_sub_title')
  @Provide thumbImage: Map<string, PixelMap> = new Map()
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
  @State showFileSheet: boolean = false
  @State fileSheetMode: FileSheetMode = FileSheetMode.NONE
  @State filePageState: FilePageState = FilePageState.IDLE
  @State searchKeyword: string = ''
  @State inputMode: FileInputMode = FileInputMode.NONE
  @State inputTitle: string|Resource = ''
  @State inputPlaceholder: string|Resource = ''
  @State inputValue: string = ''
  @State gridWidth: number = 0
  @State isHeaderGlassActive: boolean = false
  private inputRenameIndex: number = -1
  private inputRenameItem?: ObjectInfo = undefined
  private inputNewPath: string = '/'
  private inputNewIsDir: boolean = true

  setThumbData(id: string, pixMap: PixelMap) {
    const updated: Map<string, PixelMap> = new Map(this.thumbImage);
    updated.set(id, pixMap);
    this.thumbImage = updated;
  }

  getThumbData(id: string): PixelMap|undefined {
    if (this.thumbImage.has(id)) {
      return this.thumbImage.get(id)
    }
    return undefined
  }

  isSortTypeReverse(type: SortType): boolean {
    if (this.sortTypeReverse.has(type)) {
      return this.sortTypeReverse.get(type)!
    }
    return false
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
    this.isGridPadding = this.getFolderPaddingCount() > 0
    this.dirDataSource.notifyDataReload()
    this.fileDataSource.notifyDataReload()
  }

  getGridColumns(): number {
    if (this.showType !== ShowType.SHOW_ICON) {
      return CloudThemeToken.singleColumnMaxCount
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

  updateHeaderGlassState(): void {
    const scrollOffset = this.scrollerForList.currentOffset().yOffset
    const active = scrollOffset > CloudThemeToken.filesHeaderGlassThreshold
    if (this.isHeaderGlassActive !== active) {
      this.isHeaderGlassActive = active
    }
  }

  getTopInset(): number {
    return CloudThemeToken.getSafeTopInset(this.topRectHeight)
  }

  getHeaderContentHeight(): number {
    return this.isHeaderGlassActive ? CloudThemeToken.iconButtonSize : CloudThemeToken.cardHeight2xl
  }

  getHeaderContainerHeight(): number {
    return this.getTopInset() + CloudThemeToken.pageTopPadding + this.getHeaderContentHeight()
  }

  getExpandedHeaderContainerHeight(): number {
    return this.getTopInset() + CloudThemeToken.pageTopPadding + CloudThemeToken.cardHeight2xl
  }

  getGridTopPadding(): number {
    return this.getHeaderContainerHeight() + CloudThemeToken.pageTopPadding
  }

  getHeaderTopPadding(): number {
    const baseTopPadding = this.getTopInset() + CloudThemeToken.pageTopPadding
    if (!this.isHeaderGlassActive) {
      return baseTopPadding
    }
    return Math.max(CloudThemeToken.zero, baseTopPadding - CloudThemeToken.filesHeaderCollapsedContentLift)
  }

  getHeaderBottomPadding(): number {
    return this.isHeaderGlassActive ? CloudThemeToken.filesHeaderCollapsedContentLift : CloudThemeToken.zero
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
    this.fileDataSource.onDataGet = (index: number, item: ObjectInfo) => {
      //console.debug(TAG, `onDataGet: index:${index}`)
      this.getThumbFile(index, item)
    }
    (HMRouterMgr.getCurrentLifecycleOwner()?.getLifecycle() as ExitLifecycle).onBackPressedCallback = () => {
      return this.onBackPressedCallback()
    }
    this.getFileList(true, '/')
  }

  async getThumbFile(index: number, item: ObjectInfo) {
    if (item.thumb && !this.getThumbData(item.id)) {
      CloudApi.getThumb(item.id, {
        onSuccess: async (url: string) => {
          const req = http.createHttp();
          try {
            const resp = await req.request(url, {
              method: http.RequestMethod.GET,
              expectDataType: http.HttpDataType.ARRAY_BUFFER,
            });
            if (resp.responseCode === Constant.HTTP_STATUS_OK) {
              const imageSource = image.createImageSource(resp.result as ArrayBuffer);
              const pixMap = await imageSource.createPixelMap();
              imageSource.release();
              this.setThumbData(item.id, pixMap);
            }
          } catch (err) {
            console.error(TAG, `Get thumb failed: ${(err as Error)?.message ?? err}`)
          } finally {
            req.destroy();
          }
        },
        onFailure: (msg) => {
          console.error(TAG, `Get thumb failed: ${msg}`)
        }
      })
    }
  }

  async getFileList(isRefresh: boolean, path: string) {
    const isSamePath = path === this.currentPath
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
          this.thumbImage.clear()
          this.isHeaderGlassActive = false
          this.scrollerForList.scrollEdge(Edge.Start)
        }
      },
      onSuccess: (data: DirectoryInfo) => {
        if (!shouldKeepContent) {
          this.searchKeyword = ''
        }
        this.subTitle = data.policy.name
        this.objectsInfo = new DirFileInfo(data.parent, data.objects, data.policy)
        this.objectsInfo.sortObjects(this.sortType, this.isSortTypeReverse(this.sortType))
        this.applyVisibleObjects()
        this.isRefreshing = false
        this.filePageState = FilePageState.IDLE
      },
      onFailure: (msg) => {
        showToastTips($r('app.string.get_failed'), ToastType.Error)
        //决定是否重新登录
        this.isRefreshing = false
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
          },
          onFailure: (msg) => {
            console.error(TAG, 'copy failed, msg: ' + msg)
            showToast($r('app.string.copy_failed'))
          }
        })
      } else if (this.objectSelect.type == FileMenuType.MOVE) {
        let param: ObjectMove = new ObjectMove(this.currentPath, src, dst)
        CloudApi.moveObjects(param, {
          onSuccess: (data) => {
            this.dataSourceDelete()
            showToast($r('app.string.move_success'))
          },
          onFailure: (msg) => {
            console.error(TAG, 'move failed, msg: ' + msg)
            showToast($r('app.string.move_failed'))
          }
        })
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.Top }) {
        Stack({alignContent: Alignment.BottomEnd}) {
          Refresh({refreshing: $$this.isRefreshing}) {
            this.objectGrid()
          }
          .width('100%')
          .height('100%')
          .refreshOffset(CloudThemeToken.refreshOffset)
          .pullToRefresh(true)
          .onRefreshing(async () => {
            await this.getFileList(true, this.currentPath);
          })

          if (this.isFilePageLoading()) {
            this.loadingState()
          }

          if (this.isRefreshing && !this.isFilePageLoading()) {
            this.refreshingHint()
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
          .margin({ right: CloudThemeToken.spacingPage, bottom: this.tabBarHeight + CloudThemeToken.spacingPage })
          .onClick(() => { this.openSelectFileSheet() })
        }
        .width('100%')
        .height('100%')

        this.filesHeaderOverlay()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.background)

      if (this.showObjectDetail) {
        this.detailOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showFileSheet, this.fileSheetBuilder(), {
      detents: [SheetSize.FIT_CONTENT],
      showClose: false,
      backgroundColor: CloudThemeToken.background,
      onDisappear: () => {
        this.showFileSheet = false
        this.resetFileSheetState()
      }
    })
  }

  @Builder filesHeaderOverlay() {
    Column({ space: CloudThemeToken.spacingCard }) {
      TabFilesHeader({
        isRoot: this.isRoot,
        searchKeyword: this.searchKeyword,
        downloadObjects: this.downloadObjects,
        downloadingCount: this.downloadingCount,
        uploadObjects: this.uploadObjects,
        uploadingCount: this.uploadingCount,
        onBackClick: (async () => {
          await this.getFileList(true, CommonUtil.getDirectoryPath(this.currentPath))
        }),
        onSearchChange: () => {
          this.applyVisibleObjects()
        }
      })
      if (!this.isHeaderGlassActive) {
        TabFilesTitle({
          mainTitle: this.mainTitle,
          subTitle: this.subTitle,
          onMoreClick: (type: MoreMenuType, isReverse?: boolean) => {
            this.onMoreClick(type, isReverse)
          }
        })
      }
    }
    .width('100%')
    .height(this.getHeaderContainerHeight())
    .padding({
      top: this.getHeaderTopPadding(),
      bottom: this.getHeaderBottomPadding()
    })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.isHeaderGlassActive ? CloudThemeToken.headerGlass : CloudThemeToken.transparent)
    .backgroundBlurStyle(this.isHeaderGlassActive ? CloudThemeToken.filesHeaderGlassBlurStyle : BlurStyle.NONE)
    .zIndex(CloudThemeToken.filesHeaderZIndex)
    .animation({ duration: CloudThemeToken.filesHeaderTransitionDuration, curve: Curve.EaseOut })
  }

  @Builder fileSheetBuilder() {
    if (this.fileSheetMode === FileSheetMode.SELECT_FILE) {
      this.selectFileSheetBuilder()
    } else if (this.fileSheetMode === FileSheetMode.INPUT) {
      this.inputSheetBuilder()
    }
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

  @Builder refreshingHint() {
    Column() {
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
    }
    .width('100%')
    .height('100%')
    .padding({ top: CloudThemeToken.spacingXl })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
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

        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_xmark'))
            .width(CloudThemeToken.iconMd)
            .height(CloudThemeToken.iconMd)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
        .width(CloudThemeToken.iconBoxSm)
        .height(CloudThemeToken.iconBoxSm)
        .borderRadius(CloudThemeToken.controlRadius)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        .onClick(() => {
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
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
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
      LazyForEach(this.dirDataSource, (item: ObjectInfo, index: number) => {
        GridItem() {
          ObjectItem({ index, item, showType: this.showType,
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
            onMenuClick : (async (item, type) => {
              await this.onMenuClick(index, item, type)
            })
          })
        }
        .onClick(async () => {
          this.onItemClick(item)
        })
      }, (item: ObjectInfo, index: number) => item.id)
    }
    .cachedCount(CloudThemeToken.fileGridCachedCount)
    .maxCount(this.getGridColumns())
    .padding({
      left: CloudThemeToken.spacingCard,
      right: CloudThemeToken.spacingCard,
      top: this.getGridTopPadding(),
      bottom: this.tabBarHeight + CloudThemeToken.tabContentBottomGap
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
          Button() {
            Image($r('app.media.ic_xmark'))
              .width(CloudThemeToken.iconLg)
              .height(CloudThemeToken.iconLg)
              .fillColor(CloudThemeToken.textSecondary)
          }
            .width(CloudThemeToken.iconBoxMd)
            .height(CloudThemeToken.iconBoxMd)
            .borderRadius(CloudThemeToken.controlRadiusRoundLg)
            .backgroundColor(CloudThemeToken.surfaceSubtle)
            .onClick(() => {
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

  @Builder selectFileSheetBuilder() {
    SelectFileSheet({
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
    if (item.type == Constant.OBJECT_DIR_TYPE) {
      await this.getFileList(true, CloudApi.getTotalPath(item))
    }
    else {
      let fileType = CommonUtil.getFileType(item.name)
      let fileExtension = CommonUtil.getFileExtention(item.name)
      if (fileType == FileType.IMAGE) {
        HMRouterMgr.push({pageUrl: Constant.IAMGE_PREVIEW_PAGE, param: new ImagePreview(item.name, item.id, fileExtension)})
      } else {
        //filePreview.openPreview(getContext(), {title: item.name, uri: '', mimeType: ''})
        showToast('该类型不支持预览')
      }
    }
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
        this.objectSelect.copyMoveObjects.splice(0, this.copyMoveObjects.length)
        this.objectSelect.copyMoveObjects.push(item)
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          this.objectSelect.selectPathId = item.id
        }
        else {
          this.objectSelect.selectPathId = ''
        }
        this.openPathSelectSheet()
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

  itemDetail(item: ObjectInfo) {
    CloudApi.getObjectDetail(item.id, item.type == Constant.OBJECT_DIR_TYPE, {
      onSuccess: (data) => {
        this.detailData = new DetailData(item.name, item.type == Constant.OBJECT_DIR_TYPE, data)
        this.overLap = false
        this.showObjectDetail = true
      },
      onFailure: (msg) => {
        console.error(TAG, '获取详细信息失败 msg: ' + msg)
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
    this.fileSheetMode = FileSheetMode.SELECT_FILE
    this.showFileSheet = true
  }

  private openInputSheet(): void {
    this.fileSheetMode = FileSheetMode.INPUT
    this.showFileSheet = true
  }

  private closeFileSheet(): void {
    this.showFileSheet = false
  }

  private closeInputSheet(): void {
    this.closeFileSheet()
  }

  private openPathSelectSheet(): void {
    this.showPathSelect = true
  }

  private closePathSelectSheet(): void {
    this.showPathSelect = false
  }

  private resetFileSheetState(): void {
    this.fileSheetMode = FileSheetMode.NONE
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
        console.error(TAG, '重命名失败 msg: ' + msg)
        showToast($r('app.string.rename_failed'))
      }
    })
  }

  private confirmNewObject(content: string): void {
    CloudApi.newObject(`${this.inputNewPath}/${content}`, this.inputNewIsDir, {
      onSuccess: (data) => {
        this.closeInputSheet()
        this.getFileList(true, this.currentPath)
        showToast(`新建${content}成功`)
      },
      onFailure: (msg) => {
        console.error(TAG, '新建文件/文件夹失败 msg: ' + msg)
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
            console.error(TAG, '删除失败 msg: ' + msg)
            showToast($r('app.string.delete_failed'))
          }
        })
      }
    })
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
        let filePath = FileSystemUtil.getPathFromUri(documentSaveResult[Constant.FIRST_ARRAY_INDEX] + '/' + item.name);
        console.debug(TAG, 'documentViewPicker.save to file succeed and uris are:' + filePath);
        CloudApi.getDownloadUri(item.id, {
          onSuccess: (data) => {
            let url = (data.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
              data.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) ? data : CloudApi.getBaseURL() + data
            let object: TransportObject = new TransportObject(item, filePath, url)
            this.downloadObjects.pushData(object)
            this.downloadingCount++

            let fileModel: FileModel = new FileModel(item.id, filePath, url, undefined, (trans, state) => {
              object.update(trans, state)
              if (state == FileModelState.COMPLETED) {
                console.debug(TAG, `${context.cacheDir}/${object.item.name} -> ` + filePath)
                FileSystemUtil.moveFile(`${context.cacheDir}/${object.item.name}`, filePath, 0).then(() => {
                  console.debug(TAG, 'move to ' + filePath)
                }).catch((err: Error) => {
                  console.error(TAG, `err: ${err}`)
                })
                this.downloadingCount--
              }
            })

            // 创建下载任务
            requestDownload.downloadFileBackground(fileModel, context)
          },
          onFailure: (msg) => {
            console.error(TAG, 'get download uri failed, msg: ' + msg)
          }
        })
      }).catch((err: BusinessError) => {
        console.error(TAG, `Invoke documentViewPicker.save failed, code is ${err.code}, message is ${err.message}`);
      })
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      console.error(TAG, `Error code: ${err.code}, message: ${err.message}`);
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
