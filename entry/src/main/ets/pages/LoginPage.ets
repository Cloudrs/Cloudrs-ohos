import { LengthMetrics, window } from '@kit.ArkUI'
import { JSON } from '@kit.ArkTS'
import { baseUrlSet, cloudGet, cloudPost, cookieGet } from '../utils/AxiosRequest';
import { DbUserInfo, LoginData, SiteConfig, SiteURI, UserInfo } from '../model/net/ApiTypes';
import { showToastTips, ToastType } from '../utils/ToastUtil';
import Constant from '../model/Constant';
import UserPrivData from '../model/UserPreferences';
import UserDatabase from '../model/UserDatabase';
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { LoginParam } from '../model/net/LoginParam';
import { cloudLogin, cloudPing, cloudSiteConfig } from '../model/net/Api';

@Extend(Stack)
function loginStackStyle() {
  .borderRadius(10)
  .backgroundColor($r("app.color.textinput_background"))
  .width('100%')
  .height(40)
  .alignContent(Alignment.Start)
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
  @State loginTitle: string|Resource = $r('app.string.website_title');

  private address: string = ''
  private username: string = ''
  private password: string = ''
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
            this.loginTitle = $r('app.string.website_title')
            this.websiteInvalid = false
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
    baseUrlSet(this.protocol + this.address)
    cloudPing({
      onSuccess: (data) => {
        cloudSiteConfig({
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

  private login() {
    if (this.username.length == 0 || this.password.length == 0) {
      showToastTips('无效用户名或密码', ToastType.Error)
      return
    }
    cloudLogin(this.username, this.password, {
      onSuccess: (data: UserInfo) => {
        let dbUserInfo: DbUserInfo = {
          url: this.protocol + this.address,
          username: this.username,
          password: this.password,
          cookie: this.cookie,
          expires: this.cookieExpires,
          userinfo: data
        }
        // 保存当前用户
        UserPrivData.putSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, this.username)
        // 插入到数据库
        UserDatabase.insertUserInfo(dbUserInfo)
        // 登录成功，跳转到上一页
        HMRouterMgr.push({pageUrl: this.nextPage})
      },
      onFailure: (msg: string) => {
        console.debug('LoginPage', '登录失败 错误信息:', msg)
        showToastTips('登录失败，请检查用户邮箱及密码', ToastType.Error);
      }
    })
  }

  @Builder
  showLoginHeader() {
    Image($r("app.media.cloudrs"))
      .width(180)

    Text(this.loginTitle)
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
  }

  @Builder
  buttonContinue() {
    Button($r("app.string.login_continue"))
      .width("100%")
      .onClick(() => {
        if (!this.websiteInvalid) {
         this.websiteTest()
        } else {
          this.login()
        }
      })
  }

  @Builder
  protocolMenu() {
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
    .menuItemDivider({strokeWidth: LengthMetrics.px(1), color: $r('app.color.light_gray')})
  }

  @Styles
  loginTextStyle() {
    .borderRadius(10)
    .backgroundColor($r("app.color.textinput_background"))
  }

  @Styles
  loginTextInputStyle() {
    .borderRadius(0)
    .layoutWeight(1)
    .padding(0)
    .backgroundColor($r("app.color.textinput_background"))
  }

  @Builder
  showWebsiteInput() {
    Stack() {
      Text()
        .loginTextStyle()
        .width('100%')

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
    }
    .loginStackStyle()
  }

  @Builder
  showLoginInput() {
    Column({space: 10}) {
      // 用户名
      Stack() {
        Text()
          .loginTextStyle()
          .width('100%')

        Row() {
          Image($r("app.media.ic_envelope"))
            .width(20)
            .margin({ left: 10, right: 10 })

          TextInput({ placeholder: $r("app.string.login_user"), text: this.username })
            .loginTextInputStyle()
            .onChange((value) => {
              this.username = value
            })
        }
      }
      .loginStackStyle()

      // 密码
      Stack() {
        Text()
          .loginTextStyle()
          .width('100%')

        Row() {
          Image($r("app.media.ic_key_horizontal"))
            .width(20)
            .margin({ left: 10, right: 10 })

          TextInput({ placeholder: $r("app.string.login_password"), text: this.password })
            .type(InputType.Password)
            .loginTextInputStyle()
            .onChange((value) => {
              this.password = value
            })
        }
      }
      .loginStackStyle()
      .transition(TransitionEffect.OPACITY.animation({duration: 500})
        .combine(TransitionEffect.translate({y: -30}).animation({duration: 500})))
    }
  }

  @Styles
  scanAndUsersCommon() {
    .height(30)
    .width(30)
    .borderColor($r("app.color.light_light_gray"))
    .borderWidth(1)
    .borderRadius(15)
    .backgroundColor($r("app.color.main_window_background"))
  }

  @Builder
  buttonScanAndUsers() {
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

  @Builder
  privacyText() {
    Flex({wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center}) {
      Text($r('app.string.login_service_prefix'))
        .fontSize(11)
        .fontColor($r("app.color.light_gray"))

      Hyperlink('https://cloudreve.org/privacy-policy', $r('app.string.hypelink_app_service')) {
      }
      .color($r("app.color.select_primary"))
      .height(13)

      Text(" 和 ")
        .fontSize(11)
        .fontColor($r("app.color.light_gray"))

      Hyperlink('https://cloudreve.org/privacy-policy', $r('app.string.hypelink_app_privace')) {
      }
      .color($r("app.color.select_primary"))
      .height(13)
    }
    .width("100%")
    .margin({bottom: this.keyHeight})
  }
}