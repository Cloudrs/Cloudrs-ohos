import Constant from '../../model/Constant'
import { CloudThemeToken } from '../../model/CloudTheme'
import { CloudMaterial } from '../../model/CloudMaterial'
import { CloudApi } from '../../model/net/CloudApi'
import { SettingsRules } from '../../utils/SettingsRules'
import { OtpInput } from '../OtpInput'
import { showToast } from '../../utils/ToastUtil'
import { pasteboard } from '@kit.BasicServicesKit'
import AppLogger from '../../utils/AppLogger'

const TAG: string = 'TwoFactorSheet'
const SESSION_EXPIRED_HINT: string = 'not initiated 2FA'

/** 步骤标签。独立组件而非 @Builder：active 随 step 变化，@Builder 按值传参不会刷新 */
@Component
struct StepChip {
  @Prop text: string = ''
  @Prop active: boolean = false

  build() {
    Text(this.text)
      .fontSize(CloudThemeToken.textSizeSmall)
      .fontColor(this.active ? CloudThemeToken.primary : CloudThemeToken.textSecondary)
      .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
      // 半模态材质上不用实色块：当前步半透明主色浅染，其余透明 + 细描边（描边宽度两态一致，切换时不跳动）
      .backgroundColor(this.active ? CloudThemeToken.selectedTint : CloudThemeToken.transparent)
      .border({ width: CloudThemeToken.lineWidth, color: this.active ? CloudThemeToken.transparent : CloudThemeToken.line })
      .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard,
        top: CloudThemeToken.spacingTiny, bottom: CloudThemeToken.spacingTiny })
      .borderRadius(CloudThemeToken.settingChipRadius)
  }
}

/**
 * 开启：取 secret → 二维码 / 密钥 → 输 6 位码确认；关闭：直接输 6 位码。
 * 服务端 secret 只活 10 分钟，过期报 "You have not initiated 2FA session"，此时退回第一步重取。
 */
@Component
export struct TwoFactorSheet {
  @StorageProp(Constant.KEYBOARD_HEIGHT_VP) keyboardHeightVp: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @Prop enabling: boolean = true
  @Prop issuer: string = ''
  @Prop account: string = ''
  inputId: string = 'twoFactorOtpInput'
  onDone?: (enabled: boolean) => void
  /** 进入验证码步骤时让父组件抓焦点 */
  onCodeStep?: () => void
  @State step: number = 0
  @State secret: string = ''
  @State code: string = ''
  @State busy: boolean = false
  @State error: string = ''
  /** 取密钥失败（含返回空密钥）：停转圈，改显示「重试」 */
  @State secretFailed: boolean = false

  aboutToAppear(): void {
    if (this.enabling) {
      this.fetchSecret()
    } else {
      this.step = 1
    }
  }

