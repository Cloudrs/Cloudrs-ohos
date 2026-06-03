import Constant from "../model/Constant";
import { EmptyState } from "./EmptyState";
import { CloudThemeToken } from "../model/CloudTheme";
import { DirectoryInfo, DirFileInfo, ObjectInfo } from "../model/net/ApiTypes";
import { CloudApi } from "../model/net/CloudApi";
import { showToastTips, ToastType } from "../utils/ToastUtil";
import { CloudIconButton } from "./CloudIconButton";

const TAG: string = 'PathSelectSheet'

@Component
export struct PathSelectSheet {
  @Prop title: ResourceStr
  @Prop filterDirId: string
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State currentPath: string = ''
  @State isLoading: boolean = false
  @State loadFailed: boolean = false
  onClose?: (isFinished: boolean, path?: string) => void

  private normalIcon: Resource = $r('app.media.ic_folder_fill');
  private downIcon: Resource = $r('app.media.ic_chevron_down');
  private rightIcon: Resource = $r('app.media.ic_chevron_right');
  @State allDirs: Map<string, ObjectInfo[]> = new Map()
  @State pathShow: Map<string, boolean> = new Map()

  getPathPadding(path: string) {
    if (path == '/') {
      return CloudThemeToken.pathItemBasePadding
    }

    let num = path.split('/').length-1
    return CloudThemeToken.pathItemBasePadding + num * CloudThemeToken.pathItemDepthPadding
  }

  putDirs(path: string, dirs: ObjectInfo[]) {
    this.allDirs.set(path, dirs)
  }

  getDirs(path: string): ObjectInfo[] {
    if (this.allDirs.has(path)) {
      return this.allDirs.get(path) ?? []
    }
    return []
  }

  putPathShow(path: string, show: boolean) {
    this.pathShow.set(path, show)
  }

  getPathShow(item: ObjectInfo) {
    let path = CloudApi.getTotalPath(item)
    return this.pathShow.get(path)
  }

  async getFileList(path: string) {
    this.currentPath = path
    this.isLoading = true
    this.loadFailed = false
    CloudApi.getFilesInfo(path, {
      onSuccess: (data: DirectoryInfo) => {
        let dirs = new DirFileInfo(data.parent, data.objects, data.policy).dirObjects
        this.putDirs(path, dirs.filter(item => item.id != this.filterDirId))
        this.putPathShow(this.currentPath, true)
        this.isLoading = false
      },
      onFailure: (msg) => {
        this.isLoading = false
        this.loadFailed = true
        showToastTips($r('app.string.get_failed'), ToastType.Error)
      }
    })
  }

  aboutToAppear(): void {
    console.debug(TAG, 'filterDirId: ' + this.filterDirId)
    this.getFileList('/')
  }

  aboutToDisappear(): void {

  }

