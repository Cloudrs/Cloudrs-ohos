import { HMRouterMgr } from "@hadss/hmrouter";
import { SiteConfig, UserSetting, UserStorage } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import UserDatabase from "../../model/UserDatabase";
import UserPreferences from "../../model/UserPreferences";
import { CloudApi } from "../../model/net/CloudApi";
import { image } from "@kit.ImageKit";
import { CommonUtil } from "../../utils/CommonUtil";
import { CloudThemeToken } from "../../model/CloudTheme";
import { CloudScaffold } from "../../components/CloudScaffold";
import { SectionHeader } from "../../components/SectionHeader";
import { common, ConfigurationConstant } from "@kit.AbilityKit";
import { DateFormatUtil } from "../../utils/DateFormatUtil";

const TAG:string = 'TabMine'

enum MineSheetType {
  NONE = 'none',
  MORE = 'more',
  THEME = 'theme'
}

@Preview
@Component
export struct TabMine {
  @Link overLap: boolean
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';
  @State siteConfig?: SiteConfig = undefined
  @State userStorage?: UserStorage = undefined
  @State userSetting?: UserSetting = undefined
  @State currentUser: string = ''
  @State updateDate?: Date = undefined
  @State userAvatar?: PixelMap = undefined
  @State diffDays: number = 0
  @State cachedUserId: string = ''
  @State cachedGroupName: string = ''
  @State cachedDiffDays: number = 0
  private avatarSize: number = 64
  @State webUrl: string = ''
  @State webShow: boolean = false
  @State showSettingsSheet: boolean = false
  @State activeSheetType: MineSheetType = MineSheetType.NONE
  @State themeMode: string = Constant.APP_THEME_LIGHT
  private scroller: Scroller = new Scroller;
  @State versionInfo: string = ''
  @State uploadMaxConcurrent: number = 3

