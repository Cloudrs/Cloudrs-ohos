import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { ObjectItem } from "../components/ObjectItem";
import { FileMenuType, ShowType } from "../model/MenuModel";
import { ObjectInfo } from "../model/net/ApiTypes";
import { FileSearchParam, ImagePreview, PreviewFile, VideoPreview } from "../model/Params";
import { CommonUtil, FileType } from "../utils/CommonUtil";
import { CloudRouter } from "../utils/CloudRouter";
import { showToast } from "../utils/ToastUtil";
import { DividerShowType, HdsNavigation, HdsNavigationTitleMode, hdsEffect, hdsMaterial } from "@kit.UIDesignKit";

@Component
export struct FileSearchPage {
  routeParam?: FileSearchParam
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0
  @Provide thumbImage: Map<string, PixelMap> = new Map<string, PixelMap>()
  @Provide thumbSource: Map<string, string> = new Map<string, string>()
  @State searchKeyword: string = ''
  @State results: ObjectInfo[] = []
  private objects: ObjectInfo[] = []

  aboutToAppear(): void {
    this.objects = this.routeParam?.objects ?? []
    this.thumbImage = this.routeParam?.thumbImage ?? new Map<string, PixelMap>()
    this.thumbSource = this.routeParam?.thumbSource ?? new Map<string, string>()
    this.applySearch()
  }

  private getTopInset(): number {
    return CloudThemeToken.getSafeTopInset(this.topRectHeight)
  }

  private getTitleBarHeight(): number {
    return this.getTopInset() + CloudThemeToken.rowHeight5xl
  }

  private getShowType(): ShowType {
    return this.routeParam?.showType ?? ShowType.SHOW_LIST
  }

  private getResultDirs(): ObjectInfo[] {
    return this.results.filter((item: ObjectInfo) => item.type === Constant.OBJECT_DIR_TYPE)
  }

  private getResultFiles(): ObjectInfo[] {
    return this.results.filter((item: ObjectInfo) => item.type !== Constant.OBJECT_DIR_TYPE)
  }

  private getSearchFieldEffect(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
      .buildEffect()
  }

  private applySearch(): void {
    const keyword = this.searchKeyword.trim().toLowerCase()
    if (keyword.length === CloudThemeToken.zero) {
      this.results = []
      return
    }
    this.results = this.objects.filter((item: ObjectInfo) => item.name.toLowerCase().includes(keyword))
  }

  private dispatchOpenResult(item: ObjectInfo): void {
    if (this.routeParam?.onOpen) {
      CloudRouter.pop()
      this.routeParam.onOpen(item)
      return
    }
    this.openResult(item)
  }

  private dispatchMenuClick(item: ObjectInfo, type: FileMenuType): void {
    if (this.routeParam?.onMenuClick) {
      CloudRouter.pop()
      this.routeParam.onMenuClick(item, type)
      return
    }
    if (type === FileMenuType.PREVIEW || type === FileMenuType.DIR_ENTER) {
      this.openResult(item)
      return
    }
    showToast('请返回文件页操作')
  }

  private openResult(item: ObjectInfo): void {
    if (item.type === Constant.OBJECT_DIR_TYPE) {
      return
    }
    const fileType = CommonUtil.getFileType(item.name)
    const fileExtension = CommonUtil.getFileExtention(item.name)
    if (fileType === FileType.IMAGE) {
      CloudRouter.push(Constant.IAMGE_PREVIEW_PAGE, this.buildImagePreviewParam(item, fileExtension))
    } else if (fileType === FileType.VIDEO) {
      CloudRouter.push(Constant.VIDEO_PREVIEW_PAGE, new VideoPreview(item.name, item.id, fileExtension))
    } else {
      showToast('该类型不支持预览')
    }
  }

  private buildImagePreviewParam(item: ObjectInfo, fileExtension: string): ImagePreview {
    const images = this.results
      .filter((file: ObjectInfo) => file.type === Constant.OBJECT_FILE_TYPE &&
        CommonUtil.getFileType(file.name) === FileType.IMAGE)
      .map((file: ObjectInfo) => new PreviewFile(file.name, file.id, CommonUtil.getFileExtention(file.name)))
    const currentIndex = images.findIndex((file: PreviewFile) => file.fileId === item.id)
    return new ImagePreview(item.name, item.id, fileExtension, images, currentIndex >= 0 ? currentIndex : 0)
  }

