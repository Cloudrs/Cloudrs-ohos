import { photoAccessHelper } from "@kit.MediaLibraryKit"
import { BusinessError } from "@kit.BasicServicesKit"
import { common } from "@kit.AbilityKit"
import { picker } from "@kit.CoreFileKit"
import { CloudThemeToken } from "../model/CloudTheme"

const TAG: string = 'SelectFileSheet'

@Component
export struct SelectFileSheet {
  @State showPhotoPicker: boolean = false
  onSelectFinished?: (uris: string[]) => void
  onClose?: () => void

  build() {
    Column({ space: 16 }) {
      Row() {
        Text($r('app.string.upload'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)

        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_xmark'))
            .width(CloudThemeToken.sheetActionIconSize)
            .height(CloudThemeToken.sheetActionIconSize)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
        .width(CloudThemeToken.smallIconButtonSize)
        .height(CloudThemeToken.smallIconButtonSize)
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

      Column({ space: 10 }) {
        this.uploadSourceItem(
          $r('app.media.ic_upload_file_modern'),
          $r('app.string.local_files'),
          '从文管选择任意文件',
          CloudThemeToken.uploadFileSoft,
          () => {
            this.selectFiles()
          })

        this.uploadSourceItem(
          $r('app.media.ic_upload_photo_modern'),
          $r('app.string.local_photos'),
          '从相册选择图片',
          CloudThemeToken.uploadPhotoSoft,
          () => {
            this.selectPhotos(false)
          })

        this.uploadSourceItem(
          $r('app.media.ic_upload_video_modern'),
          $r('app.string.local_videos'),
          '从相册选择视频',
          CloudThemeToken.uploadVideoSoft,
          () => {
            this.selectPhotos(true)
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 28 })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder uploadSourceItem(icon: Resource, title: ResourceStr, description: ResourceStr,
    iconBackground: ResourceColor, onClick: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 12 }) {
        Stack() {
          Image(icon)
            .width(CloudThemeToken.sheetOptionIconSize)
            .height(CloudThemeToken.sheetOptionIconSize)
            .draggable(false)
        }
        .width(CloudThemeToken.uploadSourceIconBoxSize)
        .height(CloudThemeToken.uploadSourceIconBoxSize)
        .borderRadius(CloudThemeToken.controlRadius)
        .backgroundColor(iconBackground)

        Column({ space: 4 }) {
          Text(title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(description)
            .fontSize(12)
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
    .padding({ left: 14, right: 14 })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .onClick(onClick)
  }

  async selectPhotos(isVideo: boolean) {
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
      if (uris.length > 0 && this.onSelectFinished) {
        this.onSelectFinished(uris)
      }
    }).catch((err: BusinessError) => {
      console.error(TAG, `Invoke photoViewPicker.select failed, code is ${err.code}, message is ${err.message}`);
    })
  }

  async selectFiles() {
    let uris: Array<string> = [];
    const context = this.getAbilityContext();
    if (!context) {
      console.error(TAG, 'Document picker context is unavailable');
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
      if (uris.length > 0 && this.onSelectFinished) {
        this.onSelectFinished(uris)
      }
      console.info(TAG, 'documentViewPicker.select to file succeed and uris are:' + uris);
    }).catch((err: BusinessError) => {
      console.error(TAG, `Invoke documentViewPicker.select failed, code is ${err.code}, message is ${err.message}`);
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
