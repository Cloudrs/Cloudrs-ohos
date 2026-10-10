import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { CloudMaterial } from '../model/CloudMaterial'
import { CloudApi } from '../model/net/CloudApi'
import { AccountLoginActivity, AccountStoragePack } from '../model/net/ApiTypes'
import UserDatabase from '../model/UserDatabase'
import UserPreferences from '../model/UserPreferences'
import { ACCOUNT_PROFILE_STORE_KEY, AccountProfileStore } from '../model/AccountProfileStore'
import { SubPageScaffold } from '../components/SubPageScaffold'
import {
  ChipTone, SettingGroup, SettingRow, SettingSectionTitle, SettingSwitchRow
} from '../components/settings/SettingRows'
import { NicknameSheet } from '../components/account/NicknameSheet'
import { ChangePasswordSheet } from '../components/account/ChangePasswordSheet'
import { TwoFactorSheet } from '../components/account/TwoFactorSheet'
import { PasskeySheet } from '../components/account/PasskeySheet'
import { SheetPhaseController } from '../utils/SheetPhaseController'
import { SettingsRules } from '../utils/SettingsRules'
import { AvatarPicker } from '../utils/AvatarPicker'
import { AppLockUtil } from '../utils/AppLockUtil'
import { SystemAuthResult } from '../utils/SystemAuthUtil'
import { ActiveAccount } from '../utils/ActiveAccount'
import { CloudRouter } from '../utils/CloudRouter'
import { showCloudConfirmDialog } from '../utils/CloudDialogUtil'
import { showToast } from '../utils/ToastUtil'
import { CommonUtil } from '../utils/CommonUtil'
import AppLogger from '../utils/AppLogger'

const TAG: string = 'AccountSecurityPage'
const FOCUS_DELAY_MS: number = 50
const NICKNAME_INPUT_ID: string = 'accountNicknameInput'
const PASSWORD_INPUT_ID: string = 'accountPasswordInput'
const OTP_INPUT_ID: string = 'accountOtpInput'
const MAX_ACTIVITY: number = 10

@Component
export struct AccountSecurityPage {
  // 宽屏在「我的」内容区内打开时由 TabMine 传入：标题栏左内边距（让出悬浮折叠键）与返回回调；
  // 未传时 -1 / undefined，走默认 pagePadding 与 CloudRouter.pop()
  @Prop titleStartPadding: number = -1
  onBack?: () => void
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  private scroller: Scroller = new Scroller()
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0
  @State showNickname: boolean = false
  @State showPassword: boolean = false
  @State showTwoFactor: boolean = false
  @State showPasskeys: boolean = false
  @State twoFactorEnabling: boolean = true
  @State appLockEnabled: boolean = false
  @State appLockBusy: boolean = false
  @State avatarBusy: boolean = false
  @StorageLink(ACCOUNT_PROFILE_STORE_KEY) store: AccountProfileStore = AccountProfileStore.instance
  private nicknameCtrl: SheetPhaseController = new SheetPhaseController()
  private passwordCtrl: SheetPhaseController = new SheetPhaseController()
  private twoFactorCtrl: SheetPhaseController = new SheetPhaseController()
  private passkeyCtrl: SheetPhaseController = new SheetPhaseController()
  private activeUser: string = ''
  private activeUrl: string = ''

  aboutToAppear(): void {
    this.appLockEnabled = AppLockUtil.isEnabled()
    // 不信任 store 上一次被激活的账号（只有 TabMine 会 activate）：以持久化的活动账号为准
    this.activeUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string
    this.activeUrl = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string
    this.store.activate(this.activeUser, this.activeUrl)
    if (!this.store.isV3()) {
      this.store.loadAccountSettings()
    }
  }