  build() {
    HdsNavigation() {
      Column() {
        this.resultList()
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.getTitleBarHeight() + CloudThemeToken.spacingSection,
        bottom: this.bottomRectHeight + CloudThemeToken.spacingPage
      })
      .backgroundColor(CloudThemeToken.background)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: ' '
        },
        backIcon: {
          icon: $r('app.media.ic_back'),
          action: () => {
            CloudRouter.pop()
          }
        },
        stackBuilder: () => {
          this.searchTitleStack()
        },
        divider: {
          showType: DividerShowType.OFF
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: CloudThemeToken.transparent
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            },
            backIconStyle: {
              backgroundColor: CloudThemeToken.surfaceSubtle,
              iconColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder searchTitleStack() {
    Row() {
      Stack() {
        Row({ space: CloudThemeToken.spacingXs }) {
          Image($r('app.media.ic_search'))
            .width(CloudThemeToken.iconXl)
            .height(CloudThemeToken.iconXl)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)

          TextInput({ text: this.searchKeyword, placeholder: '搜索文件、文件夹' })
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontColor(CloudThemeToken.textPrimary)
            .placeholderColor(CloudThemeToken.textSecondary)
            .enterKeyType(EnterKeyType.Search)
            .backgroundColor(CloudThemeToken.transparent)
            .borderRadius(CloudThemeToken.inputInnerRadius)
            .height('100%')
            .layoutWeight(1)
            .padding({ left: CloudThemeToken.zero, right: CloudThemeToken.zero })
            .defaultFocus(true)
            .onChange((value: string) => {
              this.searchKeyword = value
              this.applySearch()
            })
        }
        .width('100%')
        .height('100%')
        .padding({
          left: CloudThemeToken.spacingCard,
          right: CloudThemeToken.spacingCard
        })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(CloudThemeToken.transparent)
      }
        .borderRadius(CloudThemeToken.controlRadiusRoundXl)
        .height(CloudThemeToken.rowHeightXl)
        .layoutWeight(1)
        .backgroundColor(CloudThemeToken.searchFieldBackground)
        .border({
          width: CloudThemeToken.lineWidth,
          color: CloudThemeToken.line
        })
        .shadow({
          radius: CloudThemeToken.refreshShadowRadius,
          color: CloudThemeToken.refreshShadow,
          offsetY: CloudThemeToken.refreshShadowOffsetY
        })
        .visualEffect(this.getSearchFieldEffect())
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.getSearchFieldLeftInset(),
      right: CloudThemeToken.filesTitleHorizontalPadding
    })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.End)
  }

  // 宽屏（PC/平板自由窗口）下 HDS 返回按钮更宽且贴近窗口边缘，
  // 预留宽度需要在手机基准上再加一段间隙，否则搜索框会顶到返回按钮。
  private getSearchFieldLeftInset(): number {
    const base = CloudThemeToken.filesTitleHorizontalPadding + CloudThemeToken.iconBoxXl
    return base + (CloudThemeToken.isWideWidth(this.windowWidthVp)
      ? CloudThemeToken.spacingPage : CloudThemeToken.spacingMd)
  }

  @Builder resultList() {
    if (this.results.length > CloudThemeToken.zero) {
      if (this.getShowType() === ShowType.SHOW_ICON) {
        Grid() {
          ForEach(this.getResultDirs(), (item: ObjectInfo, index: number) => {
            GridItem() {
              this.resultRow(item, index)
            }
          }, (item: ObjectInfo) => item.id)

          if (this.getResultDirs().length % 2 !== CloudThemeToken.zero) {
            GridItem() {
              Row()
                .width('100%')
                .height(CloudThemeToken.objectGridFolderHeight)
            }
          }

          ForEach(this.getResultFiles(), (item: ObjectInfo, index: number) => {
            GridItem() {
              this.resultRow(item, index)
            }
          }, (item: ObjectInfo) => item.id)
        }
        .width('100%')
        .height('100%')
        .columnsTemplate('1fr 1fr')
        .columnsGap(CloudThemeToken.spacingCard)
        .rowsGap(CloudThemeToken.spacingCard)
        .padding({
          left: CloudThemeToken.filesTitleHorizontalPadding,
          right: CloudThemeToken.filesTitleHorizontalPadding
        })
      } else {
        List({ space: CloudThemeToken.zero }) {
          ForEach(this.getResultDirs(), (item: ObjectInfo, index: number) => {
            ListItem() {
              this.resultRow(item, index)
            }
          }, (item: ObjectInfo) => item.id)

          ForEach(this.getResultFiles(), (item: ObjectInfo, index: number) => {
            ListItem() {
              this.resultRow(item, index)
            }
          }, (item: ObjectInfo) => item.id)
        }
        .width('100%')
        .height('100%')
        .cachedCount(CloudThemeToken.compactListCachedCount)
        .divider({
          strokeWidth: CloudThemeToken.lineWidth,
          color: CloudThemeToken.line,
          startMargin: CloudThemeToken.filesTitleHorizontalPadding + CloudThemeToken.objectListIconSize +
          CloudThemeToken.objectItemGap,
          endMargin: CloudThemeToken.filesTitleHorizontalPadding
        })
      }
    } else {
      Blank()
        .width('100%')
        .height('100%')
    }
  }

  @Builder resultRow(item: ObjectInfo, index: number) {
    ObjectItem({
      index: index,
      item: item,
      showType: this.getShowType(),
      onMenuClick: (menuItem: ObjectInfo, type: FileMenuType) => {
        this.dispatchMenuClick(menuItem, type)
      }
    })
    .onClick(() => {
      this.dispatchOpenResult(item)
    })
  }
}
