import { LengthMetrics, window } from '@kit.ArkUI'
import { DbUserInfo, SiteConfig, UserInfo, TwoFactorCallback } from '../model/net/ApiTypes';
import { showToastTips, ToastType } from '../utils/ToastUtil';
import Constant from '../model/Constant';
import UserPrivData from '../model/UserPreferences';
import UserDatabase from '../model/UserDatabase';
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { LoginParam } from '../model/net/LoginParam';
import { CloudApi } from '../model/net/CloudApi';
import { image } from '@kit.ImageKit';
import { CloudThemeToken } from '../model/CloudTheme';

@Extend(Row)
function rowCommonStyle() {
  .borderRadius(CloudThemeToken.cardRadius)
  .backgroundColor(CloudThemeToken.surface)
  .width('100%')
  .height(CloudThemeToken.inputHeight)
  .alignItems(VerticalAlign.Center)
}

function buildOtpIndexes(): number[] {
  const indexes: number[] = []
  for (let index = 0; index < CloudThemeToken.loginOtpLength; index++) {
    indexes.push(index)
  }
  return indexes
}

@HMRouter({pageUrl: Constant.LOGIN_PAGE, singleton: true})
@Component
export struct LoginPage {
  @StorageProp(Constant.CLOUD_COOKIE) cookie: string = '';
  @StorageProp(Constant.CLOUD_COOKIE_EXPIRES) cookieExpires: string = '';
  @State protocolIndex: number = 0
  @State protocol: string = 'https://'
  @State scrollHeight: number = 0;
  @State keyHeight: number = 0;
  @State websiteInvalid: boolean = false;
  @State loginInvalid: boolean = false;
  @State needs2FA: boolean = false;
  @State loginTitle: string|Resource = $r('app.string.website_title');
  @State websiteLogo: Resource|PixelMap = $r('app.media.cloudrs')

  private address: string = ''
  private username: string = ''
  private password: string = ''
  @State private otpCode: string = ''
  scroller: Scroller = new Scroller();
  private nextPage: string|null = Constant.HOME_PAGE
  private readonly otpIndexes: number[] = buildOtpIndexes()
  private readonly otpInputId: string = 'loginOtpInput'

