import Constant from '../../model/Constant'
import { CloudThemeToken } from '../../model/CloudTheme'
import { CloudMaterial } from '../../model/CloudMaterial'
import { CloudApi } from '../../model/net/CloudApi'
import { SettingsRules } from '../../utils/SettingsRules'

@Component
export struct ChangePasswordSheet {
  @StorageProp(Constant.KEYBOARD_HEIGHT_VP) keyboardHeightVp: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  inputId: string = 'passwordCurrentInput'
  onDone?: () => void
  @State current: string = ''
  @State next: string = ''
  @State confirm: string = ''
  @State busy: boolean = false
  @State serverError: string = ''
  // 当前聚焦的输入框 id，聚焦的那个描边换主色
  @State focusedId: string = ''

  build() {
    Column({ space: CloudThemeToken.spacingSection }) {
      this.field('当前密码', this.current, this.inputId, (v: string) => { this.current = v })
      this.field('新密码', this.next, 'passwordNewInput', (v: string) => { this.next = v })
      this.field('确认新密码', this.confirm, 'passwordConfirmInput', (v: string) => { this.confirm = v })
      Text(this.hintText())
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(this.hintIsError() ? CloudThemeToken.danger : CloudThemeToken.textSecondary)
      Button(this.busy ? '提交中…' : '确认修改', { type: ButtonType.Capsule })
        .width('100%')
        .height(CloudThemeToken.rowHeightXl)
        .backgroundColor(CloudThemeToken.primary)
        .enabled(!this.busy && SettingsRules.passwordError(this.current, this.next, this.confirm).length === 0)
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

  @Builder field(label: string, value: string, id: string, onChange: (v: string) => void) {
    Column({ space: CloudThemeToken.spacingSm }) {
      Text(label).fontSize(CloudThemeToken.textSizeSmallPlus).fontColor(CloudThemeToken.textSecondary)
      TextInput({ text: value })
        .id(id)
        .type(InputType.Password)
        .maxLength(SettingsRules.PASSWORD_MAX)
        .height(CloudThemeToken.inputHeight)
        .borderRadius(CloudThemeToken.inputRadius)
        .backgroundColor(CloudMaterial.fieldBackground())
        .border(CloudThemeToken.inputBorder(this.focusedId === id))
        .onFocus(() => {
          this.focusedId = id
        })
        .onBlur(() => {
          if (this.focusedId === id) {
            this.focusedId = ''
          }
        })
        .onChange((v: string) => {
          onChange(v)
          this.serverError = ''
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 输入未完成时显示规则提示；输入了但不合规显示具体错误；服务端错误优先 */
  private hintText(): string {
    if (this.serverError.length > 0) {
      return this.serverError
    }
    if (this.next.length === 0 && this.confirm.length === 0) {
      return `新密码 ${SettingsRules.PASSWORD_NEW_MIN}–${SettingsRules.PASSWORD_MAX} 位`
    }
    const error = SettingsRules.passwordError(this.current, this.next, this.confirm)
    return error.length > 0 ? error : '可以提交'
  }

  private hintIsError(): boolean {
    if (this.serverError.length > 0) {
      return true
    }
    if (this.next.length === 0 && this.confirm.length === 0) {
      return false
    }
    return SettingsRules.passwordError(this.current, this.next, this.confirm).length > 0
  }

  private submit(): void {
    if (this.busy || SettingsRules.passwordError(this.current, this.next, this.confirm).length > 0) {
      return
    }
    this.busy = true
    CloudApi.changePassword(this.current, this.next, {
      onSuccess: () => {
        this.busy = false
        this.onDone?.()
      },
      onFailure: (msg: string) => {
        this.busy = false
        this.serverError = SettingsRules.apiMessage(msg)
      }
    })
  }
}
