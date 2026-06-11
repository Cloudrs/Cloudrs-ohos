import { DbUserInfo, SiteConfig, UserInfo, UserSetting, UserStorage } from "../../model/net/ApiTypes";
import { AboutPage } from "../AboutPage";
import Constant from "../../model/Constant";
import UserDatabase from "../../model/UserDatabase";
import UserPreferences from "../../model/UserPreferences";
import { CloudApi } from "../../model/net/CloudApi";
import { CommonUtil } from "../../utils/CommonUtil";
import { CloudThemeToken } from "../../model/CloudTheme";
import { CloudScaffold } from "../../components/CloudScaffold";
import { UserSwitchSheet } from "../../components/UserSwitchSheet";
import { FeedbackSheet } from "../../components/FeedbackSheet";
import { LogViewerSheet } from "../../components/LogViewerSheet";
import { SectionHeader } from "../../components/SectionHeader";
import { common, ConfigurationConstant } from "@kit.AbilityKit";
import { DateFormatUtil } from "../../utils/DateFormatUtil";
import { showCloudConfirmDialog } from "../../utils/CloudDialogUtil";
import { CloudRouter } from "../../utils/CloudRouter";
import { AvatarUtil } from "../../utils/AvatarUtil";
import FeedbackUtil from "../../utils/FeedbackUtil";
import AppLogger from "../../utils/AppLogger";
import { showToast } from "../../utils/ToastUtil";
import { AppLockUtil } from "../../utils/AppLockUtil";
import { SystemAuthResult } from "../../utils/SystemAuthUtil";
import { BusinessError, pasteboard } from "@kit.BasicServicesKit";
import { PhotoBackupSettingsSheet } from '../../components/PhotoBackupSettingsSheet';
import { PathSelectSheet } from '../../components/PathSelectSheet';
import { PhotoBackupSettingsStore, PHOTO_BACKUP_ENABLED_KEY } from '../../model/PhotoBackupSettingsStore';
import { PhotoBackupSettings } from '../../model/PhotoBackupModel';

const TAG:string = 'TabMine'
const MINE_SETTINGS_REFRESH_INTERVAL_MS: number = 30000
const MINE_SETTINGS_REFRESH_DELAY_MS: number = 360

enum MineSheetType {
  NONE = 'none',
  MORE = 'more',
  THEME = 'theme',
  PRIVACY = 'privacy',
  PHOTO_BACKUP = 'photo_backup'
}

enum MineMetricType {
  USER_ID = 'user_id',
  USER_GROUP = 'user_group',
  USER_DAYS = 'user_days'
}

class MinePageCache {
  static key: string = ''
  static siteConfig?: SiteConfig = undefined
  static userStorage?: UserStorage = undefined
  static userSetting?: UserSetting = undefined
  static updateDate?: Date = undefined
  static userAvatar?: PixelMap = undefined
  static userAvatarCacheUri: string = ''
  static diffDays: number = 0
  static cachedUserId: string = ''
  static cachedUserName: string = ''
  static cachedNickname: string = ''
  static cachedGroupName: string = ''
  static cachedDiffDays: number = 0
  static lastRefreshAt: number = 0
}

@Component
export struct TabMine {
  @Link overLap: boolean
  @Watch('onActiveChanged')
  @Prop isActive: boolean = false
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0
  @State siteConfig?: SiteConfig = undefined
  @State userStorage?: UserStorage = undefined
  @State userSetting?: UserSetting = undefined
  @State currentUser: string = ''
  @State currentUrl: string = ''
  @State updateDate?: Date = undefined
  @State userAvatar?: PixelMap = undefined
  @State userAvatarCacheUri: string = ''
  @State diffDays: number = 0
  @State cachedUserId: string = ''
  @State cachedUserName: string = ''
  @State cachedNickname: string = ''
  @State cachedGroupName: string = ''
  @State cachedDiffDays: number = 0
  private avatarSize: number = CloudThemeToken.avatarLargeSize
  @State showUserSwitchSheet: boolean = false
  @State showSettingsSheet: boolean = false
  @State showPrivacySheet: boolean = false
  @State showThemeSheet: boolean = false
  @State showMoreSettingsSheet: boolean = false
  @State showFeedbackSheet: boolean = false
  @State showLogViewerSheet: boolean = false
  @State showAboutSheet: boolean = false
  @State activeSheetType: MineSheetType = MineSheetType.NONE
  @State showMetrics: boolean = false
  @State themeMode: string = Constant.APP_THEME_LIGHT
  private scroller: Scroller = new Scroller;
  @State versionInfo: string = ''
  @State uploadMaxConcurrent: number = 3
  @State systemAuthEnabled: boolean = false
  @State systemAuthBusy: boolean = false
  private settingsRefreshTimer: number = -1
  @State photoBackupEnabledText: string = '未开启'
  @StorageProp(PHOTO_BACKUP_ENABLED_KEY) @Watch('onPhotoBackupEnabledChanged') photoBackupEnabledMirror: boolean = false;
  @State showPhotoBackupPathSheet: boolean = false

  aboutToAppear() {
    this.loadLocalPreferences()
    if (this.isActive) {
      this.loadMineData()
    }
  }

  aboutToDisappear(): void {
    this.cancelScheduledUserSettingsRefresh()
    this.overLap = true
  }

  private onActiveChanged(): void {
    if (!this.isActive) {
      this.cancelScheduledUserSettingsRefresh()
      return
    }
    this.loadMineData()
  }

