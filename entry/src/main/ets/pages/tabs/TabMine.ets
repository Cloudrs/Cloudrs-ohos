import { DbUserInfo, SiteConfig, UserInfo, UserSetting, UserStorage } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import UserDatabase from "../../model/UserDatabase";
import UserPreferences from "../../model/UserPreferences";
import { CloudApi } from "../../model/net/CloudApi";
import { CommonUtil } from "../../utils/CommonUtil";
import { CloudThemeToken } from "../../model/CloudTheme";
import { CloudScaffold } from "../../components/CloudScaffold";
import { SectionHeader } from "../../components/SectionHeader";
import { common, ConfigurationConstant } from "@kit.AbilityKit";
import { DateFormatUtil } from "../../utils/DateFormatUtil";
import { showCloudConfirmDialog } from "../../utils/CloudDialogUtil";
import { CloudRouter } from "../../utils/CloudRouter";
import { AvatarUtil } from "../../utils/AvatarUtil";
import { showToast } from "../../utils/ToastUtil";
import { AppLockUtil } from "../../utils/AppLockUtil";
import { SystemAuthResult } from "../../utils/SystemAuthUtil";

const TAG:string = 'TabMine'

enum MineSheetType {
  NONE = 'none',
  MORE = 'more',
  THEME = 'theme',
  PRIVACY = 'privacy'
}

@Component
export struct TabMine {
  @Link overLap: boolean
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @State siteConfig?: SiteConfig = undefined
  @State userStorage?: UserStorage = undefined
  @State userSetting?: UserSetting = undefined
  @State currentUser: string = ''
  @State currentUrl: string = ''
  @State updateDate?: Date = undefined
  @State userAvatar?: PixelMap = undefined
  @State diffDays: number = 0
  @State cachedUserId: string = ''
  @State cachedGroupName: string = ''
  @State cachedDiffDays: number = 0
  private avatarSize: number = CloudThemeToken.avatarLargeSize
  @State webUrl: string = ''
  @State webShow: boolean = false
  @State showSettingsSheet: boolean = false
  @State activeSheetType: MineSheetType = MineSheetType.NONE
  @State themeMode: string = Constant.APP_THEME_LIGHT
  private scroller: Scroller = new Scroller;
  @State versionInfo: string = ''
  @State uploadMaxConcurrent: number = 3
  @State systemAuthEnabled: boolean = false
  @State systemAuthBusy: boolean = false

