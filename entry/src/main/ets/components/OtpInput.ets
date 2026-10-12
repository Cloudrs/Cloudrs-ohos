import { CloudThemeToken } from '../model/CloudTheme'
import { CloudMaterial } from '../model/CloudMaterial'

function buildIndexes(): number[] {
  const indexes: number[] = []
  for (let index = 0; index < CloudThemeToken.loginOtpLength; index++) {
    indexes.push(index)
  }
  return indexes
}

/**
 * 6 格验证码：一行展示格 + 一个透明的数字输入框叠在上面。
 * code 用 @Link，父组件清空（如验证失败）时输入框内容一并清空。
 * 聚焦由父组件按 inputId 调 focusController.requestFocus，以便放在 sheet 入场动画之后。
 */
@Component
export struct OtpInput {
  @Link code: string
  inputId: string = 'otpInput'
  onComplete?: (code: string) => void
  private readonly indexes: number[] = buildIndexes()

  build() {
    Stack() {
      Row({ space: CloudThemeToken.loginOtpCellGap }) {
        ForEach(this.indexes, (item: number) => {
          Column() {
            Text(item < this.code.length ? this.code[item] : '')
              .fontSize(CloudThemeToken.loginOtpCellTextSize)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary)
          }
          .width(CloudThemeToken.loginOtpCellWidth)
          .height(CloudThemeToken.loginOtpCellHeight)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderRadius(CloudThemeToken.otpCellRadius)
          // 同其它输入框：半透明底 + 1px 描边，待输入的那格描边换主色加粗
          .backgroundColor(CloudMaterial.fieldBackground())
          .border(this.code.length === item
            ? { width: CloudThemeToken.loginOtpBorderWidth, color: CloudThemeToken.primary }
            : CloudThemeToken.inputBorder(false))
        }, (item: number) => item.toString())
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')

      TextInput({ text: this.code })
        .id(this.inputId)
        .type(InputType.Number)
        .maxLength(CloudThemeToken.loginOtpLength)
        .width('100%')
        .height(CloudThemeToken.loginOtpCellHeight)
        .opacity(CloudThemeToken.invisibleOpacity)
        .enterKeyType(EnterKeyType.Go)
        .onChange((value: string) => {
          this.code = value
          if (value.length === CloudThemeToken.loginOtpLength) {
            this.onComplete?.(value)
          }
        })
        .onSubmit(() => {
          this.onComplete?.(this.code)
        })
    }
    .width('100%')
    .height(CloudThemeToken.loginOtpCellHeight)
  }
}