  build() {
    Stack() {
      SubPageScaffold({
        title: '账号与安全', startPadding: this.titleStartPadding, scroller: this.scroller, onBackClick: this.onBack
      }) {
        // 内容铺满全页、从标题栏底下滚过（顶部留出标题栏高度），上滑时标题栏出模糊材质
        Scroll(this.scroller) {
          Column({ space: CloudThemeToken.sectionGap }) {
            if (this.store.isV3()) {
              this.v3Banner()
            }
            this.profileSection()
            if (!this.store.isV3()) {
              this.securitySection()
            }
            this.deviceSection()
            if (!this.store.isV3() && (this.store.account?.storage_packs ?? []).length > 0) {
              this.storagePackSection()
            }
            if (!this.store.isV3() && (this.store.account?.login_activity ?? []).length > 0) {
              this.activitySection()
            }
          }
          .width('100%')
          .padding({
            left: CloudThemeToken.pagePadding,
            right: CloudThemeToken.pagePadding,
            top: CloudThemeToken.hdsTitleBarHeight(this.topRectHeight) + CloudThemeToken.spacingXs,
            bottom: this.bottomRectHeight + CloudThemeToken.pageBottomPadding
          })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }

      this.sheetHosts()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder v3Banner() {
    Column({ space: CloudThemeToken.spacingXs }) {
      Text('Cloudreve v3 请在网页端修改资料与安全设置')
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontColor(CloudThemeToken.primary)
      Text('在浏览器中打开')
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.primary)
        .decoration({ type: TextDecorationType.Underline })
        .onClick(() => this.openInBrowser())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(CloudThemeToken.spacingPanel)
    .borderRadius(CloudThemeToken.settingGroupRadius)
    .backgroundColor(CloudThemeToken.primarySoft)
  }

  @Builder profileSection() {
    Column({ space: CloudThemeToken.spacingXl }) {
      SettingSectionTitle({ title: '个人资料' })
      SettingGroup() {
        Row({ space: CloudThemeToken.spacingSection }) {
          Text('头像')
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontColor(CloudThemeToken.textPrimary)
            .layoutWeight(1)
          if (this.avatarBusy) {
            LoadingProgress().width(CloudThemeToken.iconXl).height(CloudThemeToken.iconXl)
          }
          this.smallAvatar()
          Image($r('app.media.ic_chevron_right'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
        .width('100%')
        .constraintSize({ minHeight: CloudThemeToken.rowHeight4xl })
        .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel,
          top: CloudThemeToken.spacingXl, bottom: CloudThemeToken.spacingXl })
        .opacity(this.store.isV3() ? CloudThemeToken.disabledOpacity : CloudThemeToken.fullOpacity)
        .enabled(!this.store.isV3() && !this.avatarBusy)
        // 菜单绑在整行上，默认会贴左下弹出；靠右弹出才落在右侧头像附近
        .bindMenu([
          { value: '从图库选择', action: () => this.pickAvatar() },
          { value: '恢复默认头像', action: () => this.resetAvatar() }
        ], { placement: Placement.BottomRight })

        SettingRow({
          title: '昵称',
          value: this.store.displayName(),
          divider: true,
          rowEnabled: !this.store.isV3(),
          onTap: () => {
            this.nicknameCtrl.requestOpen(() => this.showNickname, (v: boolean) => { this.showNickname = v })
          }
        })
        SettingRow({
          title: '邮箱',
          value: this.store.accountName(),
          divider: true,
          tappable: false
        })
        SettingRow({
          title: '用户组',
          desc: this.groupExpiresText(),
          chipText: this.store.user?.group?.name ?? '',
          chipTone: ChipTone.PRIMARY,
          divider: true,
          tappable: false
        })
      }
    }
    .width('100%')
  }

  @Builder smallAvatar() {
    Stack() {
      Text(this.store.displayName().substring(0, 1).toUpperCase())
        .fontSize(CloudThemeToken.textSizeBodyPlus)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.primary)
      if (this.store.avatarCacheUri.length > 0) {
        Image(this.store.avatarCacheUri).width('100%').height('100%').objectFit(ImageFit.Cover).draggable(false)
      }
      if (this.store.avatar) {
        Image(this.store.avatar).width('100%').height('100%').objectFit(ImageFit.Cover).draggable(false)
      }
    }
    .width(CloudThemeToken.iconBoxLg)
    .height(CloudThemeToken.iconBoxLg)
    .borderRadius(CloudThemeToken.iconBoxLg / CloudThemeToken.halfDivisor)
    .backgroundColor(CloudThemeToken.primarySoft)
    .clip(true)
  }

  @Builder securitySection() {
    Column({ space: CloudThemeToken.spacingXl }) {
      SettingSectionTitle({ title: '登录安全' })
      SettingGroup() {
        if (this.store.accountLoadFailed) {
          SettingRow({
            title: '加载失败，点击重试',
            showChevron: false,
            onTap: () => this.store.loadAccountSettings()
          })
        } else {
          if (this.store.account?.passwordless === true) {
            SettingRow({ title: '修改密码', desc: '未设置密码', tappable: false })
          } else {
            SettingRow({
              title: '修改密码',
              rowEnabled: this.store.account !== undefined,
              onTap: () => {
                this.passwordCtrl.requestOpen(() => this.showPassword, (v: boolean) => { this.showPassword = v })
              }
            })
          }
          SettingRow({
            title: '两步验证',
            desc: '登录时需输入动态码',
            chipText: this.store.account ? (this.store.account.two_fa_enabled ? '已开启' : '未开启') : '',
            chipTone: this.store.account?.two_fa_enabled === true ? ChipTone.SUCCESS : ChipTone.NEUTRAL,
            divider: true,
            rowEnabled: this.store.account !== undefined,
            onTap: () => this.openTwoFactor()
          })
          SettingRow({
            title: '通行密钥',
            desc: '需在网页端添加',
            value: this.passkeyCountText(),
            divider: true,
            rowEnabled: this.store.account !== undefined,
            onTap: () => {
              this.passkeyCtrl.requestOpen(() => this.showPasskeys, (v: boolean) => { this.showPasskeys = v })
            }
          })
        }
      }
    }
    .width('100%')
  }

  @Builder deviceSection() {
    Column({ space: CloudThemeToken.spacingXl }) {
      SettingSectionTitle({ title: '本机' })
      SettingGroup() {
        SettingSwitchRow({
          title: '应用锁',
          desc: this.appLockBusy ? '正在验证' : '进入应用时验证身份',
          isOn: this.appLockEnabled,
          busy: this.appLockBusy,
          onChange: (isOn: boolean) => this.toggleAppLock(isOn)
        })
        SettingRow({
          title: '登录凭证',
          desc: this.serverUrl(),
          value: this.credentialText(),
          divider: true,
          tappable: false
        })
        SettingRow({
          title: '删除本机凭证',
          desc: '移除后需重新登录',
          danger: true,
          showChevron: false,
          divider: true,
          onTap: () => this.confirmDeleteCredential()
        })
      }
    }
    .width('100%')
  }

  @Builder storagePackSection() {
    Column({ space: CloudThemeToken.spacingXl }) {
      SettingSectionTitle({ title: '存储包' })
      SettingGroup() {
        ForEach(this.store.account?.storage_packs ?? [], (pack: AccountStoragePack, index: number) => {
          SettingRow({
            title: `${pack.name} ${CommonUtil.formatBytes(pack.size)}`,
            desc: SettingsRules.formatDate(pack.active_since).length > 0
              ? `${SettingsRules.formatDate(pack.active_since)} 生效` : '',
            chipText: SettingsRules.formatDate(pack.expire_at).length > 0
              ? `${SettingsRules.formatDate(pack.expire_at)} 到期` : '',
            chipTone: ChipTone.WARNING,
            divider: index > 0,
            tappable: false
          })
        }, (pack: AccountStoragePack, index: number) => `${pack.name}_${index}`)
      }
    }
    .width('100%')
  }

  @Builder activitySection() {
    Column({ space: CloudThemeToken.spacingXl }) {
      SettingSectionTitle({ title: '最近登录' })
      SettingGroup() {
        ForEach((this.store.account?.login_activity ?? []).slice(0, MAX_ACTIVITY),
          (activity: AccountLoginActivity, index: number) => {
            SettingRow({
              title: this.activityTitle(activity),
              desc: SettingsRules.joinNonEmpty([
                activity.ip,
                SettingsRules.formatShortDateTime(activity.created_at),
                activity.login_with
              ], ' · '),
              chipText: activity.success ? '成功' : '失败',
              chipTone: activity.success ? ChipTone.SUCCESS : ChipTone.DANGER,
              divider: index > 0,
              tappable: false
            })
          }, (activity: AccountLoginActivity, index: number) => `${activity.created_at}_${index}`)
      }
      Text(`只显示最近 ${MAX_ACTIVITY} 条`)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  @Builder sheetHosts() {
    Column().width(0).height(0)
      .bindSheet($$this.showNickname, this.nicknameSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        // 宽屏走居中弹窗时 detents 不生效，高度要单独给，否则固定半屏高、内容下方大片留白
        height: SheetSize.FIT_CONTENT,
        title: { title: '修改昵称' },
        showClose: true,
        keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onWillAppear: () => this.nicknameCtrl.onWillAppear(),
        onAppear: () => {
          this.nicknameCtrl.onAppear()
          this.focusLater(NICKNAME_INPUT_ID)
        },
        onWillDisappear: () => this.nicknameCtrl.onWillDisappear(),
        onDisappear: () => this.nicknameCtrl.onDisappear((v: boolean) => { this.showNickname = v }, () => {})
      })

    Column().width(0).height(0)
      .bindSheet($$this.showPassword, this.passwordSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        // 宽屏走居中弹窗时 detents 不生效，高度要单独给，否则固定半屏高、内容下方大片留白
        height: SheetSize.FIT_CONTENT,
        title: { title: '修改密码' },
        showClose: true,
        keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onWillAppear: () => this.passwordCtrl.onWillAppear(),
        // 不自动聚焦：密码框一获焦系统密码保险箱就会弹出建议框，盖住下面的表单
        onAppear: () => this.passwordCtrl.onAppear(),
        onWillDisappear: () => this.passwordCtrl.onWillDisappear(),
        onDisappear: () => this.passwordCtrl.onDisappear((v: boolean) => { this.showPassword = v }, () => {})
      })

    Column().width(0).height(0)
      .bindSheet($$this.showTwoFactor, this.twoFactorSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        // 宽屏走居中弹窗时 detents 不生效，高度要单独给，否则固定半屏高、内容下方大片留白
        height: SheetSize.FIT_CONTENT,
        title: { title: this.twoFactorEnabling ? '开启两步验证' : '关闭两步验证' },
        showClose: true,
        keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onWillAppear: () => this.twoFactorCtrl.onWillAppear(),
        onAppear: () => {
          this.twoFactorCtrl.onAppear()
          if (!this.twoFactorEnabling) {
            this.focusLater(OTP_INPUT_ID)
          }
        },
        onWillDisappear: () => this.twoFactorCtrl.onWillDisappear(),
        onDisappear: () => this.twoFactorCtrl.onDisappear((v: boolean) => { this.showTwoFactor = v }, () => {})
      })

    Column().width(0).height(0)
      .bindSheet($$this.showPasskeys, this.passkeySheet(), {
        detents: [SheetSize.FIT_CONTENT],
        // 宽屏走居中弹窗时 detents 不生效，高度要单独给，否则固定半屏高、内容下方大片留白
        height: SheetSize.FIT_CONTENT,
        title: { title: '通行密钥' },
        showClose: true,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onWillAppear: () => this.passkeyCtrl.onWillAppear(),
        onAppear: () => this.passkeyCtrl.onAppear(),
        onWillDisappear: () => this.passkeyCtrl.onWillDisappear(),
        onDisappear: () => this.passkeyCtrl.onDisappear((v: boolean) => { this.showPasskeys = v }, () => {})
      })
  }

  @Builder nicknameSheet() {
    NicknameSheet({
      initial: this.store.user?.nickname ?? '',
      inputId: NICKNAME_INPUT_ID,
      onDone: (nick: string) => {
        this.store.applyNickname(nick)
        this.nicknameCtrl.requestClose((v: boolean) => { this.showNickname = v })
        showToast('昵称已更新')
      }
    })
  }

  @Builder passwordSheet() {
    ChangePasswordSheet({
      inputId: PASSWORD_INPUT_ID,
      onDone: () => {
        this.passwordCtrl.requestClose((v: boolean) => { this.showPassword = v })
        showToast('密码已修改')
      }
    })
  }

  @Builder twoFactorSheet() {
    TwoFactorSheet({
      enabling: this.twoFactorEnabling,
      issuer: this.siteTitle(),
      account: this.store.accountName(),
      inputId: OTP_INPUT_ID,
      onCodeStep: () => this.focusLater(OTP_INPUT_ID),
      onDone: (enabled: boolean) => {
        this.store.setTwoFactorEnabled(enabled)
        this.twoFactorCtrl.requestClose((v: boolean) => { this.showTwoFactor = v })
        showToast(enabled ? '两步验证已开启' : '两步验证已关闭')
      }
    })
  }

  @Builder passkeySheet() {
    PasskeySheet()
  }

  private openTwoFactor(): void {
    if (!this.store.account) {
      return
    }
    this.twoFactorEnabling = !this.store.account.two_fa_enabled
    this.twoFactorCtrl.requestOpen(() => this.showTwoFactor, (v: boolean) => { this.showTwoFactor = v })
  }

  private focusLater(id: string): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(id)
      } catch (err) {
        AppLogger.warn(TAG, `focus ${id} failed: ${(err as Error)?.message ?? err}`)
      }
    }, FOCUS_DELAY_MS)
  }

  private pickAvatar(): void {
    AvatarPicker.pickSquareJpeg()
      .then((bytes?: Uint8Array) => {
        if (!bytes) {
          return
        }
        this.avatarBusy = true
        CloudApi.uploadAvatar(bytes, 'image/jpeg', {
          onSuccess: () => {
            this.avatarBusy = false
            this.store.reloadAvatar()
            showToast('头像已更新')
          },
          onFailure: (msg: string) => {
            this.avatarBusy = false
            showToast(SettingsRules.apiMessage(msg))
          }
        })
      })
      .catch((err: BusinessError | string) => {
        // Image Kit 解码失败 reject 的是纯字符串而不是 BusinessError，按类型分别记，否则只剩 undefined
        const detail = typeof err === 'string' ? err : `code=${err?.code}, msg=${err?.message}`
        AppLogger.error(TAG, `pick avatar failed: ${detail}`)
        showToast('无法读取图片')
      })
  }

  private resetAvatar(): void {
    this.avatarBusy = true
    CloudApi.resetAvatar({
      onSuccess: () => {
        this.avatarBusy = false
        this.store.reloadAvatar()
        showToast('已恢复默认头像')
      },
      onFailure: (msg: string) => {
        this.avatarBusy = false
        showToast(SettingsRules.apiMessage(msg))
      }
    })
  }

  /**
   * SettingSwitchRow 把 isOn 以 @Prop 喂给 Toggle：页面若拒绝本次切换却不改自己的状态，
   * Toggle 会停在翻转后的外观。所以先乐观地把 appLockEnabled 设成目标值，认证失败/取消再回写真实值。
   */
  private toggleAppLock(isOn: boolean): void {
    if (this.appLockBusy) {
      return
    }
    // 认证取消/失败后把开关回写为关时，Toggle 会再回调一次 onChange(false)；
    // 此时应用锁本就没开，只同步状态，不弹「已关闭应用锁」盖掉真正的失败提示
    if (isOn === AppLockUtil.isEnabled()) {
      this.appLockEnabled = isOn
      return
    }
    this.appLockEnabled = isOn
    if (!isOn) {
      AppLockUtil.setEnabled(false)
      showToast('已关闭应用锁')
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (!context) {
      showToast('无法唤起系统认证')
      this.appLockEnabled = AppLockUtil.isEnabled()
      return
    }
    this.appLockBusy = true
    AppLockUtil.authenticateForSettings(context, '开启应用锁')
      .then((result: SystemAuthResult) => {
        this.appLockBusy = false
        if (result.success) {
          AppLockUtil.setEnabled(true)
        } else {
          showToast(result.message.length > 0 ? result.message : '系统认证失败')
        }
        this.appLockEnabled = AppLockUtil.isEnabled()
      })
      .catch((err: Error) => {
        this.appLockBusy = false
        this.appLockEnabled = AppLockUtil.isEnabled()
        AppLogger.error(TAG, `enable app lock failed: ${err.message}`)
        showToast('系统认证失败')
      })
  }

  private confirmDeleteCredential(): void {
    const user = this.activeUser
    const url = this.activeUrl
    if (url.length === 0) {
      showToast('无法确定服务器地址，请重新登录后再试')
      return
    }
    showCloudConfirmDialog(this.getUIContext(), {
      title: '删除本机凭证？',
      message: `${user}\n${url}\n会从账号列表中移除，需要重新登录。`,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        AppLogger.info(TAG, 'delete current credential')
        UserDatabase.deleteUserInfo(user, url)
        CloudApi.clearSession()
        ActiveAccount.clear()
        CloudRouter.resetToLogin()
      }
    })
  }

  private openInBrowser(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    context.startAbility({
      action: 'ohos.want.action.viewData',
      uri: this.serverUrl(),
      entities: ['entity.system.browsable']
    }).catch((err: Error) => {
      AppLogger.error(TAG, `open browser failed: ${err.message}`)
      showToast('无法打开浏览器')
    })
  }

  private credentialText(): string {
    const db = UserDatabase.getUserInfo(this.store.username, this.store.url)
    if (!db) {
      return '未找到'
    }
    const expires = new Date(db.expires)
    if (Number.isNaN(expires.getTime()) || expires.getTime() <= Date.now()) {
      return '已过期'
    }
    return `有效至 ${SettingsRules.formatDate(expires.toISOString())}`
  }

  private groupExpiresText(): string {
    const date = SettingsRules.formatDate(this.store.account?.group_expires ?? '')
    return date.length > 0 ? `${date} 到期` : ''
  }

  private passkeyCountText(): string {
    const count = (this.store.account?.passkeys ?? []).length
    return count > 0 ? `${count} 个` : '无'
  }

  private activityTitle(activity: AccountLoginActivity): string {
    const title = SettingsRules.joinNonEmpty([activity.os, activity.browser], ' · ')
    const base = title.length > 0 ? title : (activity.device.length > 0 ? activity.device : '未知设备')
    return activity.webdav ? `${base} · WebDAV` : base
  }

  /** store.url 为空时退回当前会话的服务器地址 */
  private serverUrl(): string {
    return this.store.url.length > 0 ? this.store.url : CloudApi.getBaseURL()
  }

  /** TOTP 发行方：只取主机名（去掉协议、路径、端口，冒号会破坏验证器的标签解析） */
  private siteTitle(): string {
    const raw = CloudApi.getBaseURL().length > 0 ? CloudApi.getBaseURL() : this.serverUrl()
    const host = raw.replace(new RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://'), '')
      .split('/')[0]
      .split('?')[0]
      .replace(new RegExp(':[0-9]*$'), '')
    return host.length > 0 ? host : 'Cloudreve'
  }
}
