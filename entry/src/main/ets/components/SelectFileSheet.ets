import { photoAccessHelper } from "@kit.MediaLibraryKit"
import { BusinessError } from "@kit.BasicServicesKit"
import { common } from "@kit.AbilityKit"
import { picker } from "@kit.CoreFileKit"

const TAG: string = 'SelectFileSheet'

@Component
export struct SelectFileSheet {
  @State showPhotoPicker: boolean = false
  onSelectFinished?: (uris: string[]) => void

  build() {
    Column() {
      // Text($r('app.string.upload'))
      //   .fontSize(16)
      //   .fontWeight(FontWeight.Bold)

      Row() {
        Column({space:15}) {
          Image($r('app.media.ic_select_files'))
            .width(40)
            .height(40)

          Text($r('app.string.local_files'))
            .fontSize(14)
            .fontColor($r('app.color.common_font_gray'))
        }
        .onClick(async () => {
          this.selectFiles()
        })

        Column({space:15}) {
          Image($r('app.media.ic_select_photos'))
            .width(40)
            .height(40)

          Text($r('app.string.local_photos'))
            .fontSize(14)
            .fontColor($r('app.color.common_font_gray'))
        }
        .onClick(async () => {
          this.selectPhotos(false)
        })

        Column({space:15}) {
          Image($r('app.media.ic_select_videos'))
            .width(40)
            .height(40)

          Text($r('app.string.local_videos'))
            .fontSize(14)
            .fontColor($r('app.color.common_font_gray'))
        }
        .onClick(() => {
          this.selectPhotos(true)
        })
      }
      .width('100%')
      .height(100)
      .padding({left: 30, right: 30})
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
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
    let context = getContext(this) as common.Context; // 请确保 getContext(this) 返回结果为 UIAbilityContext

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
}