  aboutToAppear() {
    this.currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY) as string
    this.loadCachedUserInfo()
    this.getUserSettings()
    this.themeMode = UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.APP_THEME_MODE,
      Constant.APP_THEME_LIGHT
    ) as string

    this.versionInfo = this.appVersion

    const raw = UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.UPLOAD_MAX_CONCURRENT,
      3
    );
    this.uploadMaxConcurrent = (typeof raw === 'number' && raw > 0) ? raw : 3;
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
    Stack() {
      CloudScaffold({
        scroller: this.scroller,
        topPadding: 20,
        bottomPadding: 20
      }) {
        Column({ space: CloudThemeToken.sectionGap }) {
          this.userInfo()
          this.storageInfo()
          SectionHeader({ title: $r('app.string.more_setting') })
          this.settingButton()
          this.webButton()
          this.logoutButton()
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSettingsSheet, this.settingsSheet(), {
      showClose: false,
      backgroundColor: CloudThemeToken.background,
      onDisappear: () => {
        this.showSettingsSheet = false
      }
    })
  }

  loadCachedUserInfo(): void {
    const dbUserInfo = UserDatabase.getUserInfo(this.currentUser)
    if (!dbUserInfo || !dbUserInfo.userinfo) {
      return
    }
    this.cachedUserId = dbUserInfo.userinfo.id ?? ''
    this.cachedGroupName = dbUserInfo.userinfo.group?.name ?? ''
    if (dbUserInfo.userinfo.created_at && dbUserInfo.userinfo.created_at.length > 0) {
      this.cachedDiffDays = CommonUtil.getDaysDifference(new Date(dbUserInfo.userinfo.created_at), new Date())
    }
  }

  @Builder userInfo() {
    Column({space: 16}) {
      Row({space: 14}) {
        Image(this.userAvatar ?? $r("app.media.ic_default_avatar"))
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.avatarSize / 2)
          .borderWidth(1)
          .borderColor(CloudThemeToken.line)
          .draggable(false)

        Column({space: 6}) {
          Text(this.siteConfig ? this.siteConfig.user.nickname : '')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})

          Text(this.siteConfig ? this.siteConfig.user.user_name : this.currentUser)
            .fontSize(14)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})

          Text(this.siteConfig?.user.group.name ?? '')
            .fontSize(12)
            .fontColor(CloudThemeToken.primary)
            .padding({left: 10, right: 10, top: 4, bottom: 4})
            .borderRadius(CloudThemeToken.controlRadius)
            .backgroundColor(CloudThemeToken.primarySoft)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({space: 10}) {
        this.metricCell($r('app.string.user_id'), this.getUserIdText())
        this.metricCell($r('app.string.user_group'), this.getGroupNameText())
        this.metricCell($r('app.string.user_days'), this.getUserDaysText())
      }
      .width('100%')
      .height(76)
    }
    .padding(16)
    .width('100%')
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  getUserIdText(): string {
    if (this.userSetting && this.userSetting.uid > 0) {
      return this.userSetting.uid.toString()
    }
    if (this.siteConfig?.user.id && this.siteConfig.user.id.length > 0) {
      return this.siteConfig.user.id
    }
    return this.cachedUserId.length > 0 ? this.cachedUserId : '-'
  }

  getGroupNameText(): string {
    if (this.siteConfig?.user.group?.name && this.siteConfig.user.group.name.length > 0) {
      return this.siteConfig.user.group.name
    }
    return this.cachedGroupName.length > 0 ? this.cachedGroupName : '-'
  }

  getUserDaysText(): string {
    if (this.diffDays > 0) {
      return this.diffDays.toString()
    }
    if (this.cachedDiffDays > 0) {
      return this.cachedDiffDays.toString()
    }
    return '-'
  }

  @Builder metricCell(label: ResourceStr, value: string) {
    Column({space: 6}) {
      Text(label)
        .fontSize(12)
        .fontColor(CloudThemeToken.textSecondary)
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
        .maxLines(1)
        .textOverflow({overflow: TextOverflow.Ellipsis})
    }
    .layoutWeight(1)
    .height('100%')
    .padding(10)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
  }

  @Builder storageInfo() {
    Column({space: 14}) {
      Row() {
        Column({space: 8}) {
          Text($r('app.string.storage_used'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)

          Text(this.userStorage ? `${CommonUtil.formatBytes(this.userStorage.used)} / ${CommonUtil.formatBytes(this.userStorage.total)}` : '')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)

          Row({space: 5}) {
            Text($r('app.string.storage_update_date'))
              .fontSize(12)
              .fontColor(CloudThemeToken.textSecondary)
            Text(this.updateDate ? `${DateFormatUtil.format(this.updateDate, 'yyyy/MM/dd')}` : '')
              .fontSize(12)
              .fontColor(CloudThemeToken.textSecondary)
          }
          .justifyContent(FlexAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Stack({alignContent: Alignment.Center}) {
          DataPanel({ values: [this.userStorage?.used ?? 0], max: this.userStorage?.total ?? 100, type: DataPanelType.Circle })
            .width(96)
            .height(96)
            .strokeWidth(10)
            .valueColors([CloudThemeToken.primary])

          Text(this.getStoragePercentText())
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)

      Column({space: 8}) {
        Progress({value: this.userStorage?.used ?? 0, total: this.userStorage?.total ?? 100, type: ProgressType.Capsule})
          .width('100%')
          .height(8)
          .color(CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({space: 4}) {
          Text($r('app.string.storage_available'))
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)
          Text(this.userStorage ? CommonUtil.formatBytes(this.userStorage.free) : '')
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)
          Blank()
          Image($r('app.media.ic_externaldrive_fill'))
            .width(16)
            .height(16)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .padding(16)
    .width('100%')
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: 1, color: CloudThemeToken.line })
  }

  getStoragePercentText(): string {
    if (!this.userStorage || this.userStorage.total <= 0) {
      return ''
    }
    return `${(this.userStorage.used * 100 / this.userStorage.total).toFixed(1)}%`
  }

  @Builder logoutButton() {
    Button({type: ButtonType.Normal}) {
      Row({space: 10}) {
        Image($r('app.media.ic_square_logout'))
          .width(22)
          .height(22)
          .fillColor(CloudThemeToken.danger)
          .draggable(false)

        Text($r('app.string.logout'))
          .fontColor(CloudThemeToken.danger)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(52)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: 1, color: CloudThemeToken.line })
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.logout_confim'),
        message: '',
        primaryButton: {
          value: $r('app.string.dialog_cancel'),
          action: () => {}
        },
        secondaryButton: {
          value: $r('app.string.dialog_logout'),
          action: () => {
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
          .width(30)
          .height(30)
          .borderRadius(CloudThemeToken.cardRadius)
          .padding(7)
          .fillColor(CloudThemeToken.onPrimary)
          .backgroundColor(backgroundColor)
          .draggable(false)

        Text(title)
          .fontSize(16)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)

        if (sub_title) {
          Text(sub_title)
            .fontSize(14)
            .fontColor(CloudThemeToken.textSecondary)
        }
        Image($r('app.media.ic_chevron_right'))
          .width(12)
          .height(12)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .padding({left: 10, right: 10})
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(52)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: 1, color: CloudThemeToken.line })
    .onClick(() => {
      if (onClickCallback) {
        onClickCallback()
      }
    })
  }

  @Builder rowWithSelect(icon: ResourceStr, bgColor: ResourceStr,
    title: ResourceStr, currentValue: number,
    options: SelectOption[], onChange: (val: number) => void) {
    Row({ space: 10 }) {
      Image(icon)
        .width(30).height(30).borderRadius(CloudThemeToken.cardRadius).padding(7)
        .fillColor(CloudThemeToken.onPrimary).backgroundColor(bgColor)
        .draggable(false)

      Text(title)
        .fontSize(16)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      Select(options)
        .value(currentValue.toString())
        .selected(currentValue - 1)
        .onSelect((index: number) => { onChange(index + 1); })
        .width(70)
    }
    .width('100%')
    .height(52)
    .padding({ left: 10, right: 10 })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: 1, color: CloudThemeToken.line })
    .alignItems(VerticalAlign.Center)
  }

  @Builder settingButton() {
    Column({space: 10}) {
      this.rowWithNext($r('app.media.ic_privacy_secure'),
        $r('app.color.setting_icon_privacy_background'),
        $r('app.string.user_privacy_secure'))
      this.rowWithNext($r('app.media.ic_theme_setting'),
        $r('app.color.setting_icon_theme_background'),
        $r("app.string.user_theme_setting"),
        this.getThemeModeText(),
        () => {
          this.openSettingsSheet(MineSheetType.THEME)
        })
      this.rowWithNext($r('app.media.ic_more_setting'),
        $r('app.color.setting_icon_more_background'),
        $r('app.string.more_setting'),
        undefined,
        () => {
          this.openSettingsSheet(MineSheetType.MORE)
        })
      this.rowWithNext($r('app.media.ic_info_circle'),
        $r('app.color.setting_icon_about'),
        $r('app.string.about'),
        this.versionInfo,
        () => { HMRouterMgr.push({pageUrl: Constant.ABOUT_PAGE}) }
      )
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  private openSettingsSheet(type: MineSheetType): void {
    this.activeSheetType = type
    this.showSettingsSheet = true
  }

  private closeSettingsSheet(): void {
    this.showSettingsSheet = false
    this.activeSheetType = MineSheetType.NONE
  }

  @Builder settingsSheet() {
    if (this.activeSheetType === MineSheetType.THEME) {
      this.themeSettingsSheet()
    } else {
      this.moreSettingsSheet()
    }
  }

  @Builder themeSettingsSheet() {
    Column({ space: 16 }) {
      this.sheetHeader($r('app.string.user_theme_setting'), () => {
        this.closeSettingsSheet()
      })

      this.themeOptionRow(
        $r('app.string.theme_light_title'),
        $r('app.string.theme_light_desc'),
        Constant.APP_THEME_LIGHT
      )
      this.themeOptionRow(
        $r('app.string.theme_dark_title'),
        $r('app.string.theme_dark_desc'),
        Constant.APP_THEME_DARK
      )
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 28 })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder moreSettingsSheet() {
    Column({ space: 16 }) {
      this.sheetHeader($r('app.string.more_setting'), () => {
        this.closeSettingsSheet()
      })

      this.rowWithSelect(
        $r('app.media.ic_more_setting'),
        $r('app.color.setting_icon_more_background'),
        $r('app.string.upload_max_concurrent'),
        this.uploadMaxConcurrent,
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => ({ value: n.toString() } as SelectOption)),
        (val: number) => {
          this.uploadMaxConcurrent = val;
          UserPreferences.putSync(
            Constant.USER_PREFERENCES,
            Constant.UPLOAD_MAX_CONCURRENT,
            val
          );
        }
      )
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 28 })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder sheetHeader(title: ResourceStr, onClose: () => void) {
    Row() {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_xmark_circle_fill'))
          .width(22)
          .height(22)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .borderRadius(CloudThemeToken.controlRadius)
      .backgroundColor(CloudThemeToken.surfaceSubtle)
      .onClick(onClose)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder themeOptionRow(title: ResourceStr, description: ResourceStr, mode: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
        Text(description)
          .fontSize(12)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.themeMode === mode) {
        Image($r('app.media.ic_checkmark_circle'))
          .width(22)
          .height(22)
          .fillColor(CloudThemeToken.primary)
          .draggable(false)
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 14, right: 14 })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(this.themeMode === mode ? CloudThemeToken.primarySoft : CloudThemeToken.surface)
    .border({ width: 1, color: this.themeMode === mode ? CloudThemeToken.primary : CloudThemeToken.line })
    .onClick(() => {
      this.setThemeMode(mode)
    })
  }

  getThemeModeText(): ResourceStr {
    return this.themeMode === Constant.APP_THEME_DARK
      ? $r('app.string.theme_dark_title')
      : $r('app.string.theme_light_title')
  }

  setThemeMode(mode: string): void {
    this.themeMode = mode
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.APP_THEME_MODE, mode)
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      context.setColorMode(mode === Constant.APP_THEME_DARK
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
    } catch (err) {
      console.error(TAG, `set theme mode failed: ${(err as Error)?.message ?? err}`)
    }
  }

  @Builder rowWithJump(icon: ResourceStr, backgroundColor: ResourceStr, title: ResourceStr, url: string) {
    Button({type: ButtonType.Normal}) {
      Row({space: 10}) {
        Image(icon)
          .width(28)
          .height(28)
          .borderRadius(14)
          .padding(5)
          .fillColor(CloudThemeToken.onPrimary)
          .backgroundColor(backgroundColor)
          .draggable(false)

        Hyperlink(url, title)
          .height(20)
          .color(CloudThemeToken.textPrimary)
          .draggable(false)
          .layoutWeight(1)

        Image($r('app.media.ic_web_jump'))
          .width(16)
          .height(16)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .padding({left: 10, right: 10})
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(50)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: 1, color: CloudThemeToken.line })
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
