import { LengthMetrics } from '@kit.ArkUI'
import axios, { AxiosResponse, AxiosRequestConfig } from '@ohos/axios'
import { JSON } from '@kit.ArkTS'
import { window } from '@kit.ArkUI';
import { baseUrlSet, pingRequest } from '../utils/AxiosRequest';

const REQUEST_TIMEOUT: number = 3000;

class DataResponse {
  code: string = ''
  data: string = ''
  msg: string = ''
}

@Entry
@Component
struct LoginPage {
  @State protocolIndex: number = 0
  @State protocol: string = 'https://'
  @State scrollHeight: number = 0;
  @State keyHeight: number = 0;
  @State websiteInvalid: boolean = false;
  @State loginInvalid: boolean = false;

  private address: string = ''
  private username: string = ''
  private password: string = ''
  scroller: Scroller = new Scroller();

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
  }

  build() {
    Column({space: 10}) {
      Row() {
        Button() {
          Image($r('app.media.ic_arrow_left_circle'))
        }
        .width(30)
        .backgroundColor($r("app.color.main_window_background"))
        .borderRadius(15)
        .onClick(() => {
          this.websiteInvalid = false
        })
      }
      .height(30)
      .margin({top: 20})
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .visibility(this.websiteInvalid ? Visibility.Visible : Visibility.Hidden)
      .animation({duration:500})

      Scroll(this.scroller) {
        Column({space: 10}) {
          // 显示login及标题
          this.showLoginHeader()

          // 根据状态显示不同输入框
          if (!this.websiteInvalid) {
            // 网站地址输入
            this.showWebsiteInput()
          }
          else {
            // 登录用户名密码输入
            this.showLoginInput()
          }

          // 按键
          this.buttonContinue();

          // 提示
          Text($r("app.string.login_tips"))
            .fontSize(11)
            .fontColor($r("app.color.light_gray"))
            .margin({left: 10, right: 10})
        }
      }
      .width('100%')
      .height(this.scrollHeight)
      .layoutWeight(1)
      .align(Alignment.Center)

      // 扫描添加及历史账户
      this.buttonScanAndUsers()

      // 隐私条款声明
      this.privacyText()
    }
    .height("100%")
    .padding({top: 20, left: 20, right: 20, bottom: this.keyHeight ? 0 : 20})
    .backgroundColor($r("app.color.main_window_background"))
  }

  @Builder
  showLoginHeader() {
    Image($r("app.media.cloudreve"))
      .width(100)
      .margin({ bottom: 20 })

    Text(this.websiteInvalid ? $r("app.string.login_title") : $r("app.string.website_title"))
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
  }

  @Builder
  buttonContinue() {
    Button($r("app.string.login_continue"))
      .width("100%")
      .onClick(async () => {
        if (!this.websiteInvalid) {
          if (this.address.length == 0) {
            AlertDialog.show({message: '输入的网站地址不能为空'})
            return
          }
          baseUrlSet(this.address)
          let isOk = await pingRequest();
          if (isOk) {
            this.websiteInvalid = true;
          }
          else {
            AlertDialog.show({message: '站点请求失败'})
          }
        }
        else {
          if (this.username.length == 0 || this.password.length == 0) {
            AlertDialog.show({message: '无效用户名或密码'})
            return
          }

          let urlLogin = this.protocol + this.address + '/api/v3/user/session'
          axios.get(urlLogin, {timeout: REQUEST_TIMEOUT})
            .then((response: AxiosResponse) => {
              if (response.status !== 200) {
                console.log("loginPage", "访问失败，请检查网址是否正确");
                return
              }

              let json = JSON.parse(response.data)
              if ((json as object)?.['code'] === 0) {
                console.log("loginPage", "请求成功", JSON.stringify(response.data));
                this.loginInvalid = true;
                //TODO: 跳转到导航页

              }
              else {
                console.log("loginPage", "访问失败，请检查网址是否正确");
              }
            })
            .catch((reason: string) => {
              console.log("loginPage", "请求失败，错误：", JSON.stringify(reason));
            })
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

  @Builder
  showWebsiteInput() {
    Stack() {
      TextInput()
        .borderRadius(10)
        .backgroundColor($r("app.color.textinput_background"))

      Row() {
        Image($r("app.media.ic_worldclock_fill"))
          .width(20)
          .margin({ left: 5, right: 5 })

        Text(this.protocol)
          .bindMenu(this.protocolMenu)

        TextInput({
          placeholder: $r("app.string.login_address"),
          text: this.address
        })
          .backgroundColor($r("app.color.textinput_background"))
          .borderRadius(10)
          .padding({ left: 0})
          .layoutWeight(1)
          .onChange((value) => {
            this.address = value
          })
      }
    }
    .alignContent(Alignment.Start)
    .width("100%")
    .transition( TransitionEffect.SLIDE_SWITCH.animation({ duration: 500, curve: Curve.EaseInOut }))
  }

  @Builder
  showLoginInput() {
    Column({space: 10}) {
      // 用户名
      Stack() {
        TextInput()
          .borderRadius(10)
          .backgroundColor($r("app.color.textinput_background"))

        Row() {
          Image($r("app.media.ic_envelope"))
            .width(20)
            .margin({ left: 10, right: 10 })

          TextInput({
            placeholder: $r("app.string.login_user"),
            text: this.username
          })
            .backgroundColor($r("app.color.textinput_background"))
            .borderRadius(10)
            .padding({ left: 0 })
            .layoutWeight(1)
            .onChange((value) => {
              this.username = value
            })
        }
      }
      .alignContent(Alignment.Start)
      .width("100%")

      // 密码
      Stack() {
        TextInput()
          .borderRadius(10)
          .backgroundColor($r("app.color.textinput_background"))

        Row() {
          Image($r("app.media.ic_key_horizontal"))
            .width(20)
            .margin({ left: 10, right: 10 })

          TextInput({
            placeholder: $r("app.string.login_password"),
            text: this.password
          })
            .type(InputType.Password)
            .backgroundColor($r("app.color.textinput_background"))
            .borderRadius(10)
            .padding({ left: 0 })
            .layoutWeight(1)
            .onChange((value) => {
              this.password = value
            })
        }
      }
      .alignContent(Alignment.Start)
      .width("100%")
    }
    .transition( TransitionEffect.SLIDE_SWITCH.animation({ duration: 500, curve: Curve.EaseInOut }))
  }

  @Builder
  buttonScanAndUsers() {
    Row({space: 10}) {
      Button() {
        Image($r("app.media.ic_line_viewfinder"))
          .padding(5)
          .fillColor('#ffb110b1')
      }
      .height(30)
      .width(30)
      .borderColor($r("app.color.light_light_gray"))
      .borderWidth(1)
      .borderRadius(15)
      .backgroundColor($r("app.color.main_window_background"))

      Button() {
        Image($r("app.media.ic_person_2"))
          .padding(5)
          .fillColor('#ff9d765d')
      }
      .height(30)
      .width(30)
      .borderColor($r("app.color.light_light_gray"))
      .borderWidth(1)
      .borderRadius(15)
      .backgroundColor($r("app.color.main_window_background"))
    }
  }

  @Builder
  privacyText() {
    Flex({wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center}) {
      Text("使用Cloudreve即表示您接受我们的 ")
        .fontSize(11)
        .fontColor($r("app.color.light_gray"))

      Hyperlink('https://cloudreve.org/privacy-policy', '服务条款') {
      }
      .color($r("app.color.select_primary"))
      .height(13)

      Text(" 和 ")
        .fontSize(11)
        .fontColor($r("app.color.light_gray"))

      Hyperlink('https://cloudreve.org/privacy-policy', '隐私政策') {
      }
      .color($r("app.color.select_primary"))
      .height(13)
    }
    .width("100%")
    .margin({bottom: this.keyHeight})
  }
}