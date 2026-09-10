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
    // 矮屏或大字体下本页装不下（半模态的 MEDIUM 挡位尤其明显），底部会被裁掉。
    // 只让信息卡与备案号那段滚动：标题栏、logo 与应用名是本页的身份，滚走了就
    // 不知道自己在看什么。底部安全距挂在最外层，滚动视口本身即止步于导航条之上，
    // 内容任何时刻都不会经过导航条底下。
    Column({ space: CloudThemeToken.aboutPageGap }) {
      if (!this.embedded) {
        CommonTitle({title: $r('app.string.about')})
      }

      this.logoTitle()

      Scroll() {
        Column({ space: CloudThemeToken.aboutPageGap }) {
          this.aboutInfo()

          Blank().layoutWeight(1)
          Hyperlink('https://beian.miit.gov.cn', $r('app.string.icp_id'))
            .height(CloudThemeToken.aboutIcpHeight)
            // 上面的 Blank 只在有余量时才撑得开，滚动态下会塌成 0；
            // 这条 margin 是备案号不贴住信息卡的保底
            .margin({ top: CloudThemeToken.aboutIcpTopGap })
        }
        .width('100%')
        // 用 minHeight 而非 height：空间够时照旧撑满，上面那个 layoutWeight 的 Blank
        // 仍把备案号顶到滚动区底部，观感不变；空间不够时退回自然高度交给 Scroll
        .constraintSize({ minHeight: '100%' })
        // 左右内边距下沉到滚动内容上，Scroll 本身通栏：滚动条画在组件右边界，
        // 留在这条 16vp 的空白槽里，不会压到信息卡上
        .padding({ left: CloudThemeToken.pagePadding, right: CloudThemeToken.pagePadding })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .layoutWeight(1)
      // 应用名与信息卡之间的间距（原挂在卡片的 margin 上），移到滚动区外边距：
      // 视口顶端即卡片顶端，顶上不再留空，滚动条也从卡片顶端起算
      .margin({ top: CloudThemeToken.aboutInfoTopMargin })
      .align(Alignment.Top)
      // 常驻细滚动条：装得下时 ArkUI 自己不画，装不下才出现，正好当"可以滚"的提示。
      // 只收窄宽度、不改颜色——系统默认色本就是低对比的半透明灰，且跟随深浅色
      .scrollBar(BarState.On)
      .scrollBarWidth(CloudThemeToken.strongLineWidth)
      .scrollBarColor(CloudThemeToken.scrollBar)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    // 导航条高度必须原样留出，上面只压一道细缝：本页最后一行是备案号，
    // 不是可点控件，不需要留出触摸安全距
    .padding({ bottom: this.bottomRectHeight + CloudThemeToken.spacingSm })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(CloudThemeToken.background)
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
    // 与应用名之间的间距不放这里：本卡是滚动区的第一个子节点，放在这儿会变成
    // 滚动区内部的一段空白，滚动条也跟着从那段空白开始画。间距移到 Scroll 的
    // 外边距上，卡片才贴着视口顶端
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
