import Constant from "../model/Constant";
import image from "@ohos.multimedia.image";
import { cloudGetPreview } from "../model/net/CloudApi";
import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import { ImagePreview } from "../model/Params";
import { FileUtil } from "@pura/harmony-utils";
import { photoAccessHelper } from "@kit.MediaLibraryKit";
import { showToast } from "../utils/ToastUtil";
import { systemShare } from "@kit.ShareKit";
import { uniformTypeDescriptor } from "@kit.ArkData";
import { common } from "@kit.AbilityKit";

@HMRouter({pageUrl: Constant.IAMGE_PREVIEW_PAGE})
@Component
export struct iamgePreview {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State imagePixelMap:PixelMap | undefined | Resource = undefined;
  @State imageWidth: number | string = '100%';
  @State isLoading: boolean = true;
  private fileParam: ImagePreview|null = null;
  private imageData: ArrayBuffer|null = null;

  @State saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.SAVE_IMAGE,
    buttonType: ButtonType.Capsule
  } // 设置安全控件按钮属性

  async getImageFile() {
    if (this.fileParam) {
      cloudGetPreview(this.fileParam.fileId, {
        onSuccess: (data: ArrayBuffer) => {
          this.imageData = data
          let imageSource: image.ImageSource = image.createImageSource(this.imageData)
          imageSource.createPixelMap().then((pixMap: PixelMap) => {
            this.imagePixelMap = pixMap
            this.imageWidth = '100%'
            this.isLoading = false
          })
        },
        onFailure: (msg) => {
          this.imagePixelMap = $r('app.media.ic_picture_damage')
          this.imageWidth = 128
          this.isLoading = false
        }
      })
    }
  }

  aboutToAppear(): void {
    if (HMRouterMgr.getCurrentParam()) {
      let param = HMRouterMgr.getCurrentParam() as ImagePreview
      this.fileParam = param
    }
    this.getImageFile()
  }

  build() {
    Column(){
      Blank().height(this.sysTopRectHeight)
      this.previewHeader()

      Column() {
        if (this.isLoading) {
          LoadingProgress()
            .width(40)
            .height(40)
        }
        else {
          Image(this.imagePixelMap)
            .width(this.imageWidth)
        }
      }
      .width('100%')
      .backgroundColor(Color.Black)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column() {
        SaveButton(this.saveButtonOptions)
          .onClick(() => {
            this.saveImage()
          })
      }
      .width('100%')
      .backgroundColor(Color.Black)
      .alignItems(HorizontalAlign.Center)
      .padding({bottom: this.bottomRectHeight})
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.nav_background'))
  }

  @Builder previewHeader() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.ic_xmark_circle_fill'))
            .fillColor($r('app.color.light_gray'))
            .draggable(false)
            .padding(5)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.nav_background'))
        .onClick(() => {
          HMRouterMgr.pop()
        })

        Text(this.fileParam ? this.fileParam.fileName : '')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
          .layoutWeight(1)

        Button() {
          Image($r('app.media.ic_share'))
            .draggable(false)
            .fillColor(Color.Black)
            .padding(5)
        }
        .margin({top: 4})
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.nav_background'))
        .onClick(() => {
          this.shareImage()
        })
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .padding(10)
      Divider().strokeWidth(1).color($r('app.color.default_line_color'))
    }
    .justifyContent(FlexAlign.Center)
    .height(50)
    .width('100%')
  }

  async saveImage() {
    if (this.fileParam) {
      try {
        let context = getContext();
        let photoType: photoAccessHelper.PhotoType = photoAccessHelper.PhotoType.IMAGE;
        let extension: string = this.fileParam.fileExtension;
        let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
        let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
          photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(context, photoType, extension);
        assetChangeRequest.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, this.imageData);
        await phAccessHelper.applyChanges(assetChangeRequest);
        showToast('已保存至相册')
      } catch(err) {
        console.error('ImagePreview', `addResourceByArrayBufferDemo failed with error: ${err.code}, ${err.message}`);
        showToast('保存至相册失败')
      }
    }
  }

  async shareImage() {
    if (this.fileParam) {
      try {
        let context = getContext(this) as common.UIAbilityContext;
        let path = context.tempDir + '/' + this.fileParam.fileName
        let uri = FileUtil.getUriFromPath(path)
        console.debug('ImagePreview', 'uri: ' + uri)
        await FileUtil.writeEasy(uri, this.imageData, false)
        // 保存到应用沙箱先，后续支持直接将arraybuffer发送就最好了
        let data: systemShare.SharedData = new systemShare.SharedData({
          utd: uniformTypeDescriptor.UniformDataType.IMAGE,
          title: this.fileParam.fileName,
          uri: uri
        })
        let controller: systemShare.ShareController = new systemShare.ShareController(data)
        controller.show(context, {
          previewMode: systemShare.SharePreviewMode.DEFAULT,
          selectionMode: systemShare.SelectionMode.SINGLE
        })
        controller.on('dismiss', () => {
          console.debug('ImagePreview', 'share dismiss, unlink image file!')
          FileUtil.unlink(path)
        })
      } catch(err) {
        console.error('ImagePreview', `share image failed with error: ${err.code}, ${err.message}`);
        showToast('分享失败')
      }
    }
  }
}