import { describe, it, expect } from '@ohos/hypium'
import { SettingsRules } from '../main/ets/utils/SettingsRules'

export default function settingsRulesTest() {
  describe('SettingsRules', () => {
    it('theme_keepsKnownModes', 0, () => {
      expect(SettingsRules.normalizeThemeMode('light')).assertEqual('light')
      expect(SettingsRules.normalizeThemeMode('dark')).assertEqual('dark')
      expect(SettingsRules.normalizeThemeMode('system')).assertEqual('system')
    })
    it('theme_unknownFallsBackToLight', 0, () => {
      expect(SettingsRules.normalizeThemeMode('')).assertEqual('light')
      expect(SettingsRules.normalizeThemeMode('auto')).assertEqual('light')
      expect(SettingsRules.normalizeThemeMode(undefined)).assertEqual('light')
    })
    it('concurrent_clamps', 0, () => {
      expect(SettingsRules.clampUploadConcurrent(0)).assertEqual(1)
      expect(SettingsRules.clampUploadConcurrent(11)).assertEqual(10)
      expect(SettingsRules.clampUploadConcurrent(4)).assertEqual(4)
      expect(SettingsRules.clampUploadConcurrent(2.6)).assertEqual(3)
      expect(SettingsRules.clampUploadConcurrent(Number.NaN)).assertEqual(3)
      expect(SettingsRules.clampUploadConcurrent(undefined)).assertEqual(3)
    })
    it('nickname_validation', 0, () => {
      expect(SettingsRules.nicknameError('')).assertEqual('昵称不能为空')
      expect(SettingsRules.nicknameError('   ')).assertEqual('昵称不能为空')
      expect(SettingsRules.nicknameError('a'.repeat(256))).assertEqual('昵称最多 255 个字符')
      expect(SettingsRules.nicknameError(' Neo ')).assertEqual('')
    })
    it('password_validation', 0, () => {
      expect(SettingsRules.passwordError('abc', 'newpass', 'newpass')).assertEqual('请输入当前密码')
      expect(SettingsRules.passwordError('abcd', 'short', 'short')).assertEqual('新密码至少 6 位')
      expect(SettingsRules.passwordError('abcd', 'a'.repeat(129), 'a'.repeat(129))).assertEqual('新密码最多 128 位')
      expect(SettingsRules.passwordError('abcd', 'newpass', 'newpasx')).assertEqual('两次输入的新密码不一致')
      expect(SettingsRules.passwordError('abcd', 'newpass', 'newpass')).assertEqual('')
    })
    it('otp_validation', 0, () => {
      expect(SettingsRules.isValidOtp('123456')).assertTrue()
      expect(SettingsRules.isValidOtp('12345')).assertFalse()
      expect(SettingsRules.isValidOtp('12345a')).assertFalse()
    })
    it('otpauth_uri', 0, () => {
      expect(SettingsRules.buildOtpAuthUri('My Cloud', 'a@b.com', 'ABC'))
        .assertEqual('otpauth://totp/My%20Cloud%3Aa%40b.com?secret=ABC&issuer=My%20Cloud')
      expect(SettingsRules.buildOtpAuthUri('  ', 'a@b.com', 'ABC'))
        .assertEqual('otpauth://totp/Cloudreve%3Aa%40b.com?secret=ABC&issuer=Cloudreve')
    })
    it('secret_grouping', 0, () => {
      expect(SettingsRules.groupSecret('JBSWY3DPEHPK3PXP')).assertEqual('JBSW Y3DP EHPK 3PXP')
      expect(SettingsRules.groupSecret('ABCDEF')).assertEqual('ABCD EF')
    })
    it('join_nonEmpty', 0, () => {
      expect(SettingsRules.joinNonEmpty(['a', '', ' ', 'b'], ' · ')).assertEqual('a · b')
    })
    it('date_formatting', 0, () => {
      expect(SettingsRules.formatShortDateTime(new Date(2026, 9, 8, 9, 5).toISOString())).assertEqual('10/08 09:05')
      expect(SettingsRules.formatShortDateTime('')).assertEqual('')
      expect(SettingsRules.formatShortDateTime('bad')).assertEqual('')
      expect(SettingsRules.formatDate(new Date(2026, 11, 31, 12, 0).toISOString())).assertEqual('2026/12/31')
      expect(SettingsRules.formatDate('0001-01-01T00:00:00Z')).assertEqual('')
    })
    it('api_message_extraction', 0, () => {
      expect(SettingsRules.apiMessage('API error: Incorrect password (code: 40004)')).assertEqual('Incorrect password')
      expect(SettingsRules.apiMessage('网络连接失败')).assertEqual('网络连接失败')
    })
  })
}