  private loadLocalPreferences(): void {
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
    const pbSettings = PhotoBackupSettingsStore.load();
    this.photoBackupEnabledText = pbSettings.enabled ? '已开启' : '未开启';
    PhotoBackupSettingsStore.mirror(pbSettings);
  }

  private onPhotoBackupEnabledChanged(): void {
    this.photoBackupEnabledText = this.photoBackupEnabledMirror ? '已开启' : '未开启';
  }

  private loadMineData(): void {
    this.currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY) as string
    this.currentUrl = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string
    this.hydrateMineCacheOrReset()
    const shouldRefresh = this.shouldRefreshUserSettings()
    this.loadCachedUserInfo()
    if (shouldRefresh) {
      this.scheduleUserSettingsRefresh()
    }
  }

  private scheduleUserSettingsRefresh(): void {
    this.cancelScheduledUserSettingsRefresh()
    const cacheKey = this.getMineCacheKey()
    this.settingsRefreshTimer = setTimeout(() => {
      this.settingsRefreshTimer = -1
      if (cacheKey === this.getMineCacheKey()) {
        this.getUserSettings()
      }
    }, MINE_SETTINGS_REFRESH_DELAY_MS)
  }

  private cancelScheduledUserSettingsRefresh(): void {
    if (this.settingsRefreshTimer >= 0) {
      clearTimeout(this.settingsRefreshTimer)
      this.settingsRefreshTimer = -1
    }
  }

  getUserSettings() {
    const cacheKey = this.getMineCacheKey()
    this.markMineSettingsRefresh()
    this.fetchMineRemoteData(cacheKey, true)
  }

  private fetchMineRemoteData(cacheKey: string, allowSessionRefresh: boolean): void {
    CloudApi.getSiteConfig({
      onSuccess: (data: SiteConfig) => {
        if (cacheKey !== this.getMineCacheKey()) {
          return
        }
        if (allowSessionRefresh && this.shouldRefreshV4SessionFromSiteConfig(data)) {
          this.refreshV4Session(cacheKey, () => {
            this.fetchMineRemoteData(cacheKey, false)
          })
          return
        }
        this.applySiteConfig(data)
        this.fetchUserSettingAndStorage(cacheKey)
      },
      onFailure: (msg) => {
        if (allowSessionRefresh && this.shouldRefreshStoredV4Session() && this.isUnauthorizedMessage(msg)) {
          this.refreshV4Session(cacheKey, () => {
            this.fetchMineRemoteData(cacheKey, false)
          })
          return
        }
        AppLogger.error(TAG, `SiteConfig get failed, ${msg}`)
        this.fetchUserSettingAndStorage(cacheKey)
      }
    })
  }

  private fetchUserSettingAndStorage(cacheKey: string): void {
    CloudApi.userSetting({
      onSuccess: (data: UserSetting) => {
        if (cacheKey !== this.getMineCacheKey()) {
          return
        }
        this.userSetting = data
        this.saveMineCache()
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, `Setting get failed, ${msg}`)
      }
    })

    CloudApi.userStorage({
      onSuccess: (data: UserStorage) => {
        if (cacheKey !== this.getMineCacheKey()) {
          return
        }
        this.userStorage = data
        this.updateDate = new Date()
        this.saveMineCache()
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, `Storage get failed, ${msg}`)
      }
    })
  }

  build() {
    Stack() {
      CloudScaffold({
        scroller: this.scroller,
        topPadding: CloudThemeToken.zero,
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

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showFeedbackSheet, this.feedbackSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          showClose: false,
          backgroundColor: CloudThemeToken.background,
          preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
          width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth)
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showLogViewerSheet, this.logViewerSheet(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: false,
          backgroundColor: CloudThemeToken.background,
          preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
          width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth)
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAboutSheet, this.aboutSheet(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          title: { title: $r('app.string.about') },
          showClose: true,
          backgroundColor: CloudThemeToken.background,
          preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
          width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
          onDisappear: () => {
            this.showAboutSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSettingsSheet, this.settingsSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          showClose: false,
          backgroundColor: CloudThemeToken.background,
          preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
          width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
          onDisappear: () => {
            this.finishCloseSettingsSheet()
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showPhotoBackupPathSheet, this.photoBackupPathSheet(), {
          showClose: false,
          backgroundColor: CloudThemeToken.background,
          preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
          width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
          onDisappear: () => {
            this.showPhotoBackupPathSheet = false
          }
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder photoBackupPathSheet() {
    PathSelectSheet({
      title: $r('app.string.backup_to'),
      filterDirId: '',
      onClose: (isFinished: boolean, path?: string) => {
        this.showPhotoBackupPathSheet = false
        if (isFinished && path && path.length > 0) {
          const s: PhotoBackupSettings = PhotoBackupSettingsStore.load()
          s.remotePath = path
          PhotoBackupSettingsStore.save(s)
        }
      }
    })
  }

  private applySiteConfig(data: SiteConfig): void {
    this.siteConfig = data
    this.diffDays = this.getCreatedDays(data.user.created_at)
    this.refreshCachedUserInfo(data.user)
    this.saveMineCache()
  }

  private refreshV4Session(cacheKey: string, onReady: () => void): void {
    const dbUserInfo = this.getCurrentDbUserInfo()
    if (!dbUserInfo || !this.isV4DbUser(dbUserInfo) || dbUserInfo.refresh_token.length === 0) {
      onReady()
      return
    }
    CloudApi.loginWithRefreshToken(dbUserInfo.url, dbUserInfo.refresh_token, {
      onSuccess: (userInfo: UserInfo) => {
        if (cacheKey !== this.getMineCacheKey()) {
          return
        }
        const cookie = AppStorage.get<string>(Constant.CLOUD_COOKIE) ?? dbUserInfo.cookie
        const expires = AppStorage.get<string>(Constant.CLOUD_COOKIE_EXPIRES) ?? dbUserInfo.expires
        const refreshToken = AppStorage.get<string>(Constant.CLOUD_REFRESH_TOKEN) ?? dbUserInfo.refresh_token
        dbUserInfo.cookie = cookie
        dbUserInfo.expires = expires
        dbUserInfo.refresh_token = refreshToken
        if (!this.isAnonymousUserInfo(userInfo)) {
          dbUserInfo.userinfo = userInfo
        }
        UserDatabase.insertUserInfo(dbUserInfo)
        onReady()
      },
      onFailure: (msg: string) => {
        AppLogger.error(TAG, `refresh v4 session failed, ${msg}`)
        onReady()
      }
    })
  }

  private shouldRefreshV4SessionFromSiteConfig(data: SiteConfig): boolean {
    return this.shouldRefreshStoredV4Session() && this.isAnonymousUserInfo(data.user)
  }

  private shouldRefreshStoredV4Session(): boolean {
    const dbUserInfo = this.getCurrentDbUserInfo()
    return !!dbUserInfo && this.isV4DbUser(dbUserInfo) && dbUserInfo.refresh_token.length > 0
  }

  private isV4DbUser(dbUserInfo: DbUserInfo): boolean {
    return dbUserInfo.cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX)
  }

  private isAnonymousUserInfo(userInfo: UserInfo): boolean {
    return userInfo.anonymous === true || this.isInvalidCreatedAt(userInfo.created_at)
  }

  private isUnauthorizedMessage(msg: string): boolean {
    return msg.toLowerCase().indexOf('unauthorized') >= 0 || msg.indexOf('登录') >= 0
  }

  private getCreatedDays(createdAt?: string): number {
    if (!createdAt || this.isInvalidCreatedAt(createdAt)) {
      return 0
    }
    const createdDate = new Date(createdAt)
    return CommonUtil.getDaysDifference(createdDate, new Date())
  }

  private isInvalidCreatedAt(createdAt?: string): boolean {
    if (!createdAt || createdAt.length === 0) {
      return true
    }
    const createdDate = new Date(createdAt)
    return Number.isNaN(createdDate.getTime()) || createdDate.getFullYear() <= 1971
  }

  private getMineCacheKey(): string {
    return `${this.currentUrl}|${this.currentUser}`
  }

  private hydrateMineCacheOrReset(): void {
    if (MinePageCache.key === this.getMineCacheKey()) {
      this.siteConfig = MinePageCache.siteConfig
      this.userStorage = MinePageCache.userStorage
      this.userSetting = MinePageCache.userSetting
      this.updateDate = MinePageCache.updateDate
      this.userAvatar = MinePageCache.userAvatar
      this.userAvatarCacheUri = MinePageCache.userAvatarCacheUri
      this.diffDays = MinePageCache.diffDays
      this.cachedUserId = MinePageCache.cachedUserId
      this.cachedUserName = MinePageCache.cachedUserName
      this.cachedNickname = MinePageCache.cachedNickname
      this.cachedGroupName = MinePageCache.cachedGroupName
      this.cachedDiffDays = MinePageCache.cachedDiffDays
      return
    }
    this.resetMineState()
  }

  private resetMineState(): void {
    this.siteConfig = undefined
    this.userStorage = undefined
    this.userSetting = undefined
    this.updateDate = undefined
    this.userAvatar = undefined
    this.userAvatarCacheUri = ''
    this.diffDays = 0
    this.cachedUserId = ''
    this.cachedUserName = ''
    this.cachedNickname = ''
    this.cachedGroupName = ''
    this.cachedDiffDays = 0
  }

  private saveMineCache(): void {
    MinePageCache.key = this.getMineCacheKey()
    MinePageCache.siteConfig = this.siteConfig
    MinePageCache.userStorage = this.userStorage
    MinePageCache.userSetting = this.userSetting
    MinePageCache.updateDate = this.updateDate
    MinePageCache.userAvatar = this.userAvatar
    MinePageCache.userAvatarCacheUri = this.userAvatarCacheUri
    MinePageCache.diffDays = this.diffDays
    MinePageCache.cachedUserId = this.cachedUserId
    MinePageCache.cachedUserName = this.cachedUserName
    MinePageCache.cachedNickname = this.cachedNickname
    MinePageCache.cachedGroupName = this.cachedGroupName
    MinePageCache.cachedDiffDays = this.cachedDiffDays
  }

  private shouldRefreshUserSettings(): boolean {
    return MinePageCache.key !== this.getMineCacheKey() ||
      new Date().getTime() - MinePageCache.lastRefreshAt >= MINE_SETTINGS_REFRESH_INTERVAL_MS
  }

  private markMineSettingsRefresh(): void {
    MinePageCache.key = this.getMineCacheKey()
    MinePageCache.lastRefreshAt = new Date().getTime()
  }

  loadCachedUserInfo(): void {
    const dbUserInfo = UserDatabase.getUserInfo(this.currentUser, this.currentUrl)
    if (!dbUserInfo || !dbUserInfo.userinfo) {
      return
    }
    this.cachedUserId = dbUserInfo.userinfo.id ?? ''
    this.cachedUserName = dbUserInfo.userinfo.user_name ?? ''
    this.cachedNickname = dbUserInfo.userinfo.nickname ?? ''
    this.cachedGroupName = dbUserInfo.userinfo.group?.name ?? ''
    this.userAvatarCacheUri = AvatarUtil.getDbUserAvatarCacheUri(dbUserInfo)
    const memoryAvatar = AvatarUtil.getMemoryCachedDbUserAvatar(dbUserInfo)
    if (memoryAvatar) {
      this.userAvatar = memoryAvatar
    }
    console.info(TAG, `Mine avatar cached user loaded, memory=${!!memoryAvatar}, cacheUri=${this.userAvatarCacheUri.length > 0}`)
    if (dbUserInfo.userinfo.created_at && dbUserInfo.userinfo.created_at.length > 0) {
      this.cachedDiffDays = this.getCreatedDays(dbUserInfo.userinfo.created_at)
    }
    if (!this.userAvatar && this.userAvatarCacheUri.length === 0) {
      this.loadAvatar(dbUserInfo, false)
    }
    this.saveMineCache()
  }

  refreshCachedUserInfo(userInfo: UserInfo): void {
    const dbUserInfo = UserDatabase.getUserInfo(this.currentUser, this.currentUrl)
    if (!dbUserInfo) {
      return
    }
    const previousUserId = dbUserInfo.userinfo?.id ?? ''
    const previousAvatar = dbUserInfo.userinfo?.avatar ?? ''
    dbUserInfo.userinfo = userInfo
    UserDatabase.insertUserInfo(dbUserInfo)
    this.cachedUserId = userInfo.id ?? ''
    this.cachedUserName = userInfo.user_name ?? ''
    this.cachedNickname = userInfo.nickname ?? ''
    this.cachedGroupName = userInfo.group?.name ?? ''
    this.userAvatarCacheUri = AvatarUtil.getDbUserAvatarCacheUri(dbUserInfo)
    if (userInfo.created_at && userInfo.created_at.length > 0) {
      this.cachedDiffDays = this.getCreatedDays(userInfo.created_at)
    }
    const avatarChanged = previousUserId !== (userInfo.id ?? '') || previousAvatar !== (userInfo.avatar ?? '')
    console.info(TAG, `Mine avatar refresh info, changed=${avatarChanged}, cacheUri=${this.userAvatarCacheUri.length > 0}`)
    if (avatarChanged) {
      this.loadAvatar(dbUserInfo, avatarChanged)
    } else if (this.userAvatar) {
      this.loadAvatar(dbUserInfo, true)
    } else if (this.userAvatarCacheUri.length > 0) {
      this.loadAvatar(dbUserInfo, true)
    } else {
      this.loadAvatar(dbUserInfo, false)
    }
    this.saveMineCache()
  }

  private loadCachedAvatar(dbUserInfo: DbUserInfo): void {
    const cacheKey = this.getMineCacheKey()
    AvatarUtil.loadCachedDbUserAvatar(dbUserInfo)
      .then((pixMap?: PixelMap) => {
        if (cacheKey !== this.getMineCacheKey()) {
          return
        }
        if (pixMap) {
          this.userAvatar = pixMap
          this.userAvatarCacheUri = AvatarUtil.getDbUserAvatarCacheUri(dbUserInfo)
          this.saveMineCache()
        } else {
          this.loadAvatar(dbUserInfo, false)
        }
      })
      .catch((err: Error) => {
        AppLogger.warn(TAG, `load cached avatar failed: ${err.message}`)
        this.loadAvatar(dbUserInfo, false)
      })
  }

  private loadAvatar(dbUserInfo: DbUserInfo, forceRefresh: boolean): void {
    const cacheKey = this.getMineCacheKey()
    const start = Date.now()
    console.info(TAG, `Mine avatar load start, force=${forceRefresh}`)
    AvatarUtil.loadDbUserAvatar(dbUserInfo, forceRefresh)
      .then((pixMap?: PixelMap) => {
        if (cacheKey !== this.getMineCacheKey()) {
          return
        }
        console.info(TAG, `Mine avatar load end, ok=${!!pixMap}, cost=${Date.now() - start}ms`)
        if (pixMap) {
          this.userAvatar = pixMap
          this.userAvatarCacheUri = AvatarUtil.getDbUserAvatarCacheUri(dbUserInfo)
          this.saveMineCache()
        }
      })
      .catch((err: Error) => {
        AppLogger.error(TAG, `User avatar get failed, ${err.message}`)
      })
  }

  @Builder userInfo() {
    Column() {
      Row({ space: CloudThemeToken.spacingPanel }) {
        Stack() {
          Text(this.getAvatarFallbackText())
            .fontSize(this.avatarSize * 0.36)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.primary)
          if (this.userAvatarCacheUri.length > 0) {
            Image(this.userAvatarCacheUri)
              .width(this.avatarSize)
              .height(this.avatarSize)
              .objectFit(ImageFit.Cover)
              .syncLoad(true)
              .borderRadius(this.avatarSize / CloudThemeToken.halfDivisor)
              .draggable(false)
          }
          if (this.userAvatar) {
            Image(this.userAvatar)
              .width(this.avatarSize)
              .height(this.avatarSize)
              .objectFit(ImageFit.Cover)
              .borderRadius(this.avatarSize / CloudThemeToken.halfDivisor)
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
          Text(this.getNicknameText())
            .fontSize(CloudThemeToken.textSizeHero)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})

          Text(this.getUserNameText())
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})

          Row({ space: CloudThemeToken.spacingCard }) {
            Text(this.getGroupBadgeText())
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.primary)
              .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard, top: CloudThemeToken.spacingXs, bottom: CloudThemeToken.spacingXs })
              .borderRadius(CloudThemeToken.controlRadius)
              .backgroundColor(CloudThemeToken.primarySoft)

            Image($r('app.media.ic_chevron_down'))
              .width(CloudThemeToken.iconBoxXs - 12)
              .height(CloudThemeToken.iconBoxXs - 12)
              .fillColor(CloudThemeToken.onPrimary)
              .rotate({ angle: this.showMetrics ? 180 : 0 })
              .padding(CloudThemeToken.spacingXs)
              .borderRadius(CloudThemeToken.controlRadius)
              .backgroundColor(CloudThemeToken.primary)
              .draggable(false)
              .onClick(() => {
                this.getUIContext().animateTo({
                  duration: CloudThemeToken.defaultAnimationDuration,
                  curve: Curve.EaseOut
                }, () => {
                  this.showMetrics = !this.showMetrics
                })
              })
          }
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.openUserSwitchSheet()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: CloudThemeToken.spacingCard }) {
        this.metricCell($r('app.string.user_id'), MineMetricType.USER_ID)
        this.metricCell($r('app.string.user_group'), MineMetricType.USER_GROUP)
        this.metricCell($r('app.string.user_days'), MineMetricType.USER_DAYS)
      }
      .width('100%')
      .height(this.showMetrics ? CloudThemeToken.cardHeightLg : 0)
      .margin({ top: this.showMetrics ? CloudThemeToken.spacingPage : 0 })
      .opacity(this.showMetrics ? 1 : 0)
      .clip(true)
    }
    .padding(CloudThemeToken.spacingPage)
      .width('100%')
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.surface)
  }

  @Builder switchAccountAction() {
    Row({ space: CloudThemeToken.spacingCard }) {
      Image($r('app.media.ic_person'))
        .width(CloudThemeToken.iconBoxXs)
        .height(CloudThemeToken.iconBoxXs)
        .borderRadius(CloudThemeToken.cardRadius)
        .padding(CloudThemeToken.spacingLg)
        .fillColor(CloudThemeToken.onPrimary)
        .backgroundColor(CloudThemeToken.settingIconPrivacyBackground)
        .draggable(false)
      Text('切换账号')
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)
      Image($r('app.media.ic_chevron_right'))
        .width(CloudThemeToken.iconXs)
        .height(CloudThemeToken.iconXs)
        .fillColor(CloudThemeToken.textSecondary)
        .draggable(false)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight4xl)
    .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openUserSwitchSheet()
    })
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

  getNicknameText(): string {
    if (this.siteConfig?.user.nickname && this.siteConfig.user.nickname.length > 0) {
      return this.siteConfig.user.nickname
    }
    if (this.cachedNickname.length > 0) {
      return this.cachedNickname
    }
    return this.currentUser.length > 0 ? this.currentUser : '-'
  }

  getAvatarFallbackText(): string {
    const text = this.getNicknameText()
    return text.length > 0 && text !== '-' ? text.substring(0, 1).toUpperCase() : 'C'
  }

  getUserNameText(): string {
    if (this.siteConfig?.user.user_name && this.siteConfig.user.user_name.length > 0) {
      return this.siteConfig.user.user_name
    }
    if (this.cachedUserName.length > 0) {
      return this.cachedUserName
    }
    return this.currentUser.length > 0 ? this.currentUser : '-'
  }

  getGroupNameText(): string {
    if (this.siteConfig?.user.group?.name && this.siteConfig.user.group.name.length > 0) {
      return this.siteConfig.user.group.name
    }
    return this.cachedGroupName.length > 0 ? this.cachedGroupName : '-'
  }

  getGroupBadgeText(): string {
    const groupName = this.getGroupNameText()
    return groupName === '-' ? '' : groupName
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

  private getMetricText(type: MineMetricType): string {
    switch (type) {
      case MineMetricType.USER_ID:
        return this.getUserIdText()
      case MineMetricType.USER_GROUP:
        return this.getGroupNameText()
      case MineMetricType.USER_DAYS:
        return this.getUserDaysText()
      default:
        return '-'
    }
  }

  @Builder metricCell(label: ResourceStr, type: MineMetricType) {
    Column({ space: CloudThemeToken.spacingMd }) {
      Text(label)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
      Text(this.getMetricText(type))
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
    .height(CloudThemeToken.rowHeight4xl)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
    .alignItems(VerticalAlign.Center)
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
    .height(CloudThemeToken.rowHeight4xl)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (onClickCallback) {
        onClickCallback()
      }
    })
  }

  @Builder rowWithSelect(title: ResourceStr) {
    Row({ space: CloudThemeToken.spacingCard }) {
      Column({ space: CloudThemeToken.spacingSm }) {
        Text(title)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)

        Text('当前 ' + this.uploadMaxConcurrent.toString() + ' 个任务同时上传')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        this.concurrentStepButton('-', this.uploadMaxConcurrent <= Constant.UPLOAD_CONCURRENT_MIN, () => {
          this.changeUploadMaxConcurrent(-1)
        })

        Text(this.uploadMaxConcurrent.toString())
          .width(CloudThemeToken.rowHeightMd)
          .height(CloudThemeToken.rowHeightSm)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .textAlign(TextAlign.Center)

        this.concurrentStepButton('+', this.uploadMaxConcurrent >= Constant.UPLOAD_CONCURRENT_MAX, () => {
          this.changeUploadMaxConcurrent(1)
        })
      }
      .height(CloudThemeToken.rowHeight2xl)
      .padding({ left: CloudThemeToken.spacingSm, right: CloudThemeToken.spacingSm })
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight4xl)
    .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .alignItems(VerticalAlign.Center)
  }

  @Builder concurrentStepButton(text: string, disabled: boolean, onClick: () => void) {
    Text(text)
      .width(CloudThemeToken.rowHeightSm)
      .height(CloudThemeToken.rowHeightSm)
      .fontSize(CloudThemeToken.textSizeLarge)
      .fontWeight(FontWeight.Bold)
      .fontColor(disabled ? CloudThemeToken.textSecondary : CloudThemeToken.textPrimary)
      .textAlign(TextAlign.Center)
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .opacity(disabled ? CloudThemeToken.disabledOpacity : CloudThemeToken.fullOpacity)
      .onClick(() => {
        if (!disabled) {
          onClick()
        }
      })
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
      this.rowWithNext($r('app.media.ic_externaldrive_fill'),
        CloudThemeToken.settingIconPhotoBackupBackground,
        '相册备份',
        this.photoBackupEnabledText,
        () => {
          this.openSettingsSheet(MineSheetType.PHOTO_BACKUP)
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
        () => { this.showAboutSheet = true }
      )
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  private openSettingsSheet(type: MineSheetType): void {
    this.activeSheetType = type
    this.showUserSwitchSheet = false
    this.showPrivacySheet = false
    this.showThemeSheet = false
    this.showMoreSettingsSheet = false
    this.showPhotoBackupPathSheet = false
    if (type === MineSheetType.PRIVACY) {
      this.syncSystemAuthState()
    }
    if (type === MineSheetType.THEME) {
      this.showThemeSheet = true
      this.showSettingsSheet = true
      return
    }
    if (type === MineSheetType.MORE) {
      this.showMoreSettingsSheet = true
      this.showSettingsSheet = true
      return
    }
    if (type === MineSheetType.PHOTO_BACKUP) {
      this.showSettingsSheet = true
      return
    }
    this.showPrivacySheet = true
    this.showSettingsSheet = true
  }

  private openUserSwitchSheet(): void {
    this.activeSheetType = MineSheetType.NONE
    this.showPrivacySheet = false
    this.showThemeSheet = false
    this.showMoreSettingsSheet = false
    this.showUserSwitchSheet = true
    this.showSettingsSheet = true
  }

  private closeSettingsSheet(): void {
    this.showSettingsSheet = false
  }

  private finishCloseSettingsSheet(): void {
    if (this.showSettingsSheet) {
      return
    }
    this.showUserSwitchSheet = false
    this.showPrivacySheet = false
    this.showThemeSheet = false
    this.showMoreSettingsSheet = false
    this.activeSheetType = MineSheetType.NONE
  }

  private closeFeedbackSheet(): void {
    this.showFeedbackSheet = false
  }

  @Builder userSwitchSheet() {
    UserSwitchSheet({
      currentUser: this.currentUser,
      currentUrl: this.currentUrl,
      onSelect: (user: DbUserInfo) => {
        if (CloudRouter.switchToUser(user.username, user.url, true)) {
          this.closeSettingsSheet()
          this.loadMineData()
        }
      },
      onClose: () => {
        this.closeSettingsSheet()
      }
    })
  }

  @Builder userSwitchOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.overlayScrim)
        .onClick(() => {
          this.showUserSwitchSheet = false
        })

      Column() {
        this.userSwitchSheet()
      }
      .width('100%')
      .padding({
        bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
      })
      .constraintSize({ minHeight: CloudThemeToken.detailSheetMinHeight })
      .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
      .backgroundColor(CloudThemeToken.background)
    }
    .width('100%')
    .height('100%')
    .zIndex(CloudThemeToken.overlayZIndex)
  }

  @Builder settingsSheet() {
    if (this.showUserSwitchSheet) {
      this.userSwitchSheet()
    } else if (this.activeSheetType === MineSheetType.THEME) {
      this.themeSettingsSheet()
    } else if (this.activeSheetType === MineSheetType.PRIVACY) {
      this.privacySettingsSheet()
    } else if (this.activeSheetType === MineSheetType.PHOTO_BACKUP) {
      this.photoBackupSheet()
    } else {
      this.moreSettingsSheet()
    }
  }

  @Builder photoBackupSheet() {
    PhotoBackupSettingsSheet({
      onClose: () => { this.closeSettingsSheet() },
      onPickPath: () => { this.showPhotoBackupPathSheet = true }
    })
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

      this.systemAuthActionRow()
      if (this.systemAuthEnabled) {
        this.privacyActionRow('立即验证', '测试当前人脸或指纹认证是否可用', false, () => {
          this.verifySystemAuth()
        })
      }
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
    .constraintSize({ minHeight: CloudThemeToken.detailSheetMinHeight })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder privacyActionRow(title: string, description: string, danger: boolean, onClick: () => void) {
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
    .height(CloudThemeToken.rowHeight4xl)
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
    .alignItems(VerticalAlign.Center)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(danger ? CloudThemeToken.dangerSoft : CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: danger ? CloudThemeToken.danger : CloudThemeToken.line })
    .onClick(onClick)
  }

  @Builder systemAuthActionRow() {
    Row({ space: CloudThemeToken.spacingSection }) {
      Column({ space: CloudThemeToken.spacingXs }) {
        Text('系统认证保护')
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
        Text(this.getSystemAuthDescription())
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(this.systemAuthEnabled ? CloudThemeToken.success : CloudThemeToken.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.systemAuthBusy ? '处理中' : (this.systemAuthEnabled ? '已开启' : '未开启'))
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.systemAuthEnabled ? CloudThemeToken.success : CloudThemeToken.textSecondary)
        .padding({ left: CloudThemeToken.spacingLg, right: CloudThemeToken.spacingLg })
        .height(CloudThemeToken.rowHeightSm)
        .borderRadius(CloudThemeToken.controlRadiusRoundMd)
        .backgroundColor(this.systemAuthEnabled ? CloudThemeToken.successSoft : CloudThemeToken.surfaceSubtle)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight4xl)
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
    .alignItems(VerticalAlign.Center)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(this.systemAuthEnabled ? CloudThemeToken.successSoft : CloudThemeToken.surface)
    .border({
      width: CloudThemeToken.lineWidth,
      color: this.systemAuthEnabled ? CloudThemeToken.success : CloudThemeToken.line
    })
    .opacity(this.systemAuthBusy ? CloudThemeToken.disabledOpacity : CloudThemeToken.fullOpacity)
    .onClick(() => {
      this.toggleSystemAuth()
    })
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
    .constraintSize({ minHeight: CloudThemeToken.detailSheetMinHeight })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder moreSettingsSheet() {
    Column({ space: CloudThemeToken.spacingPage }) {
      this.sheetHeader($r('app.string.more_setting'), () => {
        this.closeSettingsSheet()
      })

      this.rowWithSelect($r('app.string.upload_max_concurrent'))
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
    .constraintSize({ minHeight: CloudThemeToken.detailSheetMinHeight })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  private normalizeUploadConcurrent(raw: number): number {
    if (typeof raw !== 'number') {
      return Constant.UPLOAD_CONCURRENT_DEFAULT
    }
    return Math.max(Constant.UPLOAD_CONCURRENT_MIN, Math.min(Constant.UPLOAD_CONCURRENT_MAX, raw))
  }

  private changeUploadMaxConcurrent(delta: number): void {
    this.uploadMaxConcurrent = this.normalizeUploadConcurrent(this.uploadMaxConcurrent + delta)
    UserPreferences.putSync(
      Constant.USER_PREFERENCES,
      Constant.UPLOAD_MAX_CONCURRENT,
      this.uploadMaxConcurrent
    )
  }

  @Builder sheetHeader(title: ResourceStr, onClose: () => void) {
    Row() {
      Text(title)
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_xmark_bold'))
          .width(CloudThemeToken.sheetActionIconSize)
          .height(CloudThemeToken.sheetActionIconSize)
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

  @Builder sheetSubHeader(title: ResourceStr, onBack: () => void, onClose: () => void) {
    Row({ space: CloudThemeToken.spacingMd }) {
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_chevron_left'))
          .width(CloudThemeToken.iconXl)
          .height(CloudThemeToken.iconXl)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width(CloudThemeToken.iconBoxSm)
      .height(CloudThemeToken.iconBoxSm)
      .borderRadius(CloudThemeToken.controlRadius)
      .backgroundColor(CloudThemeToken.surfaceSubtle)
      .onClick(onBack)

      Text(title)
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_xmark_bold'))
          .width(CloudThemeToken.sheetActionIconSize)
          .height(CloudThemeToken.sheetActionIconSize)
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
    .borderRadius(CloudThemeToken.controlRadiusXl)
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
    AppLogger.info(TAG, `theme mode ${mode}`)
    this.themeMode = mode
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.APP_THEME_MODE, mode)
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      context.setColorMode(mode === Constant.APP_THEME_DARK
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
    } catch (err) {
      AppLogger.error(TAG, `set theme mode failed: ${(err as Error)?.message ?? err}`)
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
          this.userAvatarCacheUri = AvatarUtil.getDbUserAvatarCacheUri(dbUserInfo)
          this.saveMineCache()
          showToast('头像缓存已刷新')
        } else {
          showToast('头像刷新失败')
        }
      })
      .catch((err: Error) => {
        AppLogger.error(TAG, `refresh avatar cache failed: ${err.message}`)
        showToast('头像刷新失败')
      })
  }

  private getSystemAuthDescription(): string {
    if (this.systemAuthBusy) {
      return '正在等待系统认证'
    }
    return this.systemAuthEnabled ? '已开启，回到应用时需要人脸或指纹' : '未开启，可使用系统人脸或指纹保护应用'
  }

  private syncSystemAuthState(): void {
    this.systemAuthEnabled = AppLockUtil.isEnabled()
  }

  private toggleSystemAuth(): void {
    if (this.systemAuthBusy) {
      return
    }
    if (this.systemAuthEnabled) {
      AppLogger.info(TAG, 'system auth disabled')
      AppLockUtil.setEnabled(false)
      this.syncSystemAuthState()
      showToast('已关闭系统认证保护')
      return
    }
    AppLogger.info(TAG, 'system auth enable requested')

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
          AppLockUtil.setEnabled(true)
          this.syncSystemAuthState()
          showToast('已开启系统认证保护')
        } else {
          this.syncSystemAuthState()
          showToast(result.message.length > 0 ? result.message : '系统认证失败')
        }
      })
      .catch((err: Error) => {
        this.systemAuthBusy = false
        this.syncSystemAuthState()
        AppLogger.error(TAG, `enable system auth failed: ${err.message}`)
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
        AppLogger.error(TAG, `verify system auth failed: ${err.message}`)
        showToast('系统认证失败')
      })
  }

  private deleteCurrentCredential(): void {
    showCloudConfirmDialog(this.getUIContext(), {
      title: '删除当前登录凭证',
      message: `${this.currentUser}\n${this.currentUrl}`,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        AppLogger.info(TAG, 'delete current credential')
        UserDatabase.deleteUserInfo(this.currentUser, this.currentUrl)
        UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY)
        UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY)
        this.closeSettingsSheet()
        CloudRouter.resetToLogin()
      }
    })
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
      AppLogger.error(TAG, `open external url failed: ${err.code}, ${err.message}`)
      showToast('无法打开浏览器')
    })
  }

  private buildFeedbackDiagnostic(): string {
    return FeedbackUtil.buildDiagnosticMarkdown({
      appVersion: this.appVersion,
      serverUrl: this.currentUrl,
      account: this.currentUser,
      user: this.siteConfig?.user,
      recentLogs: AppLogger.getRecentText(60),
      logFilePath: AppLogger.getFilePath()
    })
  }

  private copyFeedbackDiagnostic(): void {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.buildFeedbackDiagnostic())
      pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
        showToast($r('app.string.copy_success'))
      }).catch((err: Error) => {
        AppLogger.error(TAG, 'copy feedback diagnostic failed: ' + err.message)
        showToast($r('app.string.copy_failed'))
      })
    } catch (err) {
      AppLogger.error(TAG, 'copy feedback diagnostic failed: ' + JSON.stringify(err))
      showToast($r('app.string.copy_failed'))
    }
  }

  private openFeedbackIssue(): void {
    this.copyFeedbackDiagnostic()
    this.openExternalUrl(FeedbackUtil.buildIssueUrl({
      appVersion: this.appVersion,
      serverUrl: this.currentUrl,
      account: this.currentUser,
      user: this.siteConfig?.user
    }))
    this.closeFeedbackSheet()
  }

  private openFeedbackMail(): void {
    this.copyFeedbackDiagnostic()
    this.openExternalUrl(FeedbackUtil.buildMailUrl({
      appVersion: this.appVersion,
      serverUrl: this.currentUrl,
      account: this.currentUser,
      user: this.siteConfig?.user
    }))
    this.closeFeedbackSheet()
  }

  private openLogViewer(): void {
    this.closeFeedbackSheet()
    this.showLogViewerSheet = true
  }

  @Builder aboutSheet() {
    AboutPage({ embedded: true })
  }

  @Builder logViewerSheet() {
    LogViewerSheet({
      onCopyDiagnostic: () => {
        this.copyFeedbackDiagnostic()
      },
      onClose: () => {
        this.showLogViewerSheet = false
      }
    })
  }

  @Builder rowWithJump(icon: ResourceStr, backgroundColor: ResourceColor, title: ResourceStr, url: string) {
    Row({ space: CloudThemeToken.spacingCard }) {
      Image(icon)
        .width(CloudThemeToken.icon4xl)
        .height(CloudThemeToken.icon4xl)
        .borderRadius(CloudThemeToken.controlRadiusXl)
        .padding(CloudThemeToken.spacingSm)
        .fillColor(CloudThemeToken.onPrimary)
        .backgroundColor(backgroundColor)
        .draggable(false)

      Text(title)
        .height(CloudThemeToken.iconXl)
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      Image($r('app.media.ic_web_jump'))
        .width(CloudThemeToken.iconMd)
        .height(CloudThemeToken.iconMd)
        .fillColor(CloudThemeToken.textSecondary)
        .draggable(false)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight3xl)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openExternalUrl(url)
    })
  }

  @Builder webButton() {
    Column({ space: CloudThemeToken.spacingCard }) {
      this.feedbackEntryRow()
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder feedbackEntryRow() {
    Row({ space: CloudThemeToken.spacingCard }) {
      Image($r('app.media.ic_feedback'))
        .width(CloudThemeToken.icon4xl)
        .height(CloudThemeToken.icon4xl)
        .borderRadius(CloudThemeToken.controlRadiusXl)
        .padding(CloudThemeToken.spacingSm)
        .fillColor(CloudThemeToken.onPrimary)
        .backgroundColor(CloudThemeToken.settingIconWebJumpBackground)
        .draggable(false)

      Text($r('app.string.feedback'))
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(CloudThemeToken.iconMd)
        .height(CloudThemeToken.iconMd)
        .fillColor(CloudThemeToken.textSecondary)
        .draggable(false)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight3xl)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.showFeedbackSheet = true
    })
  }

  @Builder feedbackSheet() {
    FeedbackSheet({
      onMail: () => {
        this.openFeedbackMail()
      },
      onIssue: () => {
        this.openFeedbackIssue()
      },
      onViewLogs: () => {
        this.openLogViewer()
      },
      onClose: () => {
        this.closeFeedbackSheet()
      }
    })
  }
}
