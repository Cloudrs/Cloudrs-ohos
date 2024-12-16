import { HMRouter } from "@hadss/hmrouter";
import { CommonTitle } from "../components/CommonTitle";
import Constant from "../model/Constant";

const EMAIL: string = 'postmaster@dreamflytech.com'

@HMRouter({pageUrl: Constant.ABOUT_PAGE})
@Component
export struct AboutPage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';

  build() {
    Column({space: 10}) {
      CommonTitle({title: $r('app.string.about')})

      Blank().height(20)
      this.logoTitle()

      this.aboutInfo()

      Blank().layoutWeight(1)
      Hyperlink('https://beian.miit.gov.cn', $r('app.string.icp_id')).height(12)

      Blank().height(this.bottomRectHeight)
    }
    .width('100%').height('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor($r('app.color.common_background'))
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder logoTitle() {
    Column({space: 10}) {
      Image($r('app.media.cloudrs'))
        .height(100)
        .width(100)
        .borderRadius(20)
        .backgroundColor(Color.White)

      Text($r('app.string.EntryAbility_label'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder aboutInfo() {
    Column() {
      this.commonInfo($r('app.string.version'), this.appVersion)
      Divider().strokeWidth('2px').color($r('app.color.default_line_color'))
      this.commonInfo($r('app.string.about_email'), EMAIL)
    }
    .width('100%')
    .margin({top: 30})
    .backgroundColor(Color.White)
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
  }

  @Builder commonInfo(title: ResourceStr, info: ResourceStr) {
    Row () {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
      Text(info)
        .fontSize(14)
        .fontColor($r('app.color.common_font_gray'))
    }
    .height(50)
    .width('100%')
    .padding({left: 10, right: 10})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }
}