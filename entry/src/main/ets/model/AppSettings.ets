import { common, ConfigurationConstant } from '@kit.AbilityKit'
import Constant from './Constant'
import UserPreferences from './UserPreferences'
import { SettingsRules } from '../utils/SettingsRules'
import AppLogger from '../utils/AppLogger'

const TAG: string = 'AppSettings'
const KNOCK_EXPIRE_DEFAULT_DAYS: number = 1

/**
 * 本机偏好的统一读写入口。值只存在本机 UserPreferences，不同步服务端。
 * 读这些偏好的业务方（上传队列、图片预览、碰一碰）仍直接读同一个 key，互不影响。
 */
export class AppSettings {
  static getThemeMode(): string {
    return SettingsRules.normalizeThemeMode(
      UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.APP_THEME_MODE, Constant.APP_THEME_LIGHT) as string)
  }

  static setThemeMode(context: common.UIAbilityContext, mode: string): void {
    const normalized = SettingsRules.normalizeThemeMode(mode)
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.APP_THEME_MODE, normalized)
    AppSettings.applyTheme(context, normalized)
  }

  /** system 对应 COLOR_MODE_NOT_SET：交还给系统，系统切深浅色时会回调 onConfigurationUpdate */
  static applyTheme(context: common.UIAbilityContext, mode: string): void {
    try {
      context.setColorMode(AppSettings.toColorMode(mode))
    } catch (err) {
      AppLogger.error(TAG, `set color mode failed: ${(err as Error)?.message ?? err}`)
    }
  }

  static toColorMode(mode: string): ConfigurationConstant.ColorMode {
    if (mode === Constant.APP_THEME_DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    }
    if (mode === Constant.APP_THEME_SYSTEM) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  }

  /** 实际生效的是不是深色：跟随系统时读当前 Configuration */
  static isDarkEffective(context: common.UIAbilityContext): boolean {
    return AppSettings.isDarkFor(context.config.colorMode)
  }

  /**
   * 已知系统 colorMode 时实际生效的是不是深色：保存的模式是深/浅色直接定，跟随系统才看 colorMode。
   * onConfigurationUpdate 里要用回调带来的 newConfig.colorMode，context.config 那时可能还没更新。
   */
  static isDarkFor(colorMode: ConfigurationConstant.ColorMode | undefined): boolean {
    const mode = AppSettings.getThemeMode()
    if (mode === Constant.APP_THEME_DARK) {
      return true
    }
    if (mode === Constant.APP_THEME_LIGHT) {
      return false
    }
    return colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  }

  static getUploadConcurrent(): number {
    return SettingsRules.clampUploadConcurrent(UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.UPLOAD_MAX_CONCURRENT, Constant.UPLOAD_CONCURRENT_DEFAULT) as number)
  }

  static setUploadConcurrent(value: number): number {
    const clamped = SettingsRules.clampUploadConcurrent(value)
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.UPLOAD_MAX_CONCURRENT, clamped)
    return clamped
  }

  static getBool(key: string, defValue: boolean): boolean {
    return UserPreferences.getSync(Constant.USER_PREFERENCES, key, defValue) as boolean
  }

  static setBool(key: string, value: boolean): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, key, value)
  }

  static getKnockExpireDays(): number {
    return UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.KNOCK_SHARE_EXPIRE_DAYS, KNOCK_EXPIRE_DEFAULT_DAYS) as number
  }

  static setKnockExpireDays(days: number): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.KNOCK_SHARE_EXPIRE_DAYS, days)
  }
}
