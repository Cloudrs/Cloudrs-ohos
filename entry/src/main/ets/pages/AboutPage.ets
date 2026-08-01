import { common } from "@kit.AbilityKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { CommonTitle } from "../components/CommonTitle";
import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudApi } from "../model/net/CloudApi";
import AppLogger from "../utils/AppLogger";
import { showToast } from "../utils/ToastUtil";
import { GIT_COMMIT, VERSION_CODE } from 'BuildProfile';

const EMAIL: string = 'wangxian@dreamflytech.com'
const ABOUT_TAG: string = 'AboutPage'
/** 开源仓库镜像。gitea 是自建私有源，不对外公开，这里只放 GitHub / Gitee 两个公开镜像 */
const GITHUB_URL: string = 'https://github.com/Cloudrs/Cloudrs-ohos'
const GITEE_URL: string = 'https://gitee.com/larriti/cloudrs-ohos'

@Component
export struct AboutPage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';
  @StorageProp(Constant.CLOUD_COOKIE) cloudCookie: string = '';
  @State cloudApiVersion: string = ''
  /** 版本号那一行是否正显示构建来源，点一下切换 */
  @State showGitCommit: boolean = false
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
      this.versionInfo()
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
      Divider().strokeWidth(CloudThemeToken.lineWidth).color(CloudThemeToken.line)
      this.sourceInfo()
    }
    .width('100%')
    .padding({ left: CloudThemeToken.aboutInfoHorizontalPadding, right: CloudThemeToken.aboutInfoHorizontalPadding })
    .margin({ top: CloudThemeToken.aboutInfoTopMargin })
    .backgroundColor(CloudThemeToken.surface)
    .borderRadius(CloudThemeToken.cardRadius)
    .justifyContent(FlexAlign.Center)
  }

  /** 开源地址一行放两个镜像，点哪个就用系统浏览器开哪个 */
  @Builder sourceInfo() {
    Row () {
      Text($r('app.string.about_source'))
        .fontSize(CloudThemeToken.aboutInfoTitleSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
      Row({ space: CloudThemeToken.aboutSourceLinkGap }) {
        this.sourceLink('GitHub', GITHUB_URL)
        this.sourceLink('Gitee', GITEE_URL)
      }
    }
    .height(CloudThemeToken.aboutInfoRowHeight)
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder sourceLink(label: string, url: string) {
    Text(label)
      .fontSize(CloudThemeToken.aboutInfoTextSize)
      .fontColor(CloudThemeToken.primary)
      .height(CloudThemeToken.aboutSourceLinkHeight)
      .padding({
        left: CloudThemeToken.aboutSourceLinkPadding,
        right: CloudThemeToken.aboutSourceLinkPadding
      })
      .borderRadius(CloudThemeToken.aboutSourceLinkRadius)
      .backgroundColor(CloudThemeToken.primarySoft)
      .textAlign(TextAlign.Center)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(`打开 ${label} 仓库`)
      .onClick(() => this.openExternalUrl(url))
  }

  private openExternalUrl(url: string): void {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      showToast('无法打开链接')
      return
    }

    const context = hostContext as common.UIAbilityContext
    context.startAbility({
      action: 'ohos.want.action.viewData',
      uri: url,
      entities: ['entity.system.browsable']
    }).catch((err: BusinessError) => {
      AppLogger.error(ABOUT_TAG, `open external url failed: ${err.code}, ${err.message}`)
      showToast('无法打开浏览器')
    })
  }

  /**
   * 版本行。点一下把版本号换成构建它的 git 短哈希，再点一下换回来。
   * 拿到一个上架的包时，靠它回溯是从哪个 commit 构建的。
   */
  @Builder versionInfo() {
    Row() {
      Text($r('app.string.version'))
        .fontSize(CloudThemeToken.aboutInfoTitleSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
      Text(this.showGitCommit ? GIT_COMMIT : `${this.appVersion}(${VERSION_CODE})`)
        .fontSize(CloudThemeToken.aboutInfoTextSize)
        .fontColor(CloudThemeToken.textSecondary)
    }
    .height(CloudThemeToken.aboutInfoRowHeight)
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .onClick(() => {
      this.showGitCommit = !this.showGitCommit
    })
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