  private requestOtpFocus(attempt: number = CloudThemeToken.zero): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(this.otpInputId)
      } catch (err) {
        if (attempt < CloudThemeToken.loginOtpFocusRetryCount) {
          this.requestOtpFocus(attempt + CloudThemeToken.lineWidth)
          return
        }
        console.error('LoginPage', `request OTP focus failed: ${(err as Error)?.message ?? err}`)
      }
    }, CloudThemeToken.loginOtpFocusDelayMs)
  }

  aboutToAppear() {
    const uiContext = this.getUIContext();
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      return;
    }

    window.getLastWindow(hostContext).then(currentWindow => {
      // 设置窗口的布局为沉浸式布局
      try {
        currentWindow.setWindowLayoutFullScreen(true);
        let property = currentWindow.getWindowProperties();

        // 初始化窗口高度
        let avoidArea = currentWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
        this.scrollHeight = uiContext.px2vp(property.windowRect.height - avoidArea.bottomRect.height);

        // 监听软键盘的隐藏和显示
        currentWindow.on('avoidAreaChange', data => {
          if (data.type == window.AvoidAreaType.TYPE_KEYBOARD) {
            this.keyHeight = uiContext.px2vp(data.area.bottomRect.height);
            this.scrollHeight = uiContext.px2vp(currentWindow.getWindowProperties().windowRect.height - data.area.bottomRect.height);
            return;
          }
        })
      } catch (err) {
        console.error('LoginPage', `Window layout init failed: ${(err as Error)?.message ?? err}`)
      }
    }).catch((err: Error) => {
      console.error('LoginPage', `getLastWindow failed: ${err.message}`)
    })

    if (HMRouterMgr.getCurrentParam()) {
      this.nextPage = (HMRouterMgr.getCurrentParam() as LoginParam).nextPage
      console.debug('LoginPage', `NextPage: ${this.nextPage}`)
    }
  }

  build() {
    Column({ space: CloudThemeToken.loginPageGap }) {
      Column() {
        Row() {
          Button() {
            Image($r('app.media.ic_arrow_left_circle'))
              .fillColor(CloudThemeToken.textSecondary)
          }
          .width(CloudThemeToken.smallIconButtonSize)
          .height(CloudThemeToken.smallIconButtonSize)
          .backgroundColor(CloudThemeToken.surface)
          .borderRadius(CloudThemeToken.controlRadius)
          .onClick(() => {
            if (this.needs2FA) {
              this.needs2FA = false
            } else {
              this.loginTitle = $r('app.string.website_title')
              this.websiteInvalid = false
            }
          })
        }
        .height(CloudThemeToken.loginBackRowHeight)
        .margin({ top: CloudThemeToken.loginBackTopMargin })
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .visibility(this.websiteInvalid ? Visibility.Visible : Visibility.Hidden)
        .animation({ duration: CloudThemeToken.loginTransitionDuration })

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

      Column({ space: CloudThemeToken.loginFooterGap }) {
        // 扫描添加及历史账户
        this.buttonScanAndUsers()

        // 隐私条款声明
        this.privacyText()
      }
    }
    .height("100%")
    .padding({
      top: CloudThemeToken.loginPageVerticalPadding,
      left: CloudThemeToken.pagePadding,
      right: CloudThemeToken.pagePadding,
      bottom: this.keyHeight ? CloudThemeToken.zero : CloudThemeToken.loginPageVerticalPadding
    })
    .backgroundColor(CloudThemeToken.background)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  private websiteTest() {
    if (this.address.length == 0) {
      showToastTips('无效网站地址', ToastType.Error)
      return
    }
    CloudApi.init(this.protocol + this.address, {
      onSuccess: (_version) => {
        CloudApi.getSiteConfig({
          onSuccess: (data: SiteConfig) => {
            this.loginTitle = data.title
            this.websiteInvalid = true
          },
          onFailure: (msg) => {
            console.debug('LoginPage', '站点获取配置失败 错误信息:', msg)
            showToastTips('站点获取配置失败', ToastType.Error)
          }
        })
      },
      onFailure: (msg) => {
        console.debug('LoginPage', '站点请求失败 错误信息:', msg)
        showToastTips('站点请求失败', ToastType.Error)
      }
    })
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
      password: this.password,
      cookie: cookie,
      expires: cookieExpires,
      refresh_token: refreshToken,
      userinfo: data
    }
    UserPrivData.putSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, this.username)
    UserDatabase.insertUserInfo(dbUserInfo)
    HMRouterMgr.push({pageUrl: this.nextPage ?? Constant.HOME_PAGE})
  }

  private login() {
    if (this.username.length == 0 || this.password.length == 0) {
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
      .width(CloudThemeToken.loginLogoWidth)

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
        if (!this.websiteInvalid) {
          this.websiteTest()
        } else if (this.needs2FA) {
          this.submitOtp()
        } else {
          this.login()
        }
      })
  }

  @Builder protocolMenu() {
    Menu() {
      MenuItem({ content: 'https' })
        .selectIcon(true)
        .selected(this.protocolIndex === 0)
        .onClick(() => {
          this.protocolIndex = 0
          this.protocol = 'https://'
        })
      MenuItem({ content: 'http' })
        .selectIcon(true)
        .selected(this.protocolIndex === 1)
        .onClick(() => {
          this.protocolIndex = 1
          this.protocol = 'http://'
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
      Image($r("app.media.ic_worldclock_fill"))
        .width(CloudThemeToken.loginInputIconSize)
        .margin({
          left: CloudThemeToken.loginWebsiteIconHorizontalMargin,
          right: CloudThemeToken.loginWebsiteIconHorizontalMargin
        })
        .fillColor(CloudThemeToken.primary)

      Text(this.protocol)
        .fontColor(CloudThemeToken.textSecondary)
        .textAlign(TextAlign.Center)
        .bindMenu(this.protocolMenu)

      TextInput({ placeholder: $r("app.string.login_address"), text: this.address })
        .loginTextInputStyle()
        .fontColor(CloudThemeToken.textPrimary)
        .placeholderColor(CloudThemeToken.textSecondary)
        .onChange((value) => {
          this.address = value
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

      Stack() {
        Row({ space: CloudThemeToken.loginOtpCellGap }) {
          ForEach(this.otpIndexes, (item: number) => {
            Column() {
              Text(item < this.otpCode.length ? this.otpCode[item] : '')
                .fontSize(CloudThemeToken.loginOtpCellTextSize)
                .fontWeight(FontWeight.Bold)
            }
            .width(CloudThemeToken.loginOtpCellWidth)
            .height(CloudThemeToken.loginOtpCellHeight)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(CloudThemeToken.otpCellRadius)
            .backgroundColor(CloudThemeToken.surface)
            .border({
              width: CloudThemeToken.loginOtpBorderWidth,
              color: this.otpCode.length === item
                ? CloudThemeToken.primary
                : CloudThemeToken.transparent
            })
          }, (item: number) => item.toString())
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')

        TextInput()
          .id(this.otpInputId)
          .type(InputType.Number)
          .maxLength(CloudThemeToken.loginOtpLength)
          .width('100%')
          .height(CloudThemeToken.loginOtpCellHeight)
          .opacity(CloudThemeToken.invisibleOpacity)
          .defaultFocus(true)
          .onChange((value) => {
            this.otpCode = value
            if (value.length === CloudThemeToken.loginOtpLength) {
              this.submitOtp()
            }
          })
      }
      .width('100%')
      .height(CloudThemeToken.loginOtpCellHeight)
    }
  }

  @Builder showLoginInput() {
    Column({ space: CloudThemeToken.loginInputGroupGap }) {
      // 用户名
      Row() {
        Image($r("app.media.ic_envelope"))
          .width(CloudThemeToken.loginInputIconSize)
          .margin({
            left: CloudThemeToken.loginInputIconHorizontalMargin,
            right: CloudThemeToken.loginInputIconHorizontalMargin
          })
          .fillColor(CloudThemeToken.primary)
          .draggable(false)

        TextInput({ placeholder: $r("app.string.login_user"), text: this.username })
          .loginTextInputStyle()
          .fontColor(CloudThemeToken.textPrimary)
          .placeholderColor(CloudThemeToken.textSecondary)
          .onChange((value) => {
            this.username = value
          })
      }
      .rowCommonStyle()

      // 密码
      Row() {
        Image($r("app.media.ic_key_horizontal"))
          .width(CloudThemeToken.loginInputIconSize)
          .margin({
            left: CloudThemeToken.loginInputIconHorizontalMargin,
            right: CloudThemeToken.loginInputIconHorizontalMargin
          })
          .fillColor(CloudThemeToken.primary)
          .draggable(false)

        TextInput({ placeholder: $r("app.string.login_password"), text: this.password })
          .type(InputType.Password)
          .loginTextInputStyle()
          .fontColor(CloudThemeToken.textPrimary)
          .placeholderColor(CloudThemeToken.textSecondary)
          .onChange((value) => {
            this.password = value
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

  @Styles scanAndUsersCommon() {
    .height(CloudThemeToken.smallIconButtonSize)
    .width(CloudThemeToken.smallIconButtonSize)
    .borderRadius(CloudThemeToken.controlRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder buttonScanAndUsers() {
    Row({ space: CloudThemeToken.loginFooterButtonGap }) {
      Button() {
        Image($r("app.media.ic_line_viewfinder"))
          .padding(CloudThemeToken.loginFooterIconPadding)
          .fillColor(CloudThemeToken.primary)
      }
      .scanAndUsersCommon()

      Button() {
        Image($r("app.media.ic_person_2"))
          .padding(CloudThemeToken.loginFooterIconPadding)
          .fillColor(CloudThemeToken.textSecondary)
      }
      .scanAndUsersCommon()
    }
  }

  @Builder privacyText() {
    Flex({wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center}) {
      Text($r('app.string.login_service_prefix'))
        .fontSize(CloudThemeToken.loginPrivacyTextSize)
        .fontColor(CloudThemeToken.textSecondary)

      Hyperlink('https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1579234134935491520', $r("app.string.hyperlink_app_privacy")) {
      }
      .color(CloudThemeToken.primary)
      .height(CloudThemeToken.loginPrivacyLinkHeight)
    }
    .width("100%")
    .margin({bottom: this.keyHeight})
  }
}
