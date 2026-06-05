import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { ObjectInfo } from "../model/net/ApiTypes";
import { FileSearchParam, ImagePreview, PreviewFile, VideoPreview } from "../model/Params";
import { CommonUtil, FileType } from "../utils/CommonUtil";
import { CloudRouter } from "../utils/CloudRouter";
import { DateFormatUtil } from "../utils/DateFormatUtil";
import { showToast } from "../utils/ToastUtil";
import { DividerShowType, HdsNavigation, HdsNavigationTitleMode, hdsEffect, hdsMaterial } from "@kit.UIDesignKit";

@Component
export struct FileSearchPage {
  routeParam?: FileSearchParam
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @State searchKeyword: string = ''
  @State results: ObjectInfo[] = []
  private objects: ObjectInfo[] = []

  aboutToAppear(): void {
    this.objects = this.routeParam?.objects ?? []
    this.applySearch()
  }

  private getTopInset(): number {
    return CloudThemeToken.getSafeTopInset(this.topRectHeight)
  }

  private getTitleBarHeight(): number {
    return this.getTopInset() + CloudThemeToken.rowHeight5xl
  }

  private getSearchFieldEffect(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: CloudThemeToken.onPrimary,
          intensity: CloudThemeToken.hdsIconButtonLightIntensity * 0.72,
          height: CloudThemeToken.hdsIconButtonLightHeight,
          bloom: CloudThemeToken.hdsIconButtonLightBloom * 0.72
        }
      })
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

  private getResultIcon(item: ObjectInfo): Resource {
    if (item.type === Constant.OBJECT_DIR_TYPE) {
      return $r('app.media.ic_folder_fill')
    }
    return CommonUtil.getFileIconInfo(item.name).icon
  }

  private getResultMetaText(item: ObjectInfo): string {
    const dateText = DateFormatUtil.format(new Date(item.date), 'yyyy-MM-dd')
    if (item.type === Constant.OBJECT_DIR_TYPE) {
      return dateText
    }
    return `${dateText} · ${CommonUtil.formatBytes(item.size)}`
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
      .backgroundColor(CloudThemeToken.surface)
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
    .backgroundColor(CloudThemeToken.surface)
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
      left: CloudThemeToken.filesTitleHorizontalPadding + CloudThemeToken.iconBoxXl,
      right: CloudThemeToken.filesTitleHorizontalPadding
    })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.End)
  }

  @Builder resultList() {
    if (this.results.length > CloudThemeToken.zero) {
      List({ space: CloudThemeToken.zero }) {
        ForEach(this.results, (item: ObjectInfo) => {
          ListItem() {
            this.resultRow(item)
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
    } else {
      Blank()
        .width('100%')
        .height('100%')
    }
  }

  @Builder resultRow(item: ObjectInfo) {
    Row({ space: CloudThemeToken.objectItemGap }) {
      Image(this.getResultIcon(item))
        .width(CloudThemeToken.objectListIconSize)
        .height(CloudThemeToken.objectListIconSize)
        .draggable(false)

      Column({ space: CloudThemeToken.objectMetaGap }) {
        Text(item.name)
          .fontSize(CloudThemeToken.textSizeLargePlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.getResultMetaText(item))
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(CloudThemeToken.objectListRowHeight + CloudThemeToken.spacingSection)
    .padding({
      left: CloudThemeToken.filesTitleHorizontalPadding,
      right: CloudThemeToken.filesTitleHorizontalPadding
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CloudThemeToken.surface)
    .onClick(() => {
      this.openResult(item)
    })
  }
}