  build() {
    Column({ space: CloudThemeToken.pathSheetGap }) {
      this.header()

      this.pathContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
    .padding({
      top: CloudThemeToken.pathSheetTopPadding,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
    .justifyContent(FlexAlign.Start)
  }

  @Builder pathContent() {
    if (this.isLoading) {
      Column({ space: CloudThemeToken.spacingSection }) {
        LoadingProgress()
          .width(CloudThemeToken.iconBoxSm)
          .height(CloudThemeToken.iconBoxSm)
          .color(CloudThemeToken.primary)
        Text('正在加载文件夹')
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.loadFailed) {
      Column() {
        EmptyState({
          icon: $r('app.media.ic_icloud_slash_fill'),
          title: '文件夹加载失败',
          description: '请检查网络后重试。',
          actionText: '重新加载',
          onAction: () => {
            this.getFileList(this.currentPath.length > 0 ? this.currentPath : '/')
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.getDirs('/').length === 0) {
      Column() {
        EmptyState({
          icon: $r('app.media.ic_empty_folder'),
          title: '没有可选文件夹',
          description: '当前空间暂时没有可展开的目录。'
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        ForEach(this.getDirs('/'), (item: ObjectInfo, index) => {
          this.dirItem(item)
        })
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
  }

  @Builder header() {
    Column() {
      Row({ space: CloudThemeToken.pathSheetTitleGap }) {
        Text(this.title ?? '')
          .fontSize(CloudThemeToken.pathSheetTitleSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)

        Text(this.currentPath)
          .fontSize(CloudThemeToken.pathSheetTitleSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Row({ space: CloudThemeToken.pathSheetHeaderActionGap }) {
        CloudIconButton({
          icon: $r('app.media.ic_xmark_bold'),
          buttonSize: CloudThemeToken.smallIconButtonSize,
          iconSize: CloudThemeToken.sheetActionIconSize,
          buttonBackground: CloudThemeToken.surfaceSubtle,
          iconColor: CloudThemeToken.textSecondary,
          onAction: () => {
            if (this.onClose) {
              this.onClose(false)
            }
          }
        })

        Row() {
          Text($r('app.string.select_path'))
            .fontSize(CloudThemeToken.pathSheetConfirmTextSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
            .textAlign(TextAlign.Center)
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
            .layoutWeight(1)

          Text($r('app.string.finished'))
            .height(CloudThemeToken.sheetConfirmHeight)
            .fontSize(CloudThemeToken.pathSheetConfirmTextSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.primary)
            .padding(CloudThemeToken.pathSheetConfirmPadding)
            .onClick(() => {
              if (this.onClose) {
                this.onClose(true, this.currentPath)
              }
            })
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .padding({
        left: CloudThemeToken.pathSheetHeaderHorizontalPadding,
        right: CloudThemeToken.pathSheetHeaderHorizontalPadding
      })
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .justifyContent(FlexAlign.SpaceBetween)
    .height(CloudThemeToken.sheetHeaderHeight)
    .width('100%')
    .outline({width: {bottom: CloudThemeToken.strongLineWidth}})
    .outlineColor(CloudThemeToken.line)
  }

  @Builder dirItem(item: ObjectInfo) {
    Column() {
      Row({ space: CloudThemeToken.pathItemGap }) {
        Image(this.normalIcon)
          .width(CloudThemeToken.pathFolderIconSize)
          .height(CloudThemeToken.pathFolderIconSize)
          .fillColor(CloudThemeToken.primary)
          .draggable(false)

        Row({ space: CloudThemeToken.pathItemNameGap }) {
          Text(item.name)
            .fontSize(CloudThemeToken.pathSheetConfirmTextSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .height(CloudThemeToken.pathLabelHeight)
            .layoutWeight(1)

          Image(this.getPathShow(item) ? this.downIcon : this.rightIcon)
            .width(CloudThemeToken.pathChevronWidth)
            .height(CloudThemeToken.pathChevronHeight)
            .padding({
              left: this.getPathShow(item) ? CloudThemeToken.zero : CloudThemeToken.pathChevronCollapsedPadding,
              right: this.getPathShow(item) ? CloudThemeToken.zero : CloudThemeToken.pathChevronCollapsedPadding
            })
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
        .height(CloudThemeToken.pathInnerRowHeight)
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .outline({ width: { bottom: CloudThemeToken.strongLineWidth } })
        .outlineColor(CloudThemeToken.line)
      }
      .height(CloudThemeToken.pathRowHeight)
      .width('100%')
      .padding({
        left: this.getPathPadding(CloudApi.getTotalPath(item)),
        right: CloudThemeToken.pathItemBasePadding
      })
      .clip(true)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.currentPath === CloudApi.getTotalPath(item) ? CloudThemeToken.primarySoft : CloudThemeToken.background)
      .onClick(() => {
        this.currentPath = CloudApi.getTotalPath(item)
        let isShow = this.getPathShow(item)
        if (isShow === undefined) {
          this.getFileList(this.currentPath)
        } else {
          this.putPathShow(this.currentPath, !isShow)
        }
      })

      if (this.getPathShow(item)) {
        ForEach(this.getDirs(CloudApi.getTotalPath(item)), (item: ObjectInfo, index) => {
          this.dirItem(item)
        }, (item: ObjectInfo, index) => item.id + index)
      }
    }
    .width('100%')
  }
}
