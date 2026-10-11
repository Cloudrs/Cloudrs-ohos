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

  private scroller: Scroller = new Scroller()
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
        if (ApiErrorUtil.isNetworkMessage(msg)) {
          showToast(NETWORK_ERROR_MESSAGE)
        } else {
          showToastTips($r('app.string.get_failed'), ToastType.Error)
        }
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
      // 未选中行让位给 sheet 材质（多行不逐行挂材质，避免材质叠材质发浑）；选中行保留高亮
      .backgroundColor(this.currentPath === CloudApi.getTotalPath(item)
        ? CloudThemeToken.primarySoft : CloudMaterial.materialSurface(CloudThemeToken.background))
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
