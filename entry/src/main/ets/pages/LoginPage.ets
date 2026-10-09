import { KeyboardAvoidMode, LengthMetrics, window } from '@kit.ArkUI'
import { DbUserInfo, SiteConfig, UserInfo, TwoFactorCallback } from '../model/net/ApiTypes';
import { showToastTips, ToastType } from '../utils/ToastUtil';
import Constant from '../model/Constant';
import UserPrivData from '../model/UserPreferences';
import UserDatabase from '../model/UserDatabase';
import { LoginParam } from '../model/net/LoginParam';
import { CloudApi } from '../model/net/CloudApi';
import { image } from '@kit.ImageKit';
import { CloudThemeToken } from '../model/CloudTheme';
import { CloudMaterial } from '../model/CloudMaterial';
import { CloudRouter } from '../utils/CloudRouter';
import { ActiveAccount } from '../utils/ActiveAccount';
import { AvatarUtil } from '../utils/AvatarUtil';
import { UserSwitchSheet } from '../components/UserSwitchSheet';
import scanBarcode from '@hms.core.scan.scanBarcode';
import { BusinessError } from '@kit.BasicServicesKit';
import { DividerShowType, HdsNavigation, HdsNavigationTitleMode, hdsMaterial } from '@kit.UIDesignKit';
import { OtpInput } from '../components/OtpInput';
import AppLogger from '../utils/AppLogger';
import { WindowMover } from '../utils/WindowMover';
import { common } from '@kit.AbilityKit';

@Extend(Row)
function rowCommonStyle() {
  .borderRadius(CloudThemeToken.cardRadius)
  .backgroundColor(CloudThemeToken.surface)
  .width('100%')
  .height(CloudThemeToken.inputHeight)
  .alignItems(VerticalAlign.Center)
}

class ScannedLoginData {
  address: string = ''
  username: string = ''
  password: string = ''
  refreshToken: string = ''
}

interface ScanGroupLike {
  id?: string
  name?: string
  allowShare?: boolean
  allowRemoteDownload?: boolean
  allowArchiveDownload?: boolean
  shareDownload?: boolean
  compress?: boolean
  webdav?: boolean
  sourceBatch?: number
  advanceDelete?: boolean
  allowWebDAVProxy?: boolean
}

interface ScanUserLike {
  id?: string
  user_name?: string
  email?: string
  nickname?: string
  status?: number|string
  avatar?: string|Object
  created_at?: string
  preferred_theme?: string
  anonymous?: boolean
  group?: ScanGroupLike
}

@CustomDialog
struct PrivacyConfirmDialog {
  controller?: CustomDialogController
  onAgree: () => void = () => {
  }
  onViewPolicy: () => void = () => {
  }

