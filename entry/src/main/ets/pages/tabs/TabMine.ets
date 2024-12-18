import { HMRouterMgr } from "@hadss/hmrouter";
import { SiteConfig, UserSetting, UserStorage } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import UserDatabase from "../../model/UserDatabase";
import UserPreferences from "../../model/UserPreferences";
import { CloudApi } from "../../model/net/CloudApi";
import { image } from "@kit.ImageKit";
import { CommonUtil } from "../../utils/CommonUtil";
import { DateUtil } from "@pura/harmony-utils";
import { DialogAction, DialogHelper } from "@pura/harmony-dialog";

const TAG:string = 'TabMine'

@Preview
@Component
export struct TabMine {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';
  @State siteConfig?: SiteConfig = undefined
  @State userStorage?: UserStorage = undefined
  @State userSetting?: UserSetting = undefined
  @State currentUser: string = ''
  @State updateDate?: Date = undefined
  @State userAvatar?: PixelMap = undefined
  @State diffDays: number = 0
  private avatarSize: number = 100
  @State webUrl: string = ''
  @State webShow: boolean = false
  private scroller: Scroller = new Scroller;
  @State versionInfo: string = ''

  aboutToAppear() {
    this.currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY) as string
    this.getUserSettings()

    let value = getContext().resourceManager.getStringSync($r('app.string.version'))
    this.versionInfo = `${value} ${this.appVersion}`
  }

  getUserSettings() {
    // 获取站点信息
    CloudApi.getSiteConfig({
      onSuccess: (data: SiteConfig) => {
        this.siteConfig = data
        this.diffDays = CommonUtil.getDaysDifference(new Date(this.siteConfig.user.created_at), new Date())
        // 获取用户头像
        CloudApi.getUserAvatar(this.siteConfig.user.id, {
          onSuccess: (data) => {
            let imageSource: image.ImageSource = image.createImageSource(data)
            imageSource.createPixelMap().then((pixMap: PixelMap) => {
              this.userAvatar = pixMap
            })
          },
          onFailure: (msg) => {
            console.error(TAG, `User avatar get failed, ${msg}`)
          }
        })
      },
      onFailure: (msg) => {
        console.error(TAG, `SiteConfig get failed, ${msg}`)
      }
    })

    // 获取用户配置
    CloudApi.userSetting({
      onSuccess: (data: UserSetting) => {
        this.userSetting = data
      },
      onFailure: (msg) => {
        console.error(TAG, `Setting get failed, ${msg}`)
      }
    })

    // 获取用户存储容量
    CloudApi.userStorage({
      onSuccess: (data: UserStorage) => {
        this.userStorage = data
        this.updateDate = new Date()
      },
      onFailure: (msg) => {
        console.error(TAG, `Storage get failed, ${msg}`)
      }
    })
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 10 }) {
        this.userInfo()
        this.storageInfo()
        this.settingButton()
        this.webButton()
        this.logoutButton()
      }
      .padding({left: 20, right: 20, top: 20, bottom: this.tabBarHeight+20})
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder userInfo() {
    Column({space: 15}) {
      Stack({ alignContent: Alignment.Top }) {
        Column({ space: 10 }) {
          Text(this.siteConfig ? this.siteConfig.user.nickname.toUpperCase() : '')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)

          Text(this.siteConfig ? this.siteConfig.user.user_name : '')
            .fontSize(16)
            .fontColor($r('app.color.common_font_gray'))
        }
        .width('100%')
        .height(140)
        .padding({ top: this.avatarSize / 2 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .margin({ top: this.avatarSize / 2 })
        .linearGradient({
          direction: GradientDirection.RightTop, //从左下往右上的渐变方向
          colors: [
            ['#e5f1ff', 0], //起始颜色
            ['#e9f9ee', 1]//结束颜色
          ],
          repeating: false//设置不重复渐变
        })
        .borderRadius(10)
        .shadow(ShadowStyle.OUTER_DEFAULT_SM)

        Column() {
          Image(this.userAvatar ?? $r("app.media.ic_default_avatar"))
            .width(this.avatarSize)
            .height(this.avatarSize)
            .borderWidth(5)
            .borderRadius(this.avatarSize / 2)
            .borderColor(Color.White)
            .shadow(ShadowStyle.OUTER_DEFAULT_SM)
            .draggable(false)
        }
        .alignItems(HorizontalAlign.Center)
      }

      Row({space: 10}) {
        // uid
        Column() {
          Text($r('app.string.user_id'))
            .fontSize(16)
            .fontColor($r('app.color.common_font_gray'))
          Text(this.userSetting?.uid.toString())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
        }
        .width('30%')
        .height('100%')
        .padding(10)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceEvenly)
        .borderRadius(10)
        .backgroundColor($r('app.color.uid_background'))
        .shadow(ShadowStyle.OUTER_DEFAULT_SM)

        // gid
        Column() {
          Text($r('app.string.user_group'))
            .fontSize(16)
            .fontColor($r('app.color.common_font_gray'))
          Text(this.siteConfig?.user.group.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
        }
        .width('30%')
        .height('100%')
        .padding(10)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceEvenly)
        .borderRadius(10)
        .backgroundColor($r('app.color.group_background'))
        .shadow(ShadowStyle.OUTER_DEFAULT_SM)

        // days
        Column() {
          Text($r('app.string.user_days'))
            .fontSize(16)
            .fontColor($r('app.color.common_font_gray'))
          Text(this.diffDays.toString())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
        }
        .width('30%')
        .height('100%')
        .padding(10)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceEvenly)
        .borderRadius(10)
        .backgroundColor($r('app.color.days_background'))
        .shadow(ShadowStyle.OUTER_DEFAULT_SM)
      }
      .width('100%')
      .height(70)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding({ top: this.topRectHeight })
  }

  @Builder storageInfo() {
    Row() {
      Column({space: 10}) {
        Text($r('app.string.storage_used'))
          .fontSize(15)
          .fontColor($r('app.color.common_font_gray'))

        Text(this.userStorage ? `${CommonUtil.formatBytes(this.userStorage.used)} / ${CommonUtil.formatBytes(this.userStorage.total)}` : '')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)

        Image($r('app.media.ic_externaldrive_fill'))
          .width(20)
          .height(20)
          .draggable(false)

        Row({space: 5}) {
          Text($r('app.string.storage_update_date'))
            .fontSize(12)
            .fontColor($r('app.color.common_font_gray'))
          Text(this.updateDate ? `${DateUtil.getFormatDateStr(this.updateDate, 'yyyy/MM/dd')}` : '')
            .fontSize(12)
            .fontColor($r('app.color.common_font_gray'))
        }
        .justifyContent(FlexAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)

      Stack({alignContent: Alignment.Center}) {
        DataPanel({ values: [this.userStorage?.used], max: this.userStorage?.total, type: DataPanelType.Circle })
          .width(140)
          .height(140)
          .strokeWidth(15)

        Text(this.userStorage ? `${(this.userStorage.used*100/this.userStorage.total).toFixed(1)} %` : '')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
      }
    }
    .padding(10)
    .width('100%')
    .height(140)
    .borderRadius(10)
    .backgroundColor($r('app.color.storage_info_background'))
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .shadow(ShadowStyle.OUTER_DEFAULT_SM)
  }

  @Builder logoutButton() {
    Button({type: ButtonType.Normal}) {
      Row({space: 10}) {
        Image($r('app.media.ic_square_logout'))
          .width(28)
          .height(28)
          .borderRadius(14)
          .padding(5)
          .fillColor(Color.White)
          .backgroundColor(Color.Red)
          .objectFit(ImageFit.Cover)
          .draggable(false)

        Text($r('app.string.logout'))
          .fontColor(Color.Red)
          .fontSize(16)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(50)
    .borderRadius(10)
    .backgroundColor($r('app.color.logout_background'))
    .padding({ left: 10, right: 15 })
    .onClick(() => {
      DialogHelper.showAlertDialog({
        primaryTitle:  $r('app.string.logout_confim'),
        content: '',
        primaryButton: {value: $r('app.string.dialog_cancel')},
        secondaryButton: {value: $r('app.string.dialog_logout'), role: ButtonRole.ERROR},
        onAction: (action: number, dialogId: string, content: string) => {
          if (action == DialogAction.TWO) {
            UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY)
            UserDatabase.deleteUserInfo(this.currentUser)
            HMRouterMgr.push({ pageUrl: Constant.LOGIN_PAGE })
          }
        }
      })
    })
  }

  @Builder rowWithNext(icon: ResourceStr, backgroundColor: ResourceStr,
    title: ResourceStr, sub_title?: ResourceStr, onClickCallback?: ()=>void) {
    Button({type: ButtonType.Normal}) {
      Row({space: 10}) {
        Image(icon)
          .width(28)
          .height(28)
          .borderRadius(14)
          .padding(5)
          .fillColor(Color.White)
          .backgroundColor(backgroundColor)
          .draggable(false)

        Text(title)
          .fontSize(16)
          .layoutWeight(1)

        if (sub_title) {
          Text(sub_title)
            .fontSize(14)
            .fontColor($r('app.color.common_font_gray'))
        }
        Image($r('app.media.ic_chevron_right'))
          .width(12)
          .height(12)
          .fillColor($r('app.color.common_right'))
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .padding({left: 10, right: 10})
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(50)
    .borderRadius(10)
    .backgroundColor($r('app.color.setting_button_background'))
    .onClick(() => {
      if (onClickCallback) {
        onClickCallback()
      }
    })
  }

  @Builder settingButton() {
    Column({space: 10}) {
      this.rowWithNext($r('app.media.ic_privacy_secure'),
        $r('app.color.setting_icon_privacy_background'),
        $r('app.string.user_privacy_secure'))
      this.rowWithNext($r('app.media.ic_theme_setting'),
        $r('app.color.setting_icon_theme_background'),
        $r("app.string.user_theme_setting"))
      this.rowWithNext($r('app.media.ic_more_setting'),
        $r('app.color.setting_icon_more_background'),
        $r('app.string.more_setting'))
      this.rowWithNext($r('app.media.ic_info_circle'),
        $r('app.color.setting_icon_about'),
        $r('app.string.about'),
        this.versionInfo,
        () => { HMRouterMgr.push({pageUrl: Constant.ABOUT_PAGE}) }
      )
    }
    .width('100%')
    .margin({top: 10})
    .justifyContent(FlexAlign.Center)
  }

  @Builder rowWithJump(icon: ResourceStr, backgroundColor: ResourceStr, title: ResourceStr, url: string) {
    Button({type: ButtonType.Normal}) {
      Row({space: 10}) {
        Image(icon)
          .width(28)
          .height(28)
          .borderRadius(14)
          .padding(5)
          .fillColor(Color.White)
          .backgroundColor(backgroundColor)
          .draggable(false)

        Hyperlink(url, title)
          .height(20)
          .color('#2c2c2d')
          .draggable(false)
          .layoutWeight(1)

        Image($r('app.media.ic_web_jump'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.common_right'))
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .padding({left: 10, right: 10})
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(50)
    .borderRadius(10)
    .backgroundColor($r('app.color.setting_button_background'))
    .onClick(() => {
      this.webUrl = url
      this.webShow = true
    })
  }

  @Builder webButton() {
    Column({space: 10}) {
      this.rowWithJump($r('app.media.ic_feedback'),
        $r('app.color.icon_web_jump'),
        $r('app.string.feedback'),
        'https://gitee.com/larriti/cloudrs-ohos/issues'
      )
    }
    .width('100%')
    // .margin({top: 10})
    .justifyContent(FlexAlign.Center)
  }
}