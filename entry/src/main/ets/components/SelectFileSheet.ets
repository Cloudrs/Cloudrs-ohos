import { photoAccessHelper } from "@kit.MediaLibraryKit"
import { BusinessError } from "@kit.BasicServicesKit"
import { common } from "@kit.AbilityKit"
import { picker } from "@kit.CoreFileKit"
import { CloudThemeToken } from "../model/CloudTheme"
import Constant from "../model/Constant"
import { showToastTips, ToastType } from "../utils/ToastUtil"

const TAG: string = 'SelectFileSheet'

@Component
export struct SelectFileSheet {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @Prop extraBottomPadding: number = 0
  @State showPhotoPicker: boolean = false
  @State isPicking: boolean = false
  @State pickingText: string = ''
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

      if (this.isPicking) {
        Row({ space: CloudThemeToken.spacingXl }) {
          LoadingProgress()
            .width(CloudThemeToken.iconLg)
            .height(CloudThemeToken.iconLg)
            .color(CloudThemeToken.primary)
          Text(this.pickingText)
            .fontSize(CloudThemeToken.textSizeSmallPlus)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(CloudThemeToken.rowHeightMd)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
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

  private startPicking(text: string): void {
    this.isPicking = true
    this.pickingText = text
  }

  private stopPicking(): void {
    this.isPicking = false
    this.pickingText = ''
  }

  async selectPhotos(isVideo: boolean) {
    if (this.isPicking) {
      return
    }
    this.startPicking(isVideo ? '正在打开视频选择器' : '正在打开图片选择器')
    let uris: Array<string> = [];

    const photoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    if (isVideo) {
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
    } else {
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    }

    photoViewPicker.select(photoSelectOptions).then((photoSelectResult: photoAccessHelper.PhotoSelectResult) => {
      uris = photoSelectResult.photoUris;
      console.info(TAG, 'photoViewPicker.select to file succeed and uris are:' + uris);
      this.stopPicking()
      if (uris.length > 0 && this.onSelectFinished) {
        this.onSelectFinished(uris)
      }
    }).catch((err: BusinessError) => {
      this.stopPicking()
      console.error(TAG, `Invoke photoViewPicker.select failed, code is ${err.code}, message is ${err.message}`);
      showToastTips(isVideo ? '选择视频失败' : '选择图片失败', ToastType.Error)
    })
  }

  async selectFiles() {
    if (this.isPicking) {
      return
    }
    this.startPicking('正在打开文件选择器')
    let uris: Array<string> = [];
    const context = this.getAbilityContext();
    if (!context) {
      this.stopPicking()
      console.error(TAG, 'Document picker context is unavailable');
      showToastTips($r('app.string.get_context_failed'), ToastType.Error)
      return;
    }

    const documentSelectOptions = new picker.DocumentSelectOptions();
    // 选择文档的最大数目（可选）
    // documentSelectOptions.maxSelectNumber = 5;
    // 指定选择的文件或者目录路径（可选）
    // documentSelectOptions.defaultFilePathUri = "file://docs/storage/Users/currentUser/Download";
    // 选择文件的后缀类型['后缀类型描述|后缀类型']（可选） 若选择项存在多个后缀名，则每一个后缀名之间用英文逗号进行分隔（可选），后缀类型名不能超过100,选择所有文件：'所有文件(*.*)|.*';
    // documentSelectOptions.fileSuffixFilters = ['图片(.png, .jpg)|.png,.jpg', '文档|.txt', '视频|.mp4', '.pdf'];
    //选择是否对指定文件或目录授权，true为授权，当为true时，defaultFilePathUri为必选参数，拉起文管授权界面；false为非授权，拉起常规文管界面（可选）
    // documentSelectOptions.authMode = true;

    // 创建文件选择器实例
    const documentViewPicker = new picker.DocumentViewPicker(context);
    documentViewPicker.select(documentSelectOptions).then((documentSelectResult: Array<string>) => {
      //文件选择成功后，返回被选中文档的uri结果集。
      uris = documentSelectResult;
      this.stopPicking()
      if (uris.length > 0 && this.onSelectFinished) {
        this.onSelectFinished(uris)
      }
      console.info(TAG, 'documentViewPicker.select to file succeed and uris are:' + uris);
    }).catch((err: BusinessError) => {
      this.stopPicking()
      console.error(TAG, `Invoke documentViewPicker.select failed, code is ${err.code}, message is ${err.message}`);
      showToastTips('选择文件失败', ToastType.Error)
    })
  }

  private getAbilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext) {
      return hostContext as common.UIAbilityContext;
    }
    return undefined;
  }
}
