import Constant from "../model/Constant";
import { CircleShape } from "@kit.ArkUI";
import image from "@ohos.multimedia.image";
import { cloudGetPreview } from "../model/net/Api";
import { HMParamType, HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import { ImagePreview } from "../model/Params";

@HMRouter({pageUrl: Constant.IAMGE_PREVIEW_PAGE})
@Component
export struct iamgePreview {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State imageData:PixelMap | undefined | Resource = undefined;
  @State imageWidth: number | string = 128;

  private fileName: string = ''
  private fileId: string = ''

  async getImageFile() {
    cloudGetPreview(this.fileId, {
      onSuccess: (data: ArrayBuffer) => {
        let imageSource: image.ImageSource = image.createImageSource(data)
        imageSource.createPixelMap().then((pixMap: PixelMap) => {
          this.imageData = pixMap
          this.imageWidth = '100%'
        })
      },
      onFailure: (msg) => {
        this.imageData = $r('app.media.ic_picture_damage')
        this.imageWidth = 128
      }
    })
  }

  aboutToAppear(): void {
    if (HMRouterMgr.getCurrentParam()) {
      let param = HMRouterMgr.getCurrentParam() as ImagePreview
      this.fileName = param.fileName
      this.fileId = param.fileId
    }
    this.getImageFile()
  }

  build() {
    Column(){
      Blank().height(this.sysTopRectHeight)
      this.previewHeader()
      Column() {
        Image(this.imageData)
          .width(this.imageWidth)
      }
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
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
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(Color.White)
        .onClick(() => {
          HMRouterMgr.pop()
        })

        Text(this.fileName)
          .fontSize(16)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)

        Button() {
          Image($r('app.media.ic_more'))
            .fillColor(Color.Black)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.nav_background'))
        .onClick(() => {

        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .padding(10)
      Divider().strokeWidth(1).color($r('app.color.default_line_color'))
    }
    .justifyContent(FlexAlign.Center)
    .height(60)
    .width('100%')
  }
}