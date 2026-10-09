import Constant from '../../model/Constant'
import { CloudThemeToken } from '../../model/CloudTheme'
import { CloudApi } from '../../model/net/CloudApi'
import { SettingsRules } from '../../utils/SettingsRules'

@Component
export struct NicknameSheet {
  @StorageProp(Constant.KEYBOARD_HEIGHT_VP) keyboardHeightVp: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @Prop initial: string = ''
  inputId: string = 'nicknameInput'
  onDone?: (nick: string) => void
  @State value: string = ''
  @State busy: boolean = false
  @State error: string = ''

  aboutToAppear(): void {
    this.value = this.initial
  }

  build() {
    Column({ space: CloudThemeToken.spacingSection }) {
      TextInput({ text: this.value, placeholder: '输入新昵称' })
        .id(this.inputId)
        .maxLength(SettingsRules.NICKNAME_MAX)
        .height(CloudThemeToken.inputHeight)
        .fontSize(CloudThemeToken.textSizeLarge)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        .onChange((v: string) => {
          this.value = v
          this.error = ''
        })
        .onSubmit(() => this.submit())
      if (this.error.length > 0) {
        Text(this.error).fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.danger)
      }
      Button(this.busy ? '保存中…' : '保存', { type: ButtonType.Capsule })
        .width('100%')
        .height(CloudThemeToken.rowHeightXl)
        .backgroundColor(CloudThemeToken.primary)
        .enabled(!this.busy && SettingsRules.nicknameError(this.value).length === 0)
        .onClick(() => this.submit())
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

  private submit(): void {
    const error = SettingsRules.nicknameError(this.value)
    if (error.length > 0) {
      this.error = error
      return
    }
    if (this.busy) {
      return
    }
    const nick = this.value.trim()
    this.busy = true
    CloudApi.updateNickname(nick, {
      onSuccess: () => {
        this.busy = false
        this.onDone?.(nick)
      },
      onFailure: (msg: string) => {
        this.busy = false
        this.error = SettingsRules.apiMessage(msg)
      }
    })
  }
}
