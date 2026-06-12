import { CommonTitle } from "../components/CommonTitle";
import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudApi } from "../model/net/CloudApi";
import AppLogger from "../utils/AppLogger";

const EMAIL: string = 'wangxian@dreamflytech.com'
const ABOUT_TAG: string = 'AboutPage'

@Component
export struct AboutPage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';
  @StorageProp(Constant.CLOUD_COOKIE) cloudCookie: string = '';
  @State cloudApiVersion: string = ''
  embedded: boolean = false

  aboutToAppear(): void {
    this.cloudApiVersion = this.initialApiVersionText()
    AppLogger.info(ABOUT_TAG, `aboutToAppear cookieLen=${(this.cloudCookie ?? '').length} initial=${this.cloudApiVersion}`)
    CloudApi.getApiVersionInfo({
      onSuccess: (info: string[]) => {
        AppLogger.info(ABOUT_TAG, `getApiVersionInfo ok info=${JSON.stringify(info)}`)
        const api = (info[0] ?? '').trim()
        const server = (info[1] ?? '').trim()
        if (api.length === 0) {
          return
        }
        const hasServer = server.length > 0 && server !== 'unknown'
        // Prefer the precise server version (e.g. "v4.16.0"); fall back to the
        // major-only label (e.g. "v4") if /site/ping didn't return it.
        const versionPart = hasServer
          ? (server.startsWith('v') ? server : `v${server}`)
          : api
        this.cloudApiVersion = `Cloudreve API ${versionPart}`
        AppLogger.info(ABOUT_TAG, `set cloudApiVersion=${this.cloudApiVersion}`)
      },
      onFailure: (msg: string) => {
        AppLogger.warn(ABOUT_TAG, `getApiVersionInfo failed: ${msg}`)
      }
    })
  }

  private initialApiVersionText(): string {
    const cookie = this.cloudCookie ?? ''
    if (cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX)) {
      return 'Cloudreve API v4'
    }
    if (cookie.startsWith(Constant.CLOUD_V3_COOKIE_PREFIX)) {
      return 'Cloudreve API v3'
    }
    return ''
  }

  build() {
    Column({ space: CloudThemeToken.aboutPageGap }) {
      if (!this.embedded) {
        CommonTitle({title: $r('app.string.about')})
      }

      Blank().height(CloudThemeToken.aboutLogoTopGap)
      this.logoTitle()

      this.aboutInfo()

      Blank().layoutWeight(1)
      Hyperlink('https://beian.miit.gov.cn', $r('app.string.icp_id'))
        .height(CloudThemeToken.aboutIcpHeight)
        .margin({ bottom: CloudThemeToken.pageBottomPadding })

      if (!this.embedded) {
        Blank().height(this.bottomRectHeight)
      }
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
      Row () {
        Text($r('app.string.about_api_version'))
          .fontSize(CloudThemeToken.aboutInfoTitleSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
        Text(this.cloudApiVersion.length > 0 ? this.cloudApiVersion : '—')
          .fontSize(CloudThemeToken.aboutInfoTextSize)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .height(CloudThemeToken.aboutInfoRowHeight)
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
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
