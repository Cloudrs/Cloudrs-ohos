import { AccountPasskey, AccountSettings, DbUserInfo, SiteConfig, UserInfo, UserStorage } from './net/ApiTypes'
import { CloudApi } from './net/CloudApi'
import UserDatabase from './UserDatabase'
import { AvatarUtil } from '../utils/AvatarUtil'
import { CommonUtil } from '../utils/CommonUtil'
import { SettingsRules } from '../utils/SettingsRules'
import AppLogger from '../utils/AppLogger'

const TAG: string = 'AccountProfileStore'
const REFRESH_INTERVAL_MS: number = 30000

/** AppStorage 中共享单例的键；V1 组件用 @StorageLink 订阅，字段重新赋值即触发刷新 */
export const ACCOUNT_PROFILE_STORE_KEY: string = 'accountProfileStore'

/**
 * 「我的」与「账号与安全」共享的账号状态。两页都只读这里；写操作成功后整体替换一级字段（勿就地改嵌套对象，V1 观察不到），
 * 另一页不必重新拉取就能同步。以 url|username 区分账号，切换账号即重置。
 * 会话续期由 native 负责（site config 匿名时自动续期 + SessionSync 落库），这里不再处理。
 */
@Observed
export class AccountProfileStore {
  /**
   * 必须在类装饰完成后再 new：@Observed 返回包装子类，类体内的静态初始化器早于装饰执行，
   * 那里 new 出的是未代理的原始对象，经它的写入不会通知 V1 组件。
   */
  static get instance(): AccountProfileStore {
    return accountProfileStore
  }

  username: string = ''
  url: string = ''
  user?: UserInfo = undefined
  storage?: UserStorage = undefined
  storageUpdatedAt: number = 0
  avatar?: PixelMap = undefined
  avatarCacheUri: string = ''
  account?: AccountSettings = undefined
  accountLoading: boolean = false
  accountLoadFailed: boolean = false
  private lastRefreshAt: number = 0

  private keyOf(): string {
    return `${this.url}|${this.username}`
  }

  private dbUser(): DbUserInfo | null {
    return UserDatabase.getUserInfo(this.username, this.url)
  }

  activate(username: string, url: string): void {
    if (this.username === username && this.url === url) {
      return
    }
    this.username = username
    this.url = url
    this.user = undefined
    this.storage = undefined
    this.storageUpdatedAt = 0
    this.avatar = undefined
    this.avatarCacheUri = ''
    this.account = undefined
    this.accountLoading = false
    this.accountLoadFailed = false
    this.lastRefreshAt = 0
    const db = this.dbUser()
    if (!db || !db.userinfo) {
      return
    }
    this.user = db.userinfo
    this.avatarCacheUri = AvatarUtil.getDbUserAvatarCacheUri(db)
    this.avatar = AvatarUtil.getMemoryCachedDbUserAvatar(db)
    if (!this.avatar && this.avatarCacheUri.length === 0) {
      this.loadAvatar(db, false)
    }
  }

  refreshIfStale(): void {
    if (Date.now() - this.lastRefreshAt < REFRESH_INTERVAL_MS) {
      return
    }
    this.refresh()
  }

  /**
   * site config 先行：access token 过期时它会在 native 里续期一次（refresh token 每次续期都轮换），
   * 存储与账号设置等它回来再发，避免并发续期互相用掉对方的 refresh token。
   */
  refresh(): void {
    this.lastRefreshAt = Date.now()
    const key = this.keyOf()
    CloudApi.getSiteConfig({
      onSuccess: (data: SiteConfig) => {
        if (key !== this.keyOf()) {
          return
        }
        if (data.user && data.user.anonymous !== true) {
          this.applyUser(data.user)
        }
        this.refreshDetails(key)
      },
      onFailure: (msg: string) => {
        AppLogger.error(TAG, `site config failed: ${msg}`)
        if (key !== this.keyOf()) {
          return
        }
        this.refreshDetails(key)
      }
    })
  }

  private refreshDetails(key: string): void {
    CloudApi.userStorage({
      onSuccess: (data: UserStorage) => {
        if (key !== this.keyOf()) {
          return
        }
        this.storage = data
        this.storageUpdatedAt = Date.now()
      },
      onFailure: (msg: string) => {
        AppLogger.error(TAG, `storage failed: ${msg}`)
      }
    })
    this.loadAccountSettings()
  }

