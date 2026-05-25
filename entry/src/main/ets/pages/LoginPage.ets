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

@Extend(Row)
function rowCommonStyle() {
  .borderRadius(10)
  .backgroundColor($r("app.color.textinput_background"))
  .width('100%')
  .height(40)
  .alignItems(VerticalAlign.Center)
  .shadow(ShadowStyle.OUTER_DEFAULT_SM)
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

  aboutToAppear() {
    window.getLastWindow(getContext(this)).then(currentWindow => {
      // 设置窗口的布局为沉浸式布局
      currentWindow.setWindowLayoutFullScreen(true);
      let property = currentWindow.getWindowProperties();

      // 初始化窗口高度
      let avoidArea = currentWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      this.scrollHeight = px2vp(property.windowRect.height - avoidArea.bottomRect.height);

      // 监听软键盘的隐藏和显示
      currentWindow.on('avoidAreaChange', data => {
        if (data.type == window.AvoidAreaType.TYPE_KEYBOARD) {
          this.keyHeight = px2vp(data.area.bottomRect.height);
          this.scrollHeight = px2vp(currentWindow.getWindowProperties().windowRect.height - data.area.bottomRect.height);
          return;
        }
      })
    })

    if (HMRouterMgr.getCurrentParam()) {
      this.nextPage = (HMRouterMgr.getCurrentParam() as LoginParam).nextPage
      console.debug('LoginPage', `NextPage: ${this.nextPage}`)
    }
  }

  build() {
    Column({space: 10}) {
      Column() {
        Row() {
          Button() {
            Image($r('app.media.ic_arrow_left_circle'))
          }
          .width(30)
          .backgroundColor($r("app.color.main_window_background"))
          .borderRadius(15)
          .onClick(() => {
            if (this.needs2FA) {
              this.needs2FA = false
            } else {
              this.loginTitle = $r('app.string.website_title')
              this.websiteInvalid = false
            }
          })
        }
        .height(30)
        .margin({ top: 20 })
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .visibility(this.websiteInvalid ? Visibility.Visible : Visibility.Hidden)
        .animation({ duration: 500 })

        Column({ space: 10 }) {
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
              .fontSize(11)
              .fontColor($r("app.color.light_gray"))
              .margin({ left: 10, right: 10 })
          }
        }
        .width('100%')
      }

      Column({space: 12}) {
        // 扫描添加及历史账户
        this.buttonScanAndUsers()

        // 隐私条款声明
        this.privacyText()
      }
    }
    .height("100%")
    .padding({top: 20, left: 20, right: 20, bottom: this.keyHeight ? 0 : 20})
    .backgroundColor($r("app.color.main_window_background"))
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
    HMRouterMgr.push({pageUrl: this.nextPage})
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
    if (this.otpCode.length != 6) {
      showToastTips('请输入6位验证码', ToastType.Error)
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
      }
    })
  }

  @Builder showLoginHeader() {
    Image(this.websiteLogo)
      .draggable(false)
      .width(180)

    Text(this.loginTitle)
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
  }

  @Builder buttonContinue() {
    Button($r("app.string.login_continue"))
      .margin({top: 10})
      .shadow(ShadowStyle.OUTER_FLOATING_SM)
      .width("100%")
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
    .width(200)
    .menuItemDivider({strokeWidth: LengthMetrics.px(1), color: $r("app.color.menu_divider_line")})
  }

  @Styles loginTextInputStyle() {
    .borderRadius(0)
    .layoutWeight(1)
    .padding(0)
    .backgroundColor($r("app.color.textinput_background"))
  }

  @Builder showWebsiteInput() {
    Row() {
      Image($r("app.media.ic_worldclock_fill"))
        .width(20)
        .margin({ left: 5, right: 5 })

      Text(this.protocol)
        .fontColor($r('app.color.light_gray'))
        .textAlign(TextAlign.Center)
        .bindMenu(this.protocolMenu)

      TextInput({ placeholder: $r("app.string.login_address"), text: this.address })
        .loginTextInputStyle()
        .onChange((value) => {
          this.address = value
        })
    }
    .rowCommonStyle()
  }

  @Builder showOtpInput() {
    Column({ space: 16 }) {
      Text('请输入身份验证器中的6位验证码')
        .fontSize(13)
        .fontColor($r("app.color.light_gray"))
        .width('100%')
        .textAlign(TextAlign.Center)

      Stack() {
        Row({ space: 8 }) {
          ForEach([0, 1, 2, 3, 4, 5], (item: number) => {
            Column() {
              Text(item < this.otpCode.length ? this.otpCode[item] : '')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
            }
            .width(44)
            .height(52)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(10)
            .backgroundColor($r("app.color.textinput_background"))
            .border({
              width: 2,
              color: this.otpCode.length === item
                ? $r("app.color.select_primary")
                : Color.Transparent
            })
            .shadow(ShadowStyle.OUTER_DEFAULT_XS)
          }, (item: number) => item.toString())
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')

        TextInput()
          .type(InputType.Number)
          .maxLength(6)
          .width('100%')
          .height(52)
          .opacity(0.01)
          .defaultFocus(true)
          .onChange((value) => {
            this.otpCode = value
            if (value.length === 6) {
              this.submitOtp()
            }
          })
      }
      .width('100%')
      .height(52)
    }
  }

  @Builder showLoginInput() {
    Column({space: 10}) {
      // 用户名
      Row() {
        Image($r("app.media.ic_envelope"))
          .width(20)
          .margin({ left: 10, right: 10 })
          .draggable(false)

        TextInput({ placeholder: $r("app.string.login_user"), text: this.username })
          .loginTextInputStyle()
          .onChange((value) => {
            this.username = value
          })
      }
      .rowCommonStyle()

      // 密码
      Row() {
        Image($r("app.media.ic_key_horizontal"))
          .width(20)
          .margin({ left: 10, right: 10 })
          .draggable(false)

        TextInput({ placeholder: $r("app.string.login_password"), text: this.password })
          .type(InputType.Password)
          .loginTextInputStyle()
          .onChange((value) => {
            this.password = value
          })
      }
      .rowCommonStyle()
      .transition(TransitionEffect.OPACITY.animation({duration: 500})
        .combine(TransitionEffect.translate({y: -30}).animation({duration: 500})))
    }
    .transition(TransitionEffect.asymmetric(undefined, TransitionEffect.OPACITY.animation({duration: 150})))
  }

  @Styles scanAndUsersCommon() {
    .height(30)
    .width(30)
    .borderColor($r("app.color.light_light_gray"))
    .borderWidth(1)
    .borderRadius(15)
    .backgroundColor($r("app.color.main_window_background"))
  }

  @Builder buttonScanAndUsers() {
    Row({space: 10}) {
      Button() {
        Image($r("app.media.ic_line_viewfinder"))
          .padding(5)
          .fillColor('#ffb110b1')
      }
      .scanAndUsersCommon()

      Button() {
        Image($r("app.media.ic_person_2"))
          .padding(5)
          .fillColor('#ff9d765d')
      }
      .scanAndUsersCommon()
    }
  }

  @Builder privacyText() {
    Flex({wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center}) {
      Text($r('app.string.login_service_prefix'))
        .fontSize(11)
        .fontColor($r("app.color.light_gray"))

      // Hyperlink('https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1579234134935491520', $r("app.string.hyperlink_app_service")) {
      // }
      // .color($r("app.color.select_primary"))
      // .height(13)
      //
      // Text(" 和 ")
      //   .fontSize(11)
      //   .fontColor($r("app.color.light_gray"))

      Hyperlink('https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1579234134935491520', $r("app.string.hyperlink_app_privacy")) {
      }
      .color($r("app.color.select_primary"))
      .height(13)
    }
    .width("100%")
    .margin({bottom: this.keyHeight})
  }
}