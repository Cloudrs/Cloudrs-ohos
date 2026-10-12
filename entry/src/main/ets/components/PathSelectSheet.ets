import {
  DividerShowType, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial
} from "@kit.UIDesignKit";
import Constant from "../model/Constant";
import { EmptyState } from "./EmptyState";
import { TitleControlButton } from "./TitleControlButton";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudMaterial } from "../model/CloudMaterial";
import { DirectoryInfo, DirFileInfo, ObjectInfo } from "../model/net/ApiTypes";
import { CloudApi } from "../model/net/CloudApi";
import { showToast, showToastTips, ToastType } from "../utils/ToastUtil";
import { ApiErrorUtil, NETWORK_ERROR_MESSAGE } from "../utils/ApiErrorUtil";
import { FILE_ICON_THEME_TILE, FileIcons } from "../utils/FileIcons";

const TAG: string = 'PathSelectSheet'

@Component
export struct PathSelectSheet {
  @Prop title: ResourceStr
  @Prop filterDirId: string
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.FILE_ICON_THEME) fileIconTheme: string = FILE_ICON_THEME_TILE
  @State currentPath: string = ''
  // 整页转圈 / 失败只用于首次拉根目录；展开子目录时只在 loadingPath 那一行的箭头位置转小圈，列表不动
  @State isLoading: boolean = false
  @State loadFailed: boolean = false
  @State loadingPath: string = ''
  // 紧挨在选中行上面的那一行：它的分隔线会贴着选中块的顶边，不画
  @State pathAboveSelected: string = ''
  onClose?: (isFinished: boolean, path?: string) => void

  private scroller: Scroller = new Scroller()
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
    if (this.loadingPath === path) {
      return
    }
    this.currentPath = path
    this.refreshPathAboveSelected()
    // 根目录还没拉到时整页转圈；之后展开子目录只在那一行转小圈，整页换成转圈会闪一下并丢掉滚动位置
    const fullPage = !this.allDirs.has('/')
    if (fullPage) {
      this.isLoading = true
      this.loadFailed = false
    } else {
      this.loadingPath = path
    }
    CloudApi.getFilesInfo(path, {
      onSuccess: (data: DirectoryInfo) => {
        let dirs = new DirFileInfo(data.parent, data.objects, data.policy).dirObjects
        this.putDirs(path, dirs.filter(item => item.id != this.filterDirId))
        this.putPathShow(path, true)
        this.isLoading = false
        this.clearLoadingPath(path)
        this.refreshPathAboveSelected()
      },
      onFailure: (msg) => {
        this.clearLoadingPath(path)
        if (fullPage) {
          this.isLoading = false
          this.loadFailed = true
        }
        if (ApiErrorUtil.isNetworkMessage(msg)) {
          showToast(NETWORK_ERROR_MESSAGE)
        } else {
          showToastTips($r('app.string.get_failed'), ToastType.Error)
        }
      }
    })
  }

  private clearLoadingPath(path: string): void {
    if (this.loadingPath === path) {
      this.loadingPath = ''
    }
  }

  private isSelected(item: ObjectInfo): boolean {
    return this.currentPath === CloudApi.getTotalPath(item)
  }

  /** 选中行自己和它上面那一行都不画分隔线，选中块上下不压线 */
  private showsDivider(item: ObjectInfo): boolean {
    const path = CloudApi.getTotalPath(item)
    return path !== this.currentPath && path !== this.pathAboveSelected
  }

  // 选中或展开 / 收起后，按当前可见行的显示顺序重新找出选中行的上一行
  private refreshPathAboveSelected(): void {
    const order: string[] = []
    this.collectVisiblePaths('/', order)
    const index = order.indexOf(this.currentPath)
    this.pathAboveSelected = index > 0 ? order[index - 1] : ''
  }

  private collectVisiblePaths(parent: string, out: string[]): void {
    this.getDirs(parent).forEach((dir: ObjectInfo) => {
      const path = CloudApi.getTotalPath(dir)
      out.push(path)
      if (this.pathShow.get(path)) {
        this.collectVisiblePaths(path, out)
      }
    })
  }

  aboutToAppear(): void {
    console.debug(TAG, 'filterDirId: ' + this.filterDirId)
    this.getFileList('/')
  }

  aboutToDisappear(): void {

  }

  // 头部放进 HdsNavigation 标题栏：× / ✓ 用标题栏按钮，才在沉浸光感生效范围内（半模态的内容区挂材质无效）。
  // 半模态里用官方的 MODAL 标题栏样式（MINI 是整页用的，会多让出一截状态栏高度），
  // 标题栏设为组件级安全区，目录自动避让到标题栏下方
  build() {
    HdsNavigation() {
      Column() {
        this.pathContent()
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MODAL)
    .titleBar({
      content: {
        title: {
          mainTitle: ' '
        },
        stackBuilder: () => {
          this.titleStack()
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
        // 标题是空占位，两态都要给标题色，否则开了滚动效果 HDS 会按缺省推状态栏深浅
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      enableComponentSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .backgroundColor(CloudMaterial.materialSurface(CloudThemeToken.background))
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
          plain: true,
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
          description: '当前空间暂时没有可展开的目录。',
          plain: true
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ scroller: this.scroller }) {
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

  // 标题栏：× 取消、✓ 确认用标题栏按钮（同文件页搜索 / 排序键、二级页返回键），中间主标题 + 当前目标
  @Builder titleStack() {
    Row({ space: CloudThemeToken.spacingSection }) {
      TitleControlButton({
        icon: $r('app.media.ic_window_close'),
        label: '取消',
        inTitleBar: true,
        onAction: () => this.onClose?.(false)
      })

      Column({ space: CloudThemeToken.pathSheetTitleGap }) {
        Text($r('app.string.select_path'))
          .fontSize(CloudThemeToken.textSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
        Row({ space: CloudThemeToken.pathSheetTitleGap }) {
          Text(this.title ?? '')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
          Text(this.currentPath)
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .ellipsisMode(EllipsisMode.START)
            .flexShrink(1)
        }
        .justifyContent(FlexAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      TitleControlButton({
        icon: $r('app.media.ic_check'),
        label: '确认',
        inTitleBar: true,
        onAction: () => this.onClose?.(true, this.currentPath)
      })
    }
    .width('100%')
    .height('100%')
    // stackBuilder 从标题栏左缘排起，左右边距在这里给
    .padding({ left: CloudThemeToken.pagePadding, right: CloudThemeToken.pagePadding })
    .alignItems(VerticalAlign.Center)
  }

  @Builder dirItem(item: ObjectInfo) {
    Column() {
      // 外层只负责左右内缩：选中块是内缩的圆角块（width 100% 加 margin 会溢出，用外层 padding + layoutWeight）
      Row() {
        Row({ space: CloudThemeToken.pathItemGap }) {
          Image(FileIcons.folderIcon(this.fileIconTheme))
            .width(CloudThemeToken.pathFolderIconSize)
            .height(CloudThemeToken.pathFolderIconSize)
            .draggable(false)

          Row({ space: CloudThemeToken.pathItemNameGap }) {
            Text(item.name)
              .fontSize(CloudThemeToken.pathSheetConfirmTextSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isSelected(item) ? CloudThemeToken.primary : CloudThemeToken.textPrimary)
              .wordBreak(WordBreak.BREAK_ALL)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .height(CloudThemeToken.pathLabelHeight)
              .layoutWeight(1)

            if (this.loadingPath === CloudApi.getTotalPath(item)) {
              LoadingProgress()
                .width(CloudThemeToken.pathChevronWidth)
                .height(CloudThemeToken.pathRowLoadingSize)
                .color(CloudThemeToken.primary)
            } else {
              Image(this.getPathShow(item) ? this.downIcon : this.rightIcon)
                .width(CloudThemeToken.pathChevronWidth)
                .height(CloudThemeToken.pathChevronHeight)
                .padding({
                  left: this.getPathShow(item) ? CloudThemeToken.zero : CloudThemeToken.pathChevronCollapsedPadding,
                  right: this.getPathShow(item) ? CloudThemeToken.zero : CloudThemeToken.pathChevronCollapsedPadding
                })
                .fillColor(this.isSelected(item) ? CloudThemeToken.primary : CloudThemeToken.textSecondary)
                .draggable(false)
            }
          }
          .height(CloudThemeToken.pathInnerRowHeight)
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Start)
          .outline({ width: { bottom: this.showsDivider(item) ? CloudThemeToken.lineWidth : CloudThemeToken.zero } })
          .outlineColor(CloudThemeToken.line)
        }
        .layoutWeight(1)
        .height(CloudThemeToken.pathRowHeight)
        .padding({
          left: this.getPathPadding(CloudApi.getTotalPath(item)) - CloudThemeToken.pathRowInset,
          right: CloudThemeToken.pathItemBasePadding - CloudThemeToken.pathRowInset
        })
        .borderRadius(CloudThemeToken.pathRowRadius)
        .clip(true)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
        // 未选中行透明，让位给 sheet 材质；选中行是半透明主色浅染，不用 primarySoft 实色块盖住材质
        .backgroundColor(this.isSelected(item) ? CloudThemeToken.selectedTint : CloudThemeToken.transparent)
        .onClick(() => {
          this.currentPath = CloudApi.getTotalPath(item)
          let isShow = this.getPathShow(item)
          if (isShow === undefined) {
            this.getFileList(this.currentPath)
          } else {
            this.putPathShow(this.currentPath, !isShow)
          }
          this.refreshPathAboveSelected()
        })
      }
      .width('100%')
      .padding({ left: CloudThemeToken.pathRowInset, right: CloudThemeToken.pathRowInset })

      if (this.getPathShow(item)) {
        ForEach(this.getDirs(CloudApi.getTotalPath(item)), (item: ObjectInfo, index) => {
          this.dirItem(item)
        }, (item: ObjectInfo, index) => item.id + index)
      }
    }
    .width('100%')
  }
}
