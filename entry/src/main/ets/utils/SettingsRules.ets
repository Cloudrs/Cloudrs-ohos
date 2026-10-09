import Constant from '../model/Constant'

const SECRET_GROUP_SIZE: number = 4
const MIN_VALID_YEAR: number = 1971
const API_ERROR_PATTERN: RegExp = new RegExp('^API error: (.*) \\(code: -?\\d+\\)$')

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`
}

function parseDate(iso: string): Date | undefined {
  if (iso.length === 0) {
    return undefined
  }
  const date = new Date(iso)
  if (Number.isNaN(date.getTime()) || date.getFullYear() <= MIN_VALID_YEAR) {
    return undefined
  }
  return date
}

/**
 * 设置与账号页用到的纯规则：不碰 UI、不碰存储，便于本地单测。
 */
export class SettingsRules {
  static readonly OTP_LENGTH: number = 6
  static readonly NICKNAME_MAX: number = 255
  static readonly PASSWORD_CURRENT_MIN: number = 4
  static readonly PASSWORD_NEW_MIN: number = 6
  static readonly PASSWORD_MAX: number = 128

  /** 存储里只认 light / dark / system，其它一律回落 light（老用户的默认） */
  static normalizeThemeMode(raw: string | undefined): string {
    if (raw === Constant.APP_THEME_DARK || raw === Constant.APP_THEME_SYSTEM) {
      return raw
    }
    return Constant.APP_THEME_LIGHT
  }

  static clampUploadConcurrent(raw: number | undefined): number {
    if (raw === undefined || typeof raw !== 'number' || Number.isNaN(raw)) {
      return Constant.UPLOAD_CONCURRENT_DEFAULT
    }
    return Math.max(Constant.UPLOAD_CONCURRENT_MIN, Math.min(Constant.UPLOAD_CONCURRENT_MAX, Math.round(raw)))
  }

  /** 返回第一条错误文案；合法返回空串 */
  static nicknameError(nick: string): string {
    const trimmed = nick.trim()
    if (trimmed.length === 0) {
      return '昵称不能为空'
    }
    if (trimmed.length > SettingsRules.NICKNAME_MAX) {
      return `昵称最多 ${SettingsRules.NICKNAME_MAX} 个字符`
    }
    return ''
  }

  /** 与服务端 PatchUserSetting 的 binding 对齐：当前密码 4–128，新密码 6–128 */
  static passwordError(current: string, next: string, confirm: string): string {
    if (current.length < SettingsRules.PASSWORD_CURRENT_MIN) {
      return '请输入当前密码'
    }
    if (next.length < SettingsRules.PASSWORD_NEW_MIN) {
      return `新密码至少 ${SettingsRules.PASSWORD_NEW_MIN} 位`
    }
    if (next.length > SettingsRules.PASSWORD_MAX) {
      return `新密码最多 ${SettingsRules.PASSWORD_MAX} 位`
    }
    if (next !== confirm) {
      return '两次输入的新密码不一致'
    }
    return ''
  }

  static isValidOtp(code: string): boolean {
    return /^\d{6}$/.test(code)
  }

  static buildOtpAuthUri(issuer: string, account: string, secret: string): string {
    const name = issuer.trim().length > 0 ? issuer.trim() : 'Cloudreve'
    const label = encodeURIComponent(`${name}:${account}`)
    return `otpauth://totp/${label}?secret=${secret}&issuer=${encodeURIComponent(name)}`
  }

  /** 每 4 位一组，方便用户手抄到验证器 */
  static groupSecret(secret: string): string {
    const parts: string[] = []
    for (let index = 0; index < secret.length; index += SECRET_GROUP_SIZE) {
      parts.push(secret.substring(index, index + SECRET_GROUP_SIZE))
    }
    return parts.join(' ')
  }

  static joinNonEmpty(parts: string[], separator: string): string {
    return parts.filter((part: string) => part.trim().length > 0).join(separator)
  }

  /** MM/dd HH:mm（本地时区）；无效或 Go 零值时间返回空串 */
  static formatShortDateTime(iso: string): string {
    const date = parseDate(iso)
    if (!date) {
      return ''
    }
    return `${pad2(date.getMonth() + 1)}/${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`
  }

  /** yyyy/MM/dd（本地时区）；无效或 Go 零值时间返回空串 */
  static formatDate(iso: string): string {
    const date = parseDate(iso)
    if (!date) {
      return ''
    }
    return `${date.getFullYear()}/${pad2(date.getMonth() + 1)}/${pad2(date.getDate())}`
  }

  /** 从 crate 的 "API error: <msg> (code: N)" 里取出服务端原文；其它消息原样返回 */
  static apiMessage(raw: string): string {
    const match = API_ERROR_PATTERN.exec(raw)
    return match && match[1] ? match[1] : raw
  }
}