  loadAccountSettings(): void {
    if (this.isV3()) {
      this.accountLoading = false
      return
    }
    const key = this.keyOf()
    this.accountLoading = true
    this.accountLoadFailed = false
    CloudApi.getAccountSettings({
      onSuccess: (data: AccountSettings) => {
        if (key !== this.keyOf()) {
          return
        }
        this.account = data
        this.accountLoading = false
      },
      onFailure: (msg: string) => {
        if (key !== this.keyOf()) {
          return
        }
        AppLogger.error(TAG, `account settings failed: ${msg}`)
        this.accountLoading = false
        this.accountLoadFailed = true
      }
    })
  }

  isV3(): boolean {
    return !CloudApi.isV4()
  }

  createdDays(): number {
    const created = this.user?.created_at ?? ''
    if (SettingsRules.formatDate(created).length === 0) {
      return 0
    }
    return CommonUtil.getDaysDifference(new Date(created), new Date())
  }

  displayName(): string {
    const nick = this.user?.nickname ?? ''
    return nick.length > 0 ? nick : this.username
  }

  /** 登录名：v3 是 user_name，v4 没有该字段时回落到登录账号（邮箱） */
  accountName(): string {
    const name = this.user?.user_name ?? ''
    return name.length > 0 ? name : this.username
  }

  applyNickname(nick: string): void {
    const current = this.user
    if (!current) {
      return
    }
    const next: UserInfo = {
      id: current.id,
      user_name: current.user_name,
      nickname: nick,
      status: current.status,
      avatar: current.avatar,
      created_at: current.created_at,
      preferred_theme: current.preferred_theme,
      anonymous: current.anonymous,
      group: current.group
    }
    this.user = next
    const db = this.dbUser()
    if (db) {
      db.userinfo = next
      UserDatabase.insertUserInfo(db)
    }
  }

  reloadAvatar(): void {
    const db = this.dbUser()
    if (!db || !db.userinfo) {
      return
    }
    AvatarUtil.clearDbUserAvatar(db)
    this.avatar = undefined
    this.avatarCacheUri = ''
    this.loadAvatar(db, true)
  }

  removePasskey(id: string): void {
    const current = this.account
    if (!current) {
      return
    }
    this.account = AccountProfileStore.copyAccount(current, current.two_fa_enabled,
      current.passkeys.filter(passkey => passkey.id !== id))
  }

  setTwoFactorEnabled(enabled: boolean): void {
    const current = this.account
    if (!current) {
      return
    }
    this.account = AccountProfileStore.copyAccount(current, enabled, current.passkeys)
  }

  private static copyAccount(src: AccountSettings, twoFa: boolean, passkeys: AccountPasskey[]): AccountSettings {
    const next: AccountSettings = {
      supported: src.supported,
      passwordless: src.passwordless,
      two_fa_enabled: twoFa,
      passkeys: passkeys,
      login_activity: src.login_activity,
      storage_packs: src.storage_packs,
      group_expires: src.group_expires
    }
    return next
  }

  private applyUser(user: UserInfo): void {
    const db = this.dbUser()
    const previousId = this.user?.id ?? ''
    const previousAvatar = this.user?.avatar ?? ''
    this.user = user
    if (!db) {
      return
    }
    db.userinfo = user
    UserDatabase.insertUserInfo(db)
    this.avatarCacheUri = AvatarUtil.getDbUserAvatarCacheUri(db)
    const changed = previousId !== (user.id ?? '') || previousAvatar !== (user.avatar ?? '')
    // 与旧版一致：已有头像或缓存时也强制刷新，网页端/其他设备改了头像才能同步过来
    const hasCached = !!this.avatar || this.avatarCacheUri.length > 0
    this.loadAvatar(db, changed || hasCached)
  }

  private loadAvatar(db: DbUserInfo, forceRefresh: boolean): void {
    const key = this.keyOf()
    AvatarUtil.loadDbUserAvatar(db, forceRefresh)
      .then((pixelMap?: PixelMap) => {
        if (key !== this.keyOf() || !pixelMap) {
          return
        }
        this.avatar = pixelMap
        this.avatarCacheUri = AvatarUtil.getDbUserAvatarCacheUri(db)
      })
      .catch((err: Error) => {
        AppLogger.error(TAG, `avatar load failed: ${err.message}`)
      })
  }
}

const accountProfileStore: AccountProfileStore = new AccountProfileStore()
AppStorage.setOrCreate<AccountProfileStore>(ACCOUNT_PROFILE_STORE_KEY, accountProfileStore)