  build() {
    Column({ space: CloudThemeToken.spacingPage }) {
      Text($r('app.string.login_privacy_dialog_title'))
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)

      Text() {
        Span($r('app.string.login_privacy_dialog_message_prefix'))
        Span($r('app.string.login_privacy_dialog_link'))
          .fontColor(CloudThemeToken.primary)
          .onClick(() => {
            this.onViewPolicy()
          })
        Span($r('app.string.login_privacy_dialog_message_suffix'))
      }
      .fontSize(CloudThemeToken.textSizeLarge)
      .fontColor(CloudThemeToken.textPrimary)
      .textAlign(TextAlign.Center)
      .width('100%')

      Row() {
        Button($r('app.string.dialog_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontColor(CloudThemeToken.primary)
          .layoutWeight(1)
          .onClick(() => {
            this.controller?.close()
          })
        Button($r('app.string.login_privacy_dialog_agree'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontColor(CloudThemeToken.primary)
          .layoutWeight(1)
          .onClick(() => {
            this.controller?.close()
            this.onAgree()
          })
      }
      .width('100%')
    }
    .padding(CloudThemeToken.spacingPage)
    .width('100%')
  }
}

@Component
export struct LoginPage {
  routeParam?: LoginParam
  @StorageProp(Constant.CLOUD_COOKIE) cookie: string = '';
  // 2in1 隐藏系统标题栏后 >0；此时登录页顶部需要自备窗口拖动区
  @StorageProp(Constant.TITLE_BUTTON_INSET_END) titleButtonInsetEnd: number = 0
  @StorageProp(Constant.CLOUD_COOKIE_EXPIRES) cookieExpires: string = '';
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0;
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State protocolIndex: number = Constant.PROTOCOL_HTTPS_INDEX
  @State protocol: string = Constant.PROTOCOL_HTTPS_SCHEME
  @State keyHeight: number = 0;
  // 键盘弹出时底部显隐用的测量值（vp）：未弹键盘时的页面总高、主内容去掉 logo 的高度、两块底部内容的高度
  @State private loginBodyHeight: number = 0
  @State private contentNoLogoHeight: number = 0
  @State private footerIconsHeight: number = 0
  @State private privacyHeight: number = 0
  private loginContentHeight: number = 0
  private loginLogoHeight: number = 0
  @State websiteInvalid: boolean = false;
  @State loginInvalid: boolean = false;
  @State needs2FA: boolean = false;
  @State privacyAccepted: boolean = false;
  @State loginTitle: string|Resource = $r('app.string.website_title');
  @State websiteLogo: Resource|PixelMap = $r('app.media.cloudrs')
  @State showUserSwitchSheet: boolean = false
  @State activeUserName: string = ''
  @State activeUserUrl: string = ''

  @State private address: string = ''
  @State private username: string = ''
  @State private password: string = ''
  @State private otpCode: string = ''
  scroller: Scroller = new Scroller();
  private nextPage: string|null = Constant.HOME_PAGE
  private readonly otpInputId: string = 'loginOtpInput'
  private readonly usernameInputId: string = 'loginUsernameInput'
  private readonly passwordInputId: string = 'loginPasswordInput'
  private scanShouldAutoLogin: boolean = false
  private keyboardWindow?: window.Window
  private avoidAreaListener?: (data: window.AvoidAreaOptions) => void
  private pendingPrivacyAgree: (() => void) | undefined = undefined
  private privacyDialogController: CustomDialogController = new CustomDialogController({
    builder: PrivacyConfirmDialog({
      onAgree: () => {
        this.privacyAccepted = true
        const action = this.pendingPrivacyAgree
        this.pendingPrivacyAgree = undefined
        if (action) {
          action()
        }
      },
      onViewPolicy: () => {
        this.openPrivacyPolicy()
      }
    }),
    autoCancel: true
  })

  private isKeyboardVisible(): boolean {
    return this.keyHeight > CloudThemeToken.zero
  }

  // logo 随键盘缩放，单独扣掉；剩下的部分只随登录步骤变化，键盘弹出前后不变
  private updateContentNoLogoHeight(): void {
    this.contentNoLogoHeight = Math.max(CloudThemeToken.zero, this.loginContentHeight - this.loginLogoHeight)
  }

  // 键盘弹出后（页面缩到键盘上方、logo 为紧凑尺寸）主内容下方还剩的高度
  private keyboardFreeHeight(): number {
    const bodyInner = this.loginBodyHeight - this.keyHeight -
      CloudThemeToken.loginPageVerticalPadding - CloudThemeToken.spacingSection
    return bodyInner - this.contentNoLogoHeight - CloudThemeToken.loginLogoCompactWidth - CloudThemeToken.loginPageGap
  }

  private shouldShowFooterIcons(): boolean {
    return !this.isKeyboardVisible() || this.keyboardFreeHeight() >= this.footerIconsHeight
  }

  private shouldShowPrivacy(): boolean {
    return !this.isKeyboardVisible() ||
      this.keyboardFreeHeight() >= this.footerIconsHeight + CloudThemeToken.loginFooterGap + this.privacyHeight
  }

  // 底部两块的进出场：淡出时向下移出，键盘收起时从下方淡入回来
  private footerItemTransition(): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: CloudThemeToken.loginPrivacyExitOffsetY }))
      .animation({ duration: CloudThemeToken.loginTransitionDuration })
  }

  private requestOtpFocus(attempt: number = CloudThemeToken.zero): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(this.otpInputId)
      } catch (err) {
        if (attempt < CloudThemeToken.loginOtpFocusRetryCount) {
          this.requestOtpFocus(attempt + CloudThemeToken.lineWidth)
          return
        }
        AppLogger.error('LoginPage', `request OTP focus failed: ${(err as Error)?.message ?? err}`)
      }
    }, CloudThemeToken.loginOtpFocusDelayMs)
  }

  private focusInput(inputId: string): void {
    try {
      this.getUIContext().getFocusController().requestFocus(inputId)
    } catch (err) {
      AppLogger.warn('LoginPage', `request focus ${inputId} failed: ${(err as Error)?.message ?? err}`)
    }
  }

  // 网址校验通过后输入框才刚创建，延迟一帧再抓焦点，让外接键盘可以继续回车推进
  private focusLoginInputLater(): void {
    setTimeout(() => {
      this.focusInput(this.username.length === CloudThemeToken.zero ? this.usernameInputId : this.passwordInputId)
    }, CloudThemeToken.loginOtpFocusDelayMs)
  }

  aboutToAppear() {
    const uiContext = this.getUIContext();
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      return;
    }

    // 默认的键盘避让只保证获得焦点的输入框露出来，下面的登录按钮会被挡住一截（OTP 一步最明显）；
    // 登录页期间改为 RESIZE：页面缩到键盘上方，配合键盘弹出时缩小 logo，按钮始终完整可见。离开时在 aboutToDisappear 恢复
    uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);

    window.getLastWindow(hostContext).then(currentWindow => {
      // 设置窗口的布局为沉浸式布局
      try {
        currentWindow.setWindowLayoutFullScreen(true);
        // 页面出现时键盘可能已经弹着
        const avoidArea = currentWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
        this.keyHeight = uiContext.px2vp(avoidArea.bottomRect.height);

        // 监听软键盘的隐藏和显示；logo 缩放与底部区域显隐一起过渡
        this.avoidAreaListener = (data: window.AvoidAreaOptions) => {
          if (data.type == window.AvoidAreaType.TYPE_KEYBOARD) {
            uiContext.animateTo({ duration: CloudThemeToken.loginTransitionDuration, curve: Curve.EaseOut }, () => {
              this.keyHeight = uiContext.px2vp(data.area.bottomRect.height);
            });
          }
        };
        currentWindow.on('avoidAreaChange', this.avoidAreaListener);
        this.keyboardWindow = currentWindow;
      } catch (err) {
        AppLogger.error('LoginPage', `Window layout init failed: ${(err as Error)?.message ?? err}`)
      }
    }).catch((err: Error) => {
      AppLogger.error('LoginPage', `getLastWindow failed: ${err.message}`)
    })

    if (this.routeParam) {
      this.nextPage = this.routeParam.nextPage
      this.applyRouteLoginParam(this.routeParam)
      console.debug('LoginPage', `NextPage: ${this.nextPage}`)
    }
    this.refreshActiveUser()
    this.prefillActiveUserForRelogin()
  }

  aboutToDisappear(): void {
    // 键盘避让是整个窗口的设置，离开登录页恢复系统默认
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
    if (this.keyboardWindow && this.avoidAreaListener) {
      try {
        this.keyboardWindow.off('avoidAreaChange', this.avoidAreaListener)
      } catch (err) {
        AppLogger.warn('LoginPage', `off avoidAreaChange failed: ${(err as Error)?.message ?? err}`)
      }
    }
    this.keyboardWindow = undefined
    this.avoidAreaListener = undefined
  }

  private refreshActiveUser(): void {
    this.activeUserName = UserPrivData.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string
    this.activeUserUrl = UserPrivData.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string
  }

  private applyRouteLoginParam(param: LoginParam): void {
    if (param.url && param.url.length > 0) {
      this.applyStoredUrl(param.url)
    }
    if (param.username && param.username.length > 0) {
      this.username = param.username
    }
    this.password = ''
    // 站点与用户名都已知（凭证过期重登 / 接续拉起）：自动跑完网址校验这一步，
    // 直接停到密码输入，别让用户对着填好的网址再点一次“继续”
    if (!param.isAdd && this.address.length > 0 && this.username.length > 0) {
      this.websiteTest(false, true)
    }
  }

  private prefillActiveUserForRelogin(): void {
    if (this.routeParam?.isAdd || this.address.length > 0 || this.username.length > 0 ||
      this.activeUserName.length === 0) {
      return
    }
    const user = UserDatabase.getUserInfo(this.activeUserName, this.activeUserUrl)
    if (!user) {
      return
    }
    this.applyStoredUrl(user.url)
    this.username = user.username
    this.password = ''
    this.websiteTest(false)
  }

  private applyStoredUrl(url: string): void {
    const normalized = this.trimTrailingSlash(url)
    if (normalized.startsWith(Constant.PROTOCOL_HTTP_SCHEME)) {
      this.protocolIndex = Constant.PROTOCOL_HTTP_INDEX
      this.protocol = Constant.PROTOCOL_HTTP_SCHEME
      this.address = this.trimTrailingSlash(normalized.substring(Constant.PROTOCOL_HTTP_SCHEME.length))
      return
    }
    if (normalized.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) {
      this.protocolIndex = Constant.PROTOCOL_HTTPS_INDEX
      this.protocol = Constant.PROTOCOL_HTTPS_SCHEME
      this.address = this.trimTrailingSlash(normalized.substring(Constant.PROTOCOL_HTTPS_SCHEME.length))
      return
    }
    this.address = normalized
  }

  // 顶栏走 HdsNavigation 标题栏：返回键用 HDS 原生 backIcon（只在账号密码 / 两步验证步骤出现），
  // 在沉浸光感生效范围内，效果随设备档位由系统自适应；标题栏透明，登录内容版式不变
  build() {
    HdsNavigation() {
      this.loginBody()
    }
    .width("100%")
    .height("100%")
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideBackButton(!this.websiteInvalid)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: ' '
        },
        backIcon: {
          icon: $r('app.media.ic_back'),
          action: () => {
            this.onLoginBack()
          }
        },
        stackBuilder: () => {
          this.titleDragStrip()
        },
        divider: {
          showType: DividerShowType.OFF
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        },
        originalStyle: {
          contentStyle: {
            // 置透明露出 HDS 标题栏材质（效果随设备档位由系统自适应）；<26 实色
            backIconStyle: {
              backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.surfaceSubtle),
              iconColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      padding: {
        start: LengthMetrics.vp(CloudThemeToken.spacingPage),
        end: this.titleButtonInsetEnd > 0 ?
          LengthMetrics.vp(this.titleButtonInsetEnd + CloudThemeToken.spacingCard) : undefined
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindSheet($$this.showUserSwitchSheet, this.userSwitchSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      title: { title: '选择账号' },
      showClose: true,
      backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
      systemMaterial: CloudMaterial.sheetMaterial(),
      preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
      width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
      onDisappear: () => {
        this.showUserSwitchSheet = false
      }
    })
    .backgroundColor(CloudThemeToken.background)
  }

  private onLoginBack(): void {
    if (this.needs2FA) {
      this.needs2FA = false
    } else {
      this.loginTitle = $r('app.string.website_title')
      this.websiteInvalid = false
    }
  }

  // 2in1 隐藏系统标题栏后登录页没有其它可拖处：标题栏里返回键右侧整段作为窗口拖动带
  @Builder titleDragStrip() {
    Row() {
      Blank()
        .layoutWeight(1)
        .height('100%')
        .onTouch((event: TouchEvent) => {
          WindowMover.onTouch(event)
        })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: CloudThemeToken.spacingPage + CloudThemeToken.iconButtonSize + CloudThemeToken.spacingSection,
      right: this.titleButtonInsetEnd
    })
  }

  @Builder loginBody() {
    Stack({ alignContent: Alignment.Top }) {
      Row() {
        Column({ space: CloudThemeToken.loginPageGap }) {
        Column() {
          // 原返回键行，返回键已移到 HDS 标题栏；保留同高占位，登录内容版式不变
          Row()
            .height(CloudThemeToken.loginBackRowHeight)
            .margin({ top: CloudThemeToken.loginBackTopMargin })
            .width('100%')

          Column({ space: CloudThemeToken.loginContentGap }) {
            // 显示login及标题
            this.showLoginHeader()
            // 根据状态显示不同输入框
            if (!this.websiteInvalid) {
              this.showWebsiteInput()
            } else if (this.needs2FA) {
              this.showOtpInput()
            } else {
              this.showLoginInput()
            }
            // 继续按钮
            this.buttonContinue();
            // 提示
            if (!this.websiteInvalid) {
              Text($r("app.string.login_tips"))
                .fontSize(CloudThemeToken.loginTipsTextSize)
                .fontColor(CloudThemeToken.textSecondary)
                .margin({
                  left: CloudThemeToken.loginTipsHorizontalMargin,
                  right: CloudThemeToken.loginTipsHorizontalMargin
                })
            }
          }
          .width('100%')
        }
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.loginContentHeight = Number(newArea.height)
          this.updateContentNoLogoHeight()
        })

        // 键盘弹出时页面缩到键盘上方：底部两块按剩余空间决定显隐（各步骤内容高度、各机型键盘高度都不同），
        // 放得下就贴在键盘上方填掉空白，放不下就向下淡出收起
        Column({ space: CloudThemeToken.loginFooterGap }) {
          // 扫描添加及历史账户
          if (this.shouldShowFooterIcons()) {
            Column() {
              this.buttonScanAndUsers()
            }
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.footerIconsHeight = Number(newArea.height)
            })
            .transition(this.footerItemTransition())
          }

          // 隐私条款声明
          if (this.shouldShowPrivacy()) {
            Column() {
              this.privacyText()
            }
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.privacyHeight = Number(newArea.height)
            })
            .transition(this.footerItemTransition())
          }
        }
        // 固定整行宽：某一块收起时本列若随内容缩窄，正在淡出的那块会跟着重排，看起来像向右移出
        .width('100%')
        }
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          // 只记未弹键盘时的总高；弹键盘后的可用高按「总高 − 键盘高」推算，切换那一刻不会因测量滞后而闪一下
          if (!this.isKeyboardVisible()) {
            this.loginBodyHeight = Number(newArea.height)
          }
        })
        .height("100%")
        .width(this.sheetLayoutWidth >= CloudThemeToken.loginContentMaxWidth
          ? CloudThemeToken.loginContentMaxWidth
          : '100%')
        .padding({
          top: CloudThemeToken.loginPageVerticalPadding,
          left: CloudThemeToken.pagePadding,
          right: CloudThemeToken.pagePadding,
          // 键盘弹出时页面已缩到键盘上方，底部只留一道间隙，图标不贴着键盘
          bottom: this.isKeyboardVisible() ? CloudThemeToken.spacingSection
            : CloudThemeToken.loginPageVerticalPadding + this.bottomRectHeight
        })
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width("100%")
      .height("100%")
      .backgroundColor(CloudThemeToken.background)
      .justifyContent(FlexAlign.Center)
    }
    .width("100%")
    .height("100%")
  }

  private websiteTest(allowHttpFallback: boolean = false, focusNextStep: boolean = false) {
    if (this.address.length == CloudThemeToken.zero) {
      showToastTips('无效网站地址', ToastType.Error)
      return
    }
    CloudApi.init(this.protocol + this.address, {
      onSuccess: (_version) => {
        CloudApi.getSiteConfig({
          onSuccess: (data: SiteConfig) => {
            this.loginTitle = data.title
            this.websiteInvalid = true
            if (this.scanShouldAutoLogin && this.username.length > 0 && this.password.length > 0) {
              this.scanShouldAutoLogin = false
              showToastTips('已识别账号密码，正在登录', ToastType.Info)
              this.login()
              return
            }
            if (focusNextStep) {
              this.focusLoginInputLater()
            }
          },
          onFailure: (msg) => {
            console.debug('LoginPage', '站点获取配置失败 错误信息:', msg)
            if (this.retryWebsiteTestWithHttp(allowHttpFallback, focusNextStep)) {
              return
            }
            showToastTips('站点获取配置失败', ToastType.Error)
          }
        })
      },
      onFailure: (msg) => {
        console.debug('LoginPage', '站点请求失败 错误信息:', msg)
        if (this.retryWebsiteTestWithHttp(allowHttpFallback, focusNextStep)) {
          return
        }
        showToastTips('站点请求失败', ToastType.Error)
      }
    })
  }

  private retryWebsiteTestWithHttp(allowHttpFallback: boolean, focusNextStep: boolean): boolean {
    if (!allowHttpFallback || this.protocol !== Constant.PROTOCOL_HTTPS_SCHEME) {
      return false
    }
    this.protocolIndex = Constant.PROTOCOL_HTTP_INDEX
    this.protocol = Constant.PROTOCOL_HTTP_SCHEME
    this.websiteTest(false, focusNextStep)
    return true
  }

  private saveUserAndNavigate(data: UserInfo): void {
    // Read directly from AppStorage — @StorageProp updates asynchronously (next render frame),
    // so this.cookie/cookieExpires would still hold stale values here.
    const cookie = AppStorage.get<string>(Constant.CLOUD_COOKIE) ?? ''
    const cookieExpires = AppStorage.get<string>(Constant.CLOUD_COOKIE_EXPIRES) ?? ''
    const refreshToken = AppStorage.get<string>(Constant.CLOUD_REFRESH_TOKEN) ?? ''
    let dbUserInfo: DbUserInfo = {
      url: this.protocol + this.address,
      username: this.username,
      password: '',
      cookie: cookie,
      expires: cookieExpires,
      refresh_token: refreshToken,
      userinfo: data
    }
    ActiveAccount.apply(this.username, dbUserInfo.url)
    UserDatabase.insertUserInfo(dbUserInfo)
    AvatarUtil.refreshDbUserAvatar(dbUserInfo).catch((err: Error) => {
      AppLogger.warn('LoginPage', `refresh avatar cache failed: ${err.message}`)
    })
    CloudRouter.goAfterLogin(this.nextPage ?? Constant.HOME_PAGE)
  }

  private async startScanLogin(): Promise<void> {
    if (!this.requirePrivacyAccepted(() => {
      this.startScanLogin()
    })) {
      return
    }
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      showToastTips('扫码失败，无法获取上下文', ToastType.Error)
      return
    }

    AppLogger.info('LoginPage', 'scan start')
    try {
      const result = await scanBarcode.startScanForResult(hostContext, {
        enableAlbum: true,
        enableMultiMode: false
      })
      AppLogger.info('LoginPage', 'scan captured')
      this.applyScannedAddress(result.originalValue)
    } catch (err) {
      const error = err as BusinessError
      if (error.code === Constant.SCAN_CANCEL_CODE) {
        return
      }
      AppLogger.error('LoginPage', `scan failed: ${error.code}, ${error.message}`)
      showToastTips('扫码失败', ToastType.Error)
    }
  }

  private applyScannedAddress(value: string): void {
    const scanData = this.parseScannedLoginData(value)
    const address = scanData.address
    if (address.length === 0) {
      showToastTips(`未识别到有效站点地址：${this.buildScanSummary(value)}`, ToastType.Warn,
        Constant.TOAST_TIPS_DEFAULT_DURATION_MS)
      return
    }

    const hasProtocol = this.applyScannedSiteAddress(address)
    this.websiteInvalid = false
    this.needs2FA = false
    this.loginTitle = $r('app.string.website_title')

    if (scanData.refreshToken.length > 0) {
      this.loginWithRefreshToken(this.protocol + this.address, scanData.refreshToken)
      return
    }

    if (scanData.username.length > 0) {
      this.username = scanData.username
    }
    if (scanData.password.length > 0) {
      this.password = scanData.password
    }
    this.scanShouldAutoLogin = this.username.length > 0 && this.password.length > 0
    if (!this.scanShouldAutoLogin) {
      showToastTips(`已识别站点，二维码${this.buildMissingCredentialText(scanData)}`, ToastType.Info,
        Constant.TOAST_TIPS_DEFAULT_DURATION_MS)
    }

    this.websiteTest(!hasProtocol)
  }

  private applyScannedSiteAddress(address: string): boolean {
    const hasProtocol = address.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
      address.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)
    if (address.startsWith(Constant.PROTOCOL_HTTP_SCHEME)) {
      this.protocolIndex = Constant.PROTOCOL_HTTP_INDEX
      this.protocol = Constant.PROTOCOL_HTTP_SCHEME
      this.address = this.trimTrailingSlash(address.substring(Constant.PROTOCOL_HTTP_SCHEME.length))
    } else if (address.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) {
      this.protocolIndex = Constant.PROTOCOL_HTTPS_INDEX
      this.protocol = Constant.PROTOCOL_HTTPS_SCHEME
      this.address = this.trimTrailingSlash(address.substring(Constant.PROTOCOL_HTTPS_SCHEME.length))
    } else {
      this.address = this.trimTrailingSlash(address)
    }
    return hasProtocol
  }

  private parseScannedLoginData(value: string): ScannedLoginData {
    const scanned = value.trim()
    const data = new ScannedLoginData()
    if (scanned.length === 0) {
      return data
    }

    this.applyJsonLoginData(scanned, data)
    this.applyQueryLoginData(scanned, data)
    this.applyKeyValueLoginData(scanned, data)
    const addressWithoutUserInfo = this.applyUrlUserInfoLoginData(scanned, data)
    if (data.address.length === 0) {
      data.address = this.normalizeScannedAddress(addressWithoutUserInfo.length > 0 ? addressWithoutUserInfo : scanned)
    } else {
      data.address = this.normalizeScannedAddress(data.address)
    }
    return data
  }

  private normalizeScannedAddress(value: string): string {
    const scanned = value.trim()
    if (scanned.length === 0) {
      return ''
    }

    const jsonUrl = this.extractUrlFromJson(scanned)
    if (jsonUrl.length > 0) {
      return this.normalizeScannedAddress(jsonUrl)
    }

    const queryUrl = this.extractUrlFromQuery(scanned)
    if (queryUrl.length > 0) {
      return this.normalizeScannedAddress(queryUrl)
    }

    const match = scanned.match(/https?:\/\/[^\s"'<>]+/)
    if (match && match.length > 0) {
      return this.normalizeBaseAddress(match[0])
    }

    const domainMatch = scanned.match(/([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(:\d+)?(\/[^\s"'<>]*)?/)
    if (domainMatch && domainMatch.length > 0) {
      return this.normalizeBaseAddress(domainMatch[0])
    }
    return ''
  }

  private applyJsonLoginData(value: string, data: ScannedLoginData): void {
    if (!value.startsWith('{') || !value.endsWith('}')) {
      return
    }
    try {
      const json = JSON.parse(value) as Record<string, Object>
      this.applyJsonFields(json, data)
      const nested = json.data as Record<string, Object>
      if (nested) {
        this.applyJsonFields(nested, data)
      }
    } catch (_) {
    }
  }

  private applyJsonFields(json: Record<string, Object>, data: ScannedLoginData): void {
    const address = this.readJsonString(json, ['url', 'site', 'server', 'baseUrl', 'base_url', 'endpoint', 'host', 'address'])
    const username = this.readJsonString(json, ['username', 'user', 'account', 'email', 'mail', 'login'])
    const password = this.readJsonString(json, ['password', 'pass', 'pwd'])
    const refreshToken = this.readJsonString(json, ['refresh_token', 'refreshToken'])
    if (address.length > 0 && data.address.length === 0) {
      data.address = address
    }
    if (username.length > 0 && data.username.length === 0) {
      data.username = username
    }
    if (password.length > 0 && data.password.length === 0) {
      data.password = password
    }
    if (refreshToken.length > 0 && data.refreshToken.length === 0) {
      data.refreshToken = refreshToken
    }
  }

  private readJsonString(json: Record<string, Object>, keys: string[]): string {
    for (let index = 0; index < keys.length; index++) {
      const value = json[keys[index]]
      if (typeof value === 'string' && value.length > 0) {
        return value
      }
      if (typeof value === 'number') {
        return `${value}`
      }
    }
    return ''
  }

  private applyQueryLoginData(value: string, data: ScannedLoginData): void {
    const queryIndex = value.indexOf('?')
    if (queryIndex < 0 || queryIndex >= value.length - 1) {
      return
    }
    const query = value.substring(queryIndex + 1)
    const params = query.split('&')
    params.forEach((item: string) => {
      const pair = item.split('=')
      if (pair.length < 2) {
        return
      }
      const key = pair[0].toLowerCase()
      const val = this.safeDecode(pair.slice(1).join('='))
      if (['url', 'site', 'server', 'baseurl', 'base_url', 'endpoint', 'host', 'address'].includes(key) &&
        data.address.length === 0) {
        data.address = val
      } else if (['username', 'user', 'account', 'email', 'mail', 'login', 'loginname'].includes(key) &&
        data.username.length === 0) {
        data.username = val
      } else if (['password', 'pass', 'pwd', 'passwd'].includes(key) && data.password.length === 0) {
        data.password = val
      } else if (['refresh_token', 'refreshtoken'].includes(key) && data.refreshToken.length === 0) {
        data.refreshToken = val
      }
    })
  }

  private applyKeyValueLoginData(value: string, data: ScannedLoginData): void {
    if (data.username.length === 0) {
      data.username = this.extractKeyValue(value, '(username|user|account|email|mail|login)')
    }
    if (data.password.length === 0) {
      data.password = this.extractKeyValue(value, '(password|pass|pwd)')
    }
    if (data.refreshToken.length === 0) {
      data.refreshToken = this.extractKeyValue(value, '(refresh_token|refreshToken)')
    }
    if (data.address.length === 0) {
      data.address = this.extractKeyValue(value, '(url|site|server|baseUrl|base_url|endpoint|host|address)')
    }
  }

  private extractKeyValue(value: string, keyPattern: string): string {
    const regex = new RegExp(`(?:^|[\\s,;])${keyPattern}\\s*[:=：]\\s*([^\\s,;]+)`, 'i')
    const match = value.match(regex)
    if (!match || match.length < 3) {
      return ''
    }
    return this.safeDecode(match[2])
  }

  private applyUrlUserInfoLoginData(value: string, data: ScannedLoginData): string {
    const match = value.match(/^(https?:\/\/)([^\/:@?#\s]+):([^\/@?#\s]+)@([^\/?#\s]+)([\/?#].*)?$/)
    if (!match || match.length < 5) {
      return ''
    }
    if (data.username.length === 0) {
      data.username = this.safeDecode(match[2])
    }
    if (data.password.length === 0) {
      data.password = this.safeDecode(match[3])
    }
    return `${match[1]}${match[4]}`
  }

  private safeDecode(value: string): string {
    try {
      return decodeURIComponent(value.replace(/\+/g, ' '))
    } catch (_) {
      return value
    }
  }

  private extractUrlFromJson(value: string): string {
    if (!value.startsWith('{') || !value.endsWith('}')) {
      return ''
    }
    try {
      const data = JSON.parse(value) as Record<string, string>
      return data.url ?? data.site ?? data.server ?? data.baseUrl ?? data.base_url ?? data.endpoint ?? data.host ?? ''
    } catch (_) {
      return ''
    }
  }

  private extractUrlFromQuery(value: string): string {
    const match = value.match(/[?&](url|site|server|baseUrl|base_url|endpoint|host)=([^&\s]+)/)
    if (!match || match.length < 3) {
      return ''
    }
    try {
      return decodeURIComponent(match[2])
    } catch (_) {
      return match[2]
    }
  }

  private normalizeBaseAddress(value: string): string {
    let result = value.trim()
    while (result.endsWith('/') || result.endsWith(',') || result.endsWith(')')) {
      result = result.substring(0, result.length - 1)
    }

    const protocolMatch = result.match(/^(https?:\/\/[^\/?#]+)/)
    if (protocolMatch && protocolMatch.length > 0) {
      return protocolMatch[0]
    }

    const hostMatch = result.match(/^([^\/?#]+)/)
    return hostMatch && hostMatch.length > 0 ? hostMatch[0] : ''
  }

  private buildMissingCredentialText(data: ScannedLoginData): string {
    if (data.username.length > 0 && data.password.length === 0) {
      return '未包含密码'
    }
    if (data.username.length === 0 && data.password.length > 0) {
      return '未包含账号'
    }
    return '未包含账号密码'
  }

  private buildScanSummary(value: string): string {
    const redacted = this.redactScanText(value.trim())
    if (redacted.length === 0) {
      return '空内容'
    }
    const previewLength = 80
    const preview = redacted.length > previewLength ? `${redacted.substring(0, previewLength)}...` : redacted
    return `${this.detectScanPayloadType(value)} ${preview}`
  }

  private detectScanPayloadType(value: string): string {
    const scanned = value.trim()
    if (scanned.startsWith('{') && scanned.endsWith('}')) {
      return 'JSON'
    }
    if (scanned.startsWith(Constant.PROTOCOL_HTTP_SCHEME) || scanned.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) {
      return 'URL'
    }
    if (scanned.indexOf('://') > 0) {
      return 'URI'
    }
    return 'TEXT'
  }

  private redactScanText(value: string): string {
    let result = value
    result = result.replace(/([?&](password|pass|pwd|passwd|token|access_token|refresh_token|code)=)[^&\s]+/ig, '$1***')
    result = result.replace(/((password|pass|pwd|passwd|token|access_token|refresh_token|code)\s*[:=：]\s*)[^\s,;&"}]+/ig,
      '$1***')
    result = result.replace(/(https?:\/\/)([^\/:@?#\s]+):([^\/@?#\s]+)@/ig, '$1$2:***@')
    return result
  }

  private loginWithRefreshToken(baseUrl: string, refreshToken: string): void {
    showToastTips('已识别扫码登录令牌，正在登录', ToastType.Info)
    CloudApi.loginWithRefreshToken(baseUrl, refreshToken, {
      onSuccess: (data: UserInfo) => {
        const userInfo = this.normalizeScannedUserInfo(data)
        this.username = this.getScannedUserName(userInfo)
        this.password = ''
        if (this.username.length === 0) {
          this.username = 'scan-login'
        }
        this.saveUserAndNavigate(userInfo)
      },
      onFailure: (msg: string) => {
        AppLogger.error('LoginPage', `scan refresh login failed: ${msg}`)
        showToastTips('扫码登录失败，请重新扫码或使用账号密码登录', ToastType.Error)
      }
    })
  }

  private normalizeScannedUserInfo(raw?: UserInfo): UserInfo {
    if (!raw) {
      return this.createScannedUserInfo()
    }
    const source = raw as ScanUserLike
    const group = source.group ?? {}
    const userName = source.user_name ?? source.email ?? source.nickname ?? source.id ?? ''
    const nickname = source.nickname ?? source.user_name ?? source.email ?? source.id ?? ''
    return {
      id: source.id ?? '',
      user_name: userName,
      nickname: nickname,
      status: typeof source.status === 'number' ? source.status : 0,
      avatar: typeof source.avatar === 'string' ? source.avatar : '',
      created_at: source.created_at ?? '',
      preferred_theme: source.preferred_theme ?? '',
      anonymous: source.anonymous ?? false,
      group: {
        id: group.id ?? '',
        name: group.name ?? '',
        allowShare: group.allowShare ?? false,
        allowRemoteDownload: group.allowRemoteDownload ?? false,
        allowArchiveDownload: group.allowArchiveDownload ?? false,
        shareDownload: group.shareDownload ?? false,
        compress: group.compress ?? false,
        webdav: group.webdav ?? false,
        sourceBatch: group.sourceBatch ?? 0,
        advanceDelete: group.advanceDelete ?? false,
        allowWebDAVProxy: group.allowWebDAVProxy ?? false
      }
    }
  }

  private getScannedUserName(userInfo: UserInfo): string {
    return userInfo.user_name.length > 0 ? userInfo.user_name :
      (userInfo.nickname.length > 0 ? userInfo.nickname : userInfo.id)
  }

  private createScannedUserInfo(): UserInfo {
    return {
      id: '',
      user_name: '',
      nickname: '',
      status: 0,
      avatar: '',
      created_at: '',
      preferred_theme: '',
      anonymous: false,
      group: {
        id: '',
        name: '',
        allowShare: false,
        allowRemoteDownload: false,
        allowArchiveDownload: false,
        shareDownload: false,
        compress: false,
        webdav: false,
        sourceBatch: 0,
        advanceDelete: false,
        allowWebDAVProxy: false
      }
    }
  }

  private trimTrailingSlash(value: string): string {
    let result = value
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1)
    }
    return result
  }

  private login() {
    if (this.username.length == CloudThemeToken.zero || this.password.length == CloudThemeToken.zero) {
      showToastTips('无效用户名或密码', ToastType.Error)
      return
    }
    const twoFactorCb: TwoFactorCallback = {
      onTwoFactorRequired: () => {
        this.needs2FA = true
        this.otpCode = ''
        this.requestOtpFocus()
      }
    }
    CloudApi.login(this.username, this.password, {
      onSuccess: (data: UserInfo) => {
        this.saveUserAndNavigate(data)
      },
      onFailure: (msg: string) => {
        console.debug('LoginPage', '登录失败 错误信息:', msg)
        showToastTips('登录失败，请检查用户邮箱及密码', ToastType.Error);
      }
    }, twoFactorCb)
  }

  private submitOtp() {
    if (this.otpCode.length != CloudThemeToken.loginOtpLength) {
      showToastTips(`请输入${CloudThemeToken.loginOtpLength}位验证码`, ToastType.Error)
      return
    }
    CloudApi.login2fa(this.otpCode, {
      onSuccess: (data: UserInfo) => {
        this.needs2FA = false
        this.saveUserAndNavigate(data)
      },
      onFailure: (msg: string) => {
        console.debug('LoginPage', '2FA验证失败 错误信息:', msg)
        showToastTips('验证码错误，请重试', ToastType.Error);
        this.otpCode = ''
        this.requestOtpFocus()
      }
    })
  }

  @Builder showLoginHeader() {
    Image(this.websiteLogo)
      .draggable(false)
      // 键盘弹出时缩小，给输入框和登录按钮让出高度
      .width(this.isKeyboardVisible() ? CloudThemeToken.loginLogoCompactWidth : CloudThemeToken.loginLogoWidth)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.loginLogoHeight = Number(newArea.height)
        this.updateContentNoLogoHeight()
      })

    Text(this.loginTitle)
      .fontSize(CloudThemeToken.loginTitleSize)
      .fontWeight(FontWeight.Bold)
      .fontColor(CloudThemeToken.textPrimary)
      .maxLines(2)
      .textAlign(TextAlign.Center)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder buttonContinue() {
    Button($r("app.string.login_continue"))
      .margin({ top: CloudThemeToken.loginContinueTopMargin })
      .height(CloudThemeToken.inputHeight)
      .width("100%")
      .borderRadius(CloudThemeToken.controlRadius)
      .backgroundColor(CloudThemeToken.primary)
      .fontColor(CloudThemeToken.onPrimary)
      .onClick(() => {
        this.submitLoginStep()
      })
  }

  @Builder protocolMenu() {
    Menu() {
      MenuItem({ content: Constant.PROTOCOL_HTTPS_LABEL })
        .selectIcon(true)
        .selected(this.protocolIndex === Constant.PROTOCOL_HTTPS_INDEX)
        .onClick(() => {
          this.protocolIndex = Constant.PROTOCOL_HTTPS_INDEX
          this.protocol = Constant.PROTOCOL_HTTPS_SCHEME
        })
      MenuItem({ content: Constant.PROTOCOL_HTTP_LABEL })
        .selectIcon(true)
        .selected(this.protocolIndex === Constant.PROTOCOL_HTTP_INDEX)
        .onClick(() => {
          this.protocolIndex = Constant.PROTOCOL_HTTP_INDEX
          this.protocol = Constant.PROTOCOL_HTTP_SCHEME
        })
    }
    .width(CloudThemeToken.loginProtocolMenuWidth)
    .menuItemDivider({ strokeWidth: LengthMetrics.px(CloudThemeToken.loginProtocolDividerWidthPx),
      color: CloudThemeToken.line })
  }

  @Styles loginTextInputStyle() {
    .borderRadius(CloudThemeToken.inputInnerRadius)
    .layoutWeight(1)
    .padding(CloudThemeToken.zero)
    .backgroundColor(CloudThemeToken.transparent)
  }

  @Builder showWebsiteInput() {
    Row() {
      Image($r("app.media.ic_login_globe"))
        .width(CloudThemeToken.loginInputIconSize)
        .margin({
          left: CloudThemeToken.loginWebsiteIconHorizontalMargin,
          right: CloudThemeToken.loginWebsiteIconHorizontalMargin
        })
        .fillColor(CloudThemeToken.textSecondary)
        .draggable(false)

      Text(this.protocol)
        .fontColor(CloudThemeToken.textSecondary)
        .textAlign(TextAlign.Center)
        .bindMenu(this.protocolMenu)

      TextInput({ placeholder: $r("app.string.login_address"), text: this.address })
        .loginTextInputStyle()
        .fontColor(CloudThemeToken.textPrimary)
        .placeholderColor(CloudThemeToken.textSecondary)
        .enterKeyType(EnterKeyType.Next)
        .onChange((value) => {
          this.address = value
        })
        .onSubmit(() => {
          this.submitLoginStep()
        })
    }
    .rowCommonStyle()
  }

  @Builder showOtpInput() {
    Column({ space: CloudThemeToken.loginOtpGap }) {
      Text('请输入身份验证器中的6位验证码')
        .fontSize(CloudThemeToken.loginOtpHintSize)
        .fontColor(CloudThemeToken.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)

      OtpInput({
        code: $otpCode,
        inputId: this.otpInputId,
        onComplete: () => {
          this.submitOtp()
        }
      })
    }
  }

  @Builder showLoginInput() {
    Column({ space: CloudThemeToken.loginInputGroupGap }) {
      // 用户名
      Row() {
        Image($r("app.media.ic_login_mail"))
          .width(CloudThemeToken.loginInputIconSize)
          .margin({
            left: CloudThemeToken.loginInputIconHorizontalMargin,
            right: CloudThemeToken.loginInputIconHorizontalMargin
          })
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)

        TextInput({ placeholder: $r("app.string.login_user"), text: this.username })
          .id(this.usernameInputId)
          .loginTextInputStyle()
          .fontColor(CloudThemeToken.textPrimary)
          .placeholderColor(CloudThemeToken.textSecondary)
          .enterKeyType(EnterKeyType.Next)
          .onChange((value) => {
            this.username = value
          })
          .onSubmit(() => {
            if (this.password.length === CloudThemeToken.zero) {
              this.focusInput(this.passwordInputId)
              return
            }
            this.submitLoginStep()
          })
      }
      .rowCommonStyle()

      // 密码
      Row() {
        Image($r("app.media.ic_login_lock"))
          .width(CloudThemeToken.loginInputIconSize)
          .margin({
            left: CloudThemeToken.loginInputIconHorizontalMargin,
            right: CloudThemeToken.loginInputIconHorizontalMargin
          })
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)

        TextInput({ placeholder: $r("app.string.login_password"), text: this.password })
          .id(this.passwordInputId)
          .type(InputType.Password)
          .loginTextInputStyle()
          .fontColor(CloudThemeToken.textPrimary)
          .placeholderColor(CloudThemeToken.textSecondary)
          .enterKeyType(EnterKeyType.Go)
          .onChange((value) => {
            this.password = value
          })
          .onSubmit(() => {
            this.submitLoginStep()
          })
      }
      .rowCommonStyle()
      .transition(TransitionEffect.OPACITY.animation({ duration: CloudThemeToken.loginTransitionDuration })
        .combine(TransitionEffect.translate({ y: CloudThemeToken.loginPasswordTransitionOffsetY })
          .animation({ duration: CloudThemeToken.loginTransitionDuration })))
    }
    .transition(TransitionEffect.asymmetric(undefined,
      TransitionEffect.OPACITY.animation({ duration: CloudThemeToken.loginInputDisappearDuration })))
  }

  // 底部入口：与我的页同一套线性图标，不加底色，下方配文字说明用途
  @Builder footerEntry(icon: Resource, label: string, onAction: () => void) {
    Column({ space: CloudThemeToken.loginFooterLabelGap }) {
      Image(icon)
        .width(CloudThemeToken.loginFooterIconSize)
        .height(CloudThemeToken.loginFooterIconSize)
        .fillColor(CloudThemeToken.textPrimary)
        .draggable(false)
      Text(label)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
    }
    .padding(CloudThemeToken.loginFooterItemPadding)
    .borderRadius(CloudThemeToken.controlRadius)
    .alignItems(HorizontalAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .accessibilityText(label)
    .onClick(() => onAction())
  }

  @Builder buttonScanAndUsers() {
    Row({ space: CloudThemeToken.loginFooterButtonGap }) {
      this.footerEntry($r("app.media.ic_login_scan"), '扫码登录', () => {
        this.startScanLogin()
      })

      this.footerEntry($r("app.media.ic_mine_switch_account"), '已保存账号', () => {
        this.refreshActiveUser()
        this.showUserSwitchSheet = true
      })
    }
  }

  @Builder userSwitchSheet() {
    UserSwitchSheet({
      currentUser: this.activeUserName,
      currentUrl: this.activeUserUrl,
      onSelect: (user: DbUserInfo) => {
        if (!this.requirePrivacyAccepted(() => {
          this.switchToSelectedUser(user)
        })) {
          this.showUserSwitchSheet = false
          return
        }
        this.switchToSelectedUser(user)
      },
      onClose: () => {
        this.showUserSwitchSheet = false
      }
    })
  }

  @Builder privacyText() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
      Checkbox({ name: 'login_privacy', group: 'login' })
        .select(this.privacyAccepted)
        .selectedColor(CloudThemeToken.primary)
        .width(CloudThemeToken.loginPrivacyCheckboxSize)
        .height(CloudThemeToken.loginPrivacyCheckboxSize)
        .margin({ right: CloudThemeToken.loginPrivacyCheckboxGap })
        .onChange((value: boolean) => {
          this.privacyAccepted = value
        })

      Text($r('app.string.login_service_prefix'))
        .fontSize(CloudThemeToken.loginPrivacyTextSize)
        .fontColor(CloudThemeToken.textSecondary)
        .onClick(() => {
          this.privacyAccepted = !this.privacyAccepted
        })

      Hyperlink(Constant.PRIVACY_POLICY_URL, $r("app.string.hyperlink_app_privacy")) {
      }
      .color(CloudThemeToken.primary)
      .height(CloudThemeToken.loginPrivacyLinkHeight)
    }
    .width("100%")
  }

  private continueLoginStep(): void {
    if (!this.websiteInvalid) {
      this.websiteTest(false, true)
    } else if (this.needs2FA) {
      this.submitOtp()
    } else {
      this.login()
    }
  }

  // 继续按钮点击与输入框回车共用：先过隐私确认，再推进当前登录步骤
  private submitLoginStep(): void {
    if (!this.requirePrivacyAccepted(() => {
      this.continueLoginStep()
    })) {
      return
    }
    this.continueLoginStep()
  }

  private switchToSelectedUser(user: DbUserInfo): void {
    // 过期账号会重新渲染登录页并预填，先关 sheet 避免它盖在上面
    if (CloudRouter.switchToUser(user.username, user.url, () => { this.showUserSwitchSheet = false })) {
      this.showUserSwitchSheet = false
      CloudRouter.goAfterLogin(this.nextPage ?? Constant.HOME_PAGE)
    }
  }

  private requirePrivacyAccepted(onAgree: () => void): boolean {
    if (this.privacyAccepted) {
      return true
    }
    this.pendingPrivacyAgree = onAgree
    this.privacyDialogController.open()
    return false
  }

  private openPrivacyPolicy(): void {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      showToastTips('无法打开链接', ToastType.Error)
      return
    }
    (hostContext as common.UIAbilityContext).startAbility({
      action: 'ohos.want.action.viewData',
      uri: Constant.PRIVACY_POLICY_URL,
      entities: ['entity.system.browsable']
    }).catch((err: BusinessError) => {
      AppLogger.error('LoginPage', `open privacy policy failed: ${err.code}, ${err.message}`)
      showToastTips('无法打开浏览器', ToastType.Error)
    })
  }
}
