import { HMRouter } from "@hadss/hmrouter";
import { CommonTitle } from "../components/CommonTitle";
import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";

const EMAIL: string = 'wangxian@dreamflytech.com'

@HMRouter({pageUrl: Constant.ABOUT_PAGE})
@Component
export struct AboutPage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';

  build() {
    Column({ space: CloudThemeToken.aboutPageGap }) {
      CommonTitle({title: $r('app.string.about')})

      Blank().height(CloudThemeToken.aboutLogoTopGap)
      this.logoTitle()

      this.aboutInfo()

      Blank().layoutWeight(1)
      Hyperlink('https://beian.miit.gov.cn', $r('app.string.icp_id')).height(CloudThemeToken.aboutIcpHeight)

      Blank().height(this.bottomRectHeight)
    }
    .width('100%').height('100%')
    .padding({ left: CloudThemeToken.pagePadding, right: CloudThemeToken.pagePadding })
    .backgroundColor(CloudThemeToken.background)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder logoTitle() {
    Column({ space: CloudThemeToken.aboutLogoGap }) {
      Image($r('app.media.cloudrs'))
        .height(CloudThemeToken.aboutLogoSize)
        .width(CloudThemeToken.aboutLogoSize)
        .borderRadius(CloudThemeToken.surfaceRadius)
        .backgroundColor(CloudThemeToken.surface)

      Text($r('app.string.EntryAbility_label'))
        .fontSize(CloudThemeToken.aboutTitleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder aboutInfo() {
    Column() {
      this.commonInfo($r('app.string.version'), this.appVersion)
      Divider().strokeWidth(CloudThemeToken.lineWidth).color(CloudThemeToken.line)
      this.commonInfo($r('app.string.about_email'), EMAIL)
    }
    .width('100%')
    .padding({ left: CloudThemeToken.aboutInfoHorizontalPadding, right: CloudThemeToken.aboutInfoHorizontalPadding })
    .margin({ top: CloudThemeToken.aboutInfoTopMargin })
    .backgroundColor(CloudThemeToken.surface)
    .borderRadius(CloudThemeToken.cardRadius)
    .justifyContent(FlexAlign.Center)
  }

  @Builder commonInfo(title: ResourceStr, info: ResourceStr) {
    Row () {
      Text(title)
        .fontSize(CloudThemeToken.aboutInfoTitleSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
      Text(info)
        .fontSize(CloudThemeToken.aboutInfoTextSize)
        .fontColor(CloudThemeToken.textSecondary)
    }
    .height(CloudThemeToken.aboutInfoRowHeight)
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