  aboutToAppear() {
    this.currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY) as string
    this.currentUrl = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string
    this.loadCachedUserInfo()
    this.getUserSettings()
    this.themeMode = UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.APP_THEME_MODE,
      Constant.APP_THEME_LIGHT
    ) as string
    this.systemAuthEnabled = AppLockUtil.isEnabled()

    this.versionInfo = this.appVersion

    const raw = UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.UPLOAD_MAX_CONCURRENT,
      Constant.UPLOAD_CONCURRENT_DEFAULT
    ) as number;
    this.uploadMaxConcurrent = this.normalizeUploadConcurrent(raw)
  }

  getUserSettings() {
    // 获取站点信息
    CloudApi.getSiteConfig({
      onSuccess: (data: SiteConfig) => {
        this.siteConfig = data
        this.diffDays = CommonUtil.getDaysDifference(new Date(this.siteConfig.user.created_at), new Date())
        this.refreshCachedUserInfo(data.user)
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
        topPadding: CloudThemeToken.pageTopPadding,
        bottomPadding: CloudThemeToken.pageBottomPadding
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
        this.activeSheetType = MineSheetType.NONE
      }
    })
  }

  loadCachedUserInfo(): void {
    const dbUserInfo = UserDatabase.getUserInfo(this.currentUser, this.currentUrl)
    if (!dbUserInfo || !dbUserInfo.userinfo) {
      return
    }
    this.cachedUserId = dbUserInfo.userinfo.id ?? ''
    this.cachedGroupName = dbUserInfo.userinfo.group?.name ?? ''
    if (dbUserInfo.userinfo.created_at && dbUserInfo.userinfo.created_at.length > 0) {
      this.cachedDiffDays = CommonUtil.getDaysDifference(new Date(dbUserInfo.userinfo.created_at), new Date())
    }
    this.loadAvatar(dbUserInfo, false)
  }

  refreshCachedUserInfo(userInfo: UserInfo): void {
    const dbUserInfo = UserDatabase.getUserInfo(this.currentUser, this.currentUrl)
    if (!dbUserInfo) {
      return
    }
    dbUserInfo.userinfo = userInfo
    UserDatabase.insertUserInfo(dbUserInfo)
    this.cachedUserId = userInfo.id ?? ''
    this.cachedGroupName = userInfo.group?.name ?? ''
    if (userInfo.created_at && userInfo.created_at.length > 0) {
      this.cachedDiffDays = CommonUtil.getDaysDifference(new Date(userInfo.created_at), new Date())
    }
    this.loadAvatar(dbUserInfo, true)
  }

  private loadAvatar(dbUserInfo: DbUserInfo, forceRefresh: boolean): void {
    AvatarUtil.loadDbUserAvatar(dbUserInfo, forceRefresh)
      .then((pixMap?: PixelMap) => {
        if (pixMap) {
          this.userAvatar = pixMap
        }
      })
      .catch((err: Error) => {
        console.error(TAG, `User avatar get failed, ${err.message}`)
      })
  }

  @Builder userInfo() {
    Column({ space: CloudThemeToken.spacingPage }) {
      Row({ space: CloudThemeToken.spacingPanel }) {
        Stack() {
          if (this.userAvatar) {
            Image(this.userAvatar)
              .width(this.avatarSize)
              .height(this.avatarSize)
              .borderRadius(this.avatarSize / CloudThemeToken.halfDivisor)
              .draggable(false)
          } else {
            Image($r("app.media.ic_default_avatar"))
              .width(this.avatarSize * 0.58)
              .height(this.avatarSize * 0.58)
              .fillColor(CloudThemeToken.primary)
              .draggable(false)
          }
        }
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.avatarSize / CloudThemeToken.halfDivisor)
          .borderWidth(CloudThemeToken.lineWidth)
          .borderColor(CloudThemeToken.line)
          .backgroundColor(CloudThemeToken.primarySoft)

        Column({ space: CloudThemeToken.spacingMd }) {
          Text(this.siteConfig ? this.siteConfig.user.nickname : '')
            .fontSize(CloudThemeToken.textSizeHero)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})

          Text(this.siteConfig ? this.siteConfig.user.user_name : this.currentUser)
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})

          Text(this.siteConfig?.user.group.name ?? '')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.primary)
            .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard, top: CloudThemeToken.spacingXs, bottom: CloudThemeToken.spacingXs })
            .borderRadius(CloudThemeToken.controlRadius)
            .backgroundColor(CloudThemeToken.primarySoft)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: CloudThemeToken.spacingCard }) {
        this.metricCell($r('app.string.user_id'), this.getUserIdText())
        this.metricCell($r('app.string.user_group'), this.getGroupNameText())
        this.metricCell($r('app.string.user_days'), this.getUserDaysText())
      }
      .width('100%')
      .height(CloudThemeToken.cardHeightLg)
    }
    .padding(CloudThemeToken.spacingPage)
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
    Column({ space: CloudThemeToken.spacingMd }) {
      Text(label)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
      Text(value)
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
        .maxLines(1)
        .textOverflow({overflow: TextOverflow.Ellipsis})
    }
    .layoutWeight(1)
    .height('100%')
    .padding(CloudThemeToken.spacingCard)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
  }

  @Builder storageInfo() {
    Column({ space: CloudThemeToken.spacingPanel }) {
      Row() {
        Column({ space: CloudThemeToken.spacingXl }) {
          Text($r('app.string.storage_used'))
            .fontSize(CloudThemeToken.textSizeBodyPlus)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)

          Text(this.userStorage ? `${CommonUtil.formatBytes(this.userStorage.used)} / ${CommonUtil.formatBytes(this.userStorage.total)}` : '')
            .fontSize(CloudThemeToken.textSizeHeadline)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)

          Row({ space: CloudThemeToken.spacingSm }) {
            Text($r('app.string.storage_update_date'))
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
            Text(this.updateDate ? `${DateFormatUtil.format(this.updateDate, 'yyyy/MM/dd')}` : '')
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
          }
          .justifyContent(FlexAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Stack({alignContent: Alignment.Center}) {
          DataPanel({ values: [this.userStorage?.used ?? 0], max: this.userStorage?.total ?? 100, type: DataPanelType.Circle })
            .width(CloudThemeToken.panelLargeSize)
            .height(CloudThemeToken.cardHeight2xl)
            .strokeWidth(CloudThemeToken.storageProgressStrokeWidth)
            .valueColors([CloudThemeToken.primary])

          Text(this.getStoragePercentText())
            .fontSize(CloudThemeToken.textSizeBodyPlus)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: CloudThemeToken.spacingXl }) {
        Progress({value: this.userStorage?.used ?? 0, total: this.userStorage?.total ?? 100, type: ProgressType.Capsule})
          .width('100%')
          .height(CloudThemeToken.storageProgressHeight)
          .color(CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({ space: CloudThemeToken.spacingXs }) {
          Text($r('app.string.storage_available'))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
          Text(this.userStorage ? CommonUtil.formatBytes(this.userStorage.free) : '')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
          Blank()
          Image($r('app.media.ic_externaldrive_fill'))
            .width(CloudThemeToken.iconMd)
            .height(CloudThemeToken.iconMd)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .padding(CloudThemeToken.spacingPage)
    .width('100%')
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
  }

  getStoragePercentText(): string {
    if (!this.userStorage || this.userStorage.total <= 0) {
      return ''
    }
    return `${(this.userStorage.used * CloudThemeToken.percentageFull / this.userStorage.total).toFixed(1)}%`
  }

  @Builder logoutButton() {
    Button({type: ButtonType.Normal}) {
      Row({ space: CloudThemeToken.spacingCard }) {
        Image($r('app.media.ic_square_logout'))
          .width(CloudThemeToken.icon2xl)
          .height(CloudThemeToken.icon2xl)
          .fillColor(CloudThemeToken.danger)
          .draggable(false)

        Text($r('app.string.logout'))
          .fontColor(CloudThemeToken.danger)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight4xl)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
    .onClick(() => {
      showCloudConfirmDialog(this.getUIContext(), {
        title: $r('app.string.logout_confim'),
        confirmText: $r('app.string.dialog_logout'),
        onConfirm: () => {
          UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY)
          UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY)
          CloudRouter.resetToLogin()
        }
      })
    })
  }

  @Builder rowWithNext(icon: ResourceStr, backgroundColor: ResourceColor,
    title: ResourceStr, sub_title?: ResourceStr, onClickCallback?: ()=>void) {
    Button({type: ButtonType.Normal}) {
      Row({ space: CloudThemeToken.spacingCard }) {
        Image(icon)
          .width(CloudThemeToken.iconBoxXs)
          .height(CloudThemeToken.iconBoxXs)
          .borderRadius(CloudThemeToken.cardRadius)
          .padding(CloudThemeToken.spacingLg)
          .fillColor(CloudThemeToken.onPrimary)
          .backgroundColor(backgroundColor)
          .draggable(false)

        Text(title)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)

        if (sub_title) {
          Text(sub_title)
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
        }
        Image($r('app.media.ic_chevron_right'))
          .width(CloudThemeToken.iconXs)
          .height(CloudThemeToken.iconXs)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight4xl)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .onClick(() => {
      if (onClickCallback) {
        onClickCallback()
      }
    })
  }

  @Builder rowWithSelect(icon: ResourceStr, bgColor: ResourceColor,
    title: ResourceStr, currentValue: number,
    options: SelectOption[], onChange: (val: number) => void) {
    Row({ space: CloudThemeToken.spacingCard }) {
      Image(icon)
        .width(CloudThemeToken.iconBoxXs).height(CloudThemeToken.iconBoxXs).borderRadius(CloudThemeToken.cardRadius).padding(CloudThemeToken.spacingLg)
        .fillColor(CloudThemeToken.onPrimary).backgroundColor(bgColor)
        .draggable(false)

      Text(title)
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      Select(options)
        .value(currentValue.toString())
        .selected(currentValue - 1)
        .onSelect((index: number) => { onChange(index + 1); })
        .width(CloudThemeToken.mineSelectWidth)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight4xl)
    .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .alignItems(VerticalAlign.Center)
  }

  @Builder settingButton() {
    Column({ space: CloudThemeToken.spacingCard }) {
      this.rowWithNext($r('app.media.ic_privacy_secure'),
        CloudThemeToken.settingIconPrivacyBackground,
        $r('app.string.user_privacy_secure'),
        undefined,
        () => {
          this.openSettingsSheet(MineSheetType.PRIVACY)
        })
      this.rowWithNext($r('app.media.ic_theme_setting'),
        CloudThemeToken.settingIconThemeBackground,
        $r("app.string.user_theme_setting"),
        this.getThemeModeText(),
        () => {
          this.openSettingsSheet(MineSheetType.THEME)
        })
      this.rowWithNext($r('app.media.ic_more_setting'),
        CloudThemeToken.settingIconMoreBackground,
        $r('app.string.more_setting'),
        undefined,
        () => {
          this.openSettingsSheet(MineSheetType.MORE)
        })
      this.rowWithNext($r('app.media.ic_info_circle'),
        CloudThemeToken.settingIconAboutBackground,
        $r('app.string.about'),
        this.versionInfo,
        () => { CloudRouter.push(Constant.ABOUT_PAGE) }
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
    } else if (this.activeSheetType === MineSheetType.PRIVACY) {
      this.privacySettingsSheet()
    } else {
      this.moreSettingsSheet()
    }
  }

  @Builder privacySettingsSheet() {
    Column({ space: CloudThemeToken.spacingPage }) {
      this.sheetHeader($r('app.string.user_privacy_secure'), () => {
        this.closeSettingsSheet()
      })

      Column({ space: CloudThemeToken.spacingXs }) {
        Text(this.currentUser)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.currentUrl)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.getCredentialStatusText())
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.primary)
      }
      .width('100%')
      .padding(CloudThemeToken.spacingPanel)
      .alignItems(HorizontalAlign.Start)
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.surface)
      .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })

      this.privacyActionRow('刷新头像缓存', '重新获取当前账号头像', false, () => {
        this.refreshCurrentAvatarCache()
      })
      this.privacyActionRow(
        '系统认证保护',
        this.getSystemAuthDescription(),
        false,
        () => {
          this.toggleSystemAuth()
        })
      if (this.systemAuthEnabled) {
        this.privacyActionRow('立即验证', '测试当前人脸或指纹认证是否可用', false, () => {
          this.verifySystemAuth()
        })
      }
      this.privacyActionRow('清除头像缓存', '下次进入时重新加载头像', false, () => {
        this.clearCurrentAvatarCache()
      })
      this.privacyActionRow('删除当前登录凭证', '清除本机保存的 token 并重新登录', true, () => {
        this.deleteCurrentCredential()
      })
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder privacyActionRow(title: string, description: string, danger: boolean, onClick: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: CloudThemeToken.spacingSection }) {
        Column({ space: CloudThemeToken.spacingXs }) {
          Text(title)
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(danger ? CloudThemeToken.danger : CloudThemeToken.textPrimary)
          Text(description)
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Image($r('app.media.ic_chevron_right'))
          .width(CloudThemeToken.iconXs)
          .height(CloudThemeToken.iconXs)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight4xl)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(danger ? CloudThemeToken.dangerSoft : CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: danger ? CloudThemeToken.danger : CloudThemeToken.line })
    .onClick(onClick)
  }

  @Builder themeSettingsSheet() {
    Column({ space: CloudThemeToken.spacingPage }) {
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
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder moreSettingsSheet() {
    Column({ space: CloudThemeToken.spacingPage }) {
      this.sheetHeader($r('app.string.more_setting'), () => {
        this.closeSettingsSheet()
      })

      this.rowWithSelect(
        $r('app.media.ic_more_setting'),
        CloudThemeToken.settingIconMoreBackground,
        $r('app.string.upload_max_concurrent'),
        this.uploadMaxConcurrent,
        this.getUploadConcurrentOptions(),
        (val: number) => {
          this.uploadMaxConcurrent = this.normalizeUploadConcurrent(val);
          UserPreferences.putSync(
            Constant.USER_PREFERENCES,
            Constant.UPLOAD_MAX_CONCURRENT,
            this.uploadMaxConcurrent
          );
        }
      )
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  private normalizeUploadConcurrent(raw: number): number {
    if (typeof raw !== 'number') {
      return Constant.UPLOAD_CONCURRENT_DEFAULT
    }
    return Math.max(Constant.UPLOAD_CONCURRENT_MIN, Math.min(Constant.UPLOAD_CONCURRENT_MAX, raw))
  }

  private getUploadConcurrentOptions(): SelectOption[] {
    const options: SelectOption[] = []
    for (let value = Constant.UPLOAD_CONCURRENT_MIN; value <= Constant.UPLOAD_CONCURRENT_MAX; value++) {
      options.push({ value: value.toString() } as SelectOption)
    }
    return options
  }

  @Builder sheetHeader(title: ResourceStr, onClose: () => void) {
    Row() {
      Text(title)
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_xmark_circle_fill'))
          .width(CloudThemeToken.icon2xl)
          .height(CloudThemeToken.icon2xl)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width(CloudThemeToken.iconBoxSm)
      .height(CloudThemeToken.iconBoxSm)
      .borderRadius(CloudThemeToken.controlRadius)
      .backgroundColor(CloudThemeToken.surfaceSubtle)
      .onClick(onClose)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder themeOptionRow(title: ResourceStr, description: ResourceStr, mode: string) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Column({ space: CloudThemeToken.spacingXs }) {
        Text(title)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
        Text(description)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.themeMode === mode) {
        Image($r('app.media.ic_checkmark_circle'))
          .width(CloudThemeToken.icon2xl)
          .height(CloudThemeToken.icon2xl)
          .fillColor(CloudThemeToken.primary)
          .draggable(false)
      }
    }
    .width('100%')
    .height(CloudThemeToken.cardHeightSm)
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(this.themeMode === mode ? CloudThemeToken.primarySoft : CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: this.themeMode === mode ? CloudThemeToken.primary : CloudThemeToken.line })
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

  private getCurrentDbUserInfo(): DbUserInfo | null {
    return UserDatabase.getUserInfo(this.currentUser, this.currentUrl)
  }

  private getCredentialStatusText(): string {
    const dbUserInfo = this.getCurrentDbUserInfo()
    if (!dbUserInfo) {
      return '未找到本机登录凭证'
    }
    const expires = new Date(dbUserInfo.expires)
    if (expires.getTime() <= Date.now()) {
      return '登录凭证已过期'
    }
    return `登录凭证有效至 ${DateFormatUtil.format(expires, 'yyyy/MM/dd')}`
  }

  private refreshCurrentAvatarCache(): void {
    const dbUserInfo = this.getCurrentDbUserInfo()
    if (!dbUserInfo) {
      showToast('未找到当前账号')
      return
    }
    AvatarUtil.refreshDbUserAvatar(dbUserInfo)
      .then((pixMap?: PixelMap) => {
        if (pixMap) {
          this.userAvatar = pixMap
          showToast('头像缓存已刷新')
        } else {
          showToast('头像刷新失败')
        }
      })
      .catch((err: Error) => {
        console.error(TAG, `refresh avatar cache failed: ${err.message}`)
        showToast('头像刷新失败')
      })
  }

  private clearCurrentAvatarCache(): void {
    const dbUserInfo = this.getCurrentDbUserInfo()
    if (!dbUserInfo) {
      showToast('未找到当前账号')
      return
    }
    AvatarUtil.clearDbUserAvatar(dbUserInfo)
    this.userAvatar = undefined
    showToast('头像缓存已清除')
  }

  private getSystemAuthDescription(): string {
    if (this.systemAuthBusy) {
      return '正在等待系统认证'
    }
    return this.systemAuthEnabled ? '已开启，回到应用时需要人脸或指纹' : '未开启，可使用系统人脸或指纹保护应用'
  }

  private toggleSystemAuth(): void {
    if (this.systemAuthBusy) {
      return
    }
    if (this.systemAuthEnabled) {
      this.systemAuthEnabled = false
      AppLockUtil.setEnabled(false)
      showToast('已关闭系统认证保护')
      return
    }

    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (!context) {
      showToast('无法唤起系统认证')
      return
    }
    this.systemAuthBusy = true
    AppLockUtil.authenticateForSettings(context, '开启系统认证保护')
      .then((result: SystemAuthResult) => {
        this.systemAuthBusy = false
        if (result.success) {
          this.systemAuthEnabled = true
          AppLockUtil.setEnabled(true)
          showToast('已开启系统认证保护')
        } else {
          showToast(result.message.length > 0 ? result.message : '系统认证失败')
        }
      })
      .catch((err: Error) => {
        this.systemAuthBusy = false
        console.error(TAG, `enable system auth failed: ${err.message}`)
        showToast('系统认证失败')
      })
  }

  private verifySystemAuth(): void {
    if (this.systemAuthBusy) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (!context) {
      showToast('无法唤起系统认证')
      return
    }
    this.systemAuthBusy = true
    AppLockUtil.authenticateForSettings(context, '验证系统认证')
      .then((result: SystemAuthResult) => {
        this.systemAuthBusy = false
        showToast(result.success ? '系统认证可用' : (result.message.length > 0 ? result.message : '系统认证失败'))
      })
      .catch((err: Error) => {
        this.systemAuthBusy = false
        console.error(TAG, `verify system auth failed: ${err.message}`)
        showToast('系统认证失败')
      })
  }

  private deleteCurrentCredential(): void {
    showCloudConfirmDialog(this.getUIContext(), {
      title: '删除当前登录凭证',
      message: `${this.currentUser}\n${this.currentUrl}`,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        UserDatabase.deleteUserInfo(this.currentUser, this.currentUrl)
        UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY)
        UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY)
        this.closeSettingsSheet()
        CloudRouter.resetToLogin()
      }
    })
  }

  @Builder rowWithJump(icon: ResourceStr, backgroundColor: ResourceColor, title: ResourceStr, url: string) {
    Button({type: ButtonType.Normal}) {
      Row({ space: CloudThemeToken.spacingCard }) {
        Image(icon)
          .width(CloudThemeToken.icon4xl)
          .height(CloudThemeToken.icon4xl)
          .borderRadius(CloudThemeToken.controlRadiusXl)
          .padding(CloudThemeToken.spacingSm)
          .fillColor(CloudThemeToken.onPrimary)
          .backgroundColor(backgroundColor)
          .draggable(false)

        Hyperlink(url, title)
          .height(CloudThemeToken.iconXl)
          .color(CloudThemeToken.textPrimary)
          .draggable(false)
          .layoutWeight(1)

        Image($r('app.media.ic_web_jump'))
          .width(CloudThemeToken.iconMd)
          .height(CloudThemeToken.iconMd)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight3xl)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .onClick(() => {
      this.webUrl = url
      this.webShow = true
    })
  }

  @Builder webButton() {
    Column({ space: CloudThemeToken.spacingCard }) {
      this.rowWithJump($r('app.media.ic_feedback'),
        CloudThemeToken.settingIconWebJumpBackground,
        $r('app.string.feedback'),
        'https://gitee.com/larriti/cloudrs-ohos/issues'
      )
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }
}