  build() {
    Column({ space: CloudThemeToken.spacingSection }) {
      if (this.enabling) {
        Row({ space: CloudThemeToken.spacingMd }) {
          StepChip({ text: '1 添加到验证器', active: this.step === 0 })
          StepChip({ text: '2 输入验证码', active: this.step === 1 })
        }
      }
      if (this.step === 0) {
        this.secretStep()
      } else {
        this.codeStep()
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.danger)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: this.keyboardHeightVp > 0
        ? this.keyboardHeightVp + CloudThemeToken.spacingSheetBottom
        : this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
  }

  @Builder secretStep() {
    Row({ space: CloudThemeToken.spacingPanel }) {
      if (this.secret.length > 0) {
        QRCode(SettingsRules.buildOtpAuthUri(this.issuer, this.account, this.secret))
          .width(CloudThemeToken.qrCodeSize)
          .height(CloudThemeToken.qrCodeSize)
          .color(Color.Black)
          .backgroundColor(Color.White)
          .padding(CloudThemeToken.spacingMd)
          .borderRadius(CloudThemeToken.cardRadius)
      } else if (this.secretFailed) {
        Text('重试')
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.primary)
          .padding(CloudThemeToken.spacingMd)
          .onClick(() => {
            this.error = ''
            this.fetchSecret()
          })
      } else {
        LoadingProgress()
          .width(CloudThemeToken.iconBox2xl)
          .height(CloudThemeToken.iconBox2xl)
      }
      Column({ space: CloudThemeToken.spacingXs }) {
        Text('用验证器扫码，或手动输入密钥')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
        Text(SettingsRules.groupSecret(this.secret))
          .fontSize(CloudThemeToken.textSizeBody)
          .fontFamily('monospace')
          .fontColor(CloudThemeToken.textPrimary)
        Text('复制密钥')
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.primary)
          .padding({ top: CloudThemeToken.spacingXs })
          .onClick(() => this.copySecret())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(CloudThemeToken.spacingPanel)
    .borderRadius(CloudThemeToken.settingGroupRadius)
    // 同输入框：半透明底 + 细描边，不用 surfaceSubtle 实色块盖住半模态材质
    .backgroundColor(CloudMaterial.fieldBackground())
    .border(CloudThemeToken.inputBorder(false))

    Text('同一台手机扫不了码时，复制密钥粘贴到华为验证器、Google Authenticator 等应用。密钥 10 分钟内有效。')
      .fontSize(CloudThemeToken.textSizeSmall)
      .fontColor(CloudThemeToken.textSecondary)

    Button('下一步', { type: ButtonType.Capsule })
      .width('100%')
      .height(CloudThemeToken.rowHeightXl)
      .backgroundColor(CloudThemeToken.primary)
      .enabled(this.secret.length > 0)
      .onClick(() => {
        this.step = 1
        this.error = ''
        this.onCodeStep?.()
      })
  }

  @Builder codeStep() {
    Text(this.enabling ? '输入验证器里显示的 6 位数字' : '关闭后登录只需要密码，安全性会下降。请输入验证器里的 6 位数字确认。')
      .fontSize(CloudThemeToken.textSizeSmallPlus)
      .fontColor(CloudThemeToken.textSecondary)
    OtpInput({
      code: $code,
      inputId: this.inputId,
      onComplete: () => this.submit()
    })
    Row({ space: CloudThemeToken.spacingCard }) {
      if (this.enabling) {
        // 次要按钮同重命名面板的「取消」：surface 底 + 细描边
        Button('上一步', { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(CloudThemeToken.rowHeightXl)
          .backgroundColor(CloudThemeToken.surface)
          .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
          .fontColor(CloudThemeToken.textPrimary)
          .onClick(() => {
            this.step = 0
            this.error = ''
          })
      }
      Button(this.busy ? '验证中…' : (this.enabling ? '开启' : '验证并关闭'), { type: ButtonType.Capsule })
        .layoutWeight(1)
        .height(CloudThemeToken.rowHeightXl)
        .backgroundColor(this.enabling ? CloudThemeToken.primary : CloudThemeToken.danger)
        .enabled(!this.busy && SettingsRules.isValidOtp(this.code))
        .onClick(() => this.submit())
    }
    .width('100%')
  }

  private fetchSecret(): void {
    this.secret = ''
    this.secretFailed = false
    CloudApi.initTwoFactor({
      onSuccess: (secret: string) => {
        if (!secret || secret.length === 0) {
          this.secretFailed = true
          this.error = '获取密钥失败'
          return
        }
        this.secret = secret
      },
      onFailure: (msg: string) => {
        this.secretFailed = true
        this.error = SettingsRules.apiMessage(msg)
      }
    })
  }

  private copySecret(): void {
    if (this.secret.length === 0) {
      return
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.secret)
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        showToast('已复制密钥')
      }).catch((err: Error) => {
        AppLogger.error(TAG, `copy secret failed: ${err.message}`)
      })
    } catch (err) {
      AppLogger.error(TAG, `copy secret failed: ${JSON.stringify(err)}`)
    }
  }

  private submit(): void {
    if (this.busy || !SettingsRules.isValidOtp(this.code)) {
      return
    }
    this.busy = true
    this.error = ''
    CloudApi.setTwoFactor(this.enabling, this.code, {
      onSuccess: () => {
        this.busy = false
        this.onDone?.(this.enabling)
      },
      onFailure: (msg: string) => {
        this.busy = false
        this.code = ''
        const message = SettingsRules.apiMessage(msg)
        if (this.enabling && message.indexOf(SESSION_EXPIRED_HINT) >= 0) {
          this.error = '密钥已过期，已重新生成，请重新添加到验证器'
          this.step = 0
          this.fetchSecret()
          return
        }
        this.error = message
      }
    })
  }
}
