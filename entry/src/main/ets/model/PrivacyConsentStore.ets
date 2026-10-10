import { privacyManager } from '@kit.StoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Constant from './Constant';
import UserPreferences from './UserPreferences';
import { SettingsRules } from '../utils/SettingsRules';
import AppLogger from '../utils/AppLogger';

const TAG: string = 'PrivacyConsent';

/**
 * 登录页「我已阅读并同意隐私政策」的同意记录。
 *
 * 官方 FAQ（应用每次登录都需要确认隐私协议）建议持久化这份选择：首次登录勾选一次，之后退出登录、凭据过期重登、
 * 在登录页切换账号都不必再勾。记录的是同意时的隐私政策版本，政策在 AGC 托管侧升了版本就作废、重新要求勾选。
 * 规范要求提供撤回途径，见 revoke（设置页「撤回隐私政策同意」）。
 *
 * 隐私政策走 AGC 隐私托管：版本与链接优先取托管服务；本地 hdc 安装的包未接入托管（接口抛 1006700003），
 * 回落到内置版本号与 Constant 里的链接。
 */
export class PrivacyConsentStore {
  private static hostedLink: privacyManager.AppPrivacyLink | null | undefined = undefined

  static hasConsented(): boolean {
    const agreed = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.PRIVACY_CONSENT_KEY, 0) as number
    return SettingsRules.isPrivacyConsentValid(agreed, PrivacyConsentStore.policyVersion())
  }

  /** 用户勾选或在确认框里点了同意 */
  static recordConsent(): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PRIVACY_CONSENT_KEY,
      PrivacyConsentStore.policyVersion())
  }

  /** 登录前又取消了勾选：只清本机记录 */
  static clearConsent(): void {
    UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.PRIVACY_CONSENT_KEY)
  }

  /**
   * 撤回同意：清本机记录，并撤销托管服务里的签署记录，下次打开应用会重新弹出标准隐私弹窗。
   * 未接入托管（本地安装）时撤销接口会抛错，记一笔即可，本机记录照样清掉。
   */
  static revoke(): void {
    PrivacyConsentStore.clearConsent()
    try {
      privacyManager.disableService()
      AppLogger.info(TAG, 'hosted privacy consent revoked')
    } catch (err) {
      const error = err as BusinessError
      AppLogger.warn(TAG, `revoke hosted privacy consent failed: ${error.code}, ${error.message}`)
    }
  }

  static policyUrl(): string {
    const link = PrivacyConsentStore.hostedPolicyLink()
    return link && link.url.length > 0 ? link.url : Constant.PRIVACY_POLICY_URL
  }

  private static policyVersion(): number {
    const link = PrivacyConsentStore.hostedPolicyLink()
    return link && link.versionCode > 0 ? link.versionCode : Constant.PRIVACY_POLICY_FALLBACK_VERSION
  }

  /** 托管的隐私声明链接；进程内只查一次，查不到记 null 不再重试 */
  private static hostedPolicyLink(): privacyManager.AppPrivacyLink | null {
    if (PrivacyConsentStore.hostedLink !== undefined) {
      return PrivacyConsentStore.hostedLink
    }
    try {
      const info = privacyManager.getAppPrivacyMgmtInfo()
      PrivacyConsentStore.hostedLink = info.privacyInfo.find((link: privacyManager.AppPrivacyLink) =>
        link.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK) ?? null
    } catch (err) {
      const error = err as BusinessError
      AppLogger.info(TAG, `hosted privacy info unavailable, use built-in: ${error.code}, ${error.message}`)
      PrivacyConsentStore.hostedLink = null
    }
    return PrivacyConsentStore.hostedLink
  }
}
