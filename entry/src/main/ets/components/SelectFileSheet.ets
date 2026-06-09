import { photoAccessHelper } from "@kit.MediaLibraryKit"
import { BusinessError } from "@kit.BasicServicesKit"
import { common } from "@kit.AbilityKit"
import { picker } from "@kit.CoreFileKit"
import { CloudThemeToken } from "../model/CloudTheme"
import Constant from "../model/Constant"
import { showToastTips, ToastType } from "../utils/ToastUtil"
import AppLogger from "../utils/AppLogger"

const TAG: string = 'SelectFileSheet'

@Component
export struct SelectFileSheet {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @Prop extraBottomPadding: number = 0
  @State isPicking: boolean = false
  onSelectFinished?: (uris: string[]) => void
  onClose?: () => void

  build() {
    Column({ space: CloudThemeToken.uploadSourceSheetGap }) {
      Row() {
        Text($r('app.string.upload'))
          .fontSize(CloudThemeToken.uploadSourceTitleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)

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
        .onClick(() => {
          if (this.onClose) {
            this.onClose()
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: CloudThemeToken.uploadSourceListGap }) {
        this.uploadSourceItem(
          $r('app.media.ic_upload_file_modern'),
          $r('app.string.local_files'),
          '从文件管理选择文件',
          () => {
            this.selectFiles()
          })

        this.uploadSourceItem(
          $r('app.media.ic_upload_photo_modern'),
          $r('app.string.local_photos'),
          '从相册选择图片',
          () => {
            this.selectPhotos(false)
          })

        this.uploadSourceItem(
          $r('app.media.ic_upload_video_modern'),
          $r('app.string.local_videos'),
          '从相册选择视频',
          () => {
            this.selectPhotos(true)
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.uploadSourceSheetHorizontalPadding,
      right: CloudThemeToken.uploadSourceSheetHorizontalPadding,
      top: CloudThemeToken.uploadSourceSheetTopPadding,
      bottom: this.bottomRectHeight + this.extraBottomPadding + CloudThemeToken.uploadSourceSheetBottomPadding
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(CloudThemeToken.background)
    .zIndex(1)
  }

  @Builder uploadSourceItem(icon: Resource, title: ResourceStr, description: ResourceStr, onClick: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: CloudThemeToken.uploadSourceItemGap }) {
        Stack() {
          Image(icon)
            .width(CloudThemeToken.icon3xl)
            .height(CloudThemeToken.icon3xl)
            .draggable(false)
        }
        .width(CloudThemeToken.uploadSourceIconBoxSize)
        .height(CloudThemeToken.uploadSourceIconBoxSize)
        .borderRadius(CloudThemeToken.controlRadius)
        .backgroundColor(CloudThemeToken.surfaceSubtle)

        Column({ space: CloudThemeToken.uploadSourceTextGap }) {
          Text(title)
            .fontSize(CloudThemeToken.uploadSourceTitleTextSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(description)
            .fontSize(CloudThemeToken.uploadSourceDescriptionSize)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Image($r('app.media.ic_chevron_right'))
          .width(CloudThemeToken.sheetActionIconSize)
          .height(CloudThemeToken.sheetActionIconSize)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(CloudThemeToken.uploadSourceRowHeight)
    .padding({
      left: CloudThemeToken.uploadSourceItemHorizontalPadding,
      right: CloudThemeToken.uploadSourceItemHorizontalPadding
    })
    .enabled(!this.isPicking)
    .opacity(this.isPicking ? CloudThemeToken.disabledOpacity : CloudThemeToken.fullOpacity)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .onClick(onClick)
  }

  async selectPhotos(isVideo: boolean) {
    if (this.isPicking) {
      return
    }
    this.isPicking = true
    // picker 启动有 ~1s，让 sheet 先关，picker 后台异步起，避免明显等待
    const onSelected = this.onSelectFinished
    if (this.onClose) {
      this.onClose()
    }

    const photoViewPicker = new photoAccessHelper.PhotoViewPicker()
    const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
    photoSelectOptions.MIMEType = isVideo
      ? photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE
      : photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE

    photoViewPicker.select(photoSelectOptions).then((photoSelectResult: photoAccessHelper.PhotoSelectResult) => {
      const uris = photoSelectResult.photoUris
      if (uris.length > 0 && onSelected) {
        onSelected(uris)
      }
    }).catch((err: BusinessError) => {
      AppLogger.error(TAG, `photoViewPicker.select failed, code=${err.code} msg=${err.message}`)
      showToastTips(isVideo ? '选择视频失败' : '选择图片失败', ToastType.Error)
    })
  }

  async selectFiles() {
    if (this.isPicking) {
      return
    }
    this.isPicking = true
    const context = this.getAbilityContext()
    if (!context) {
      this.isPicking = false
      AppLogger.error(TAG, 'Document picker context is unavailable')
      showToastTips($r('app.string.get_context_failed'), ToastType.Error)
      return
    }
    const onSelected = this.onSelectFinished
    if (this.onClose) {
      this.onClose()
    }

    const documentSelectOptions = new picker.DocumentSelectOptions()
    const documentViewPicker = new picker.DocumentViewPicker(context)
    documentViewPicker.select(documentSelectOptions).then((documentSelectResult: Array<string>) => {
      const uris = documentSelectResult
      if (uris.length > 0 && onSelected) {
        onSelected(uris)
      }
    }).catch((err: BusinessError) => {
      AppLogger.error(TAG, `documentViewPicker.select failed, code=${err.code} msg=${err.message}`)
      showToastTips('选择文件失败', ToastType.Error)
    })
  }

  private getAbilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext) {
      return hostContext as common.UIAbilityContext
    }
    return undefined
  }
}
