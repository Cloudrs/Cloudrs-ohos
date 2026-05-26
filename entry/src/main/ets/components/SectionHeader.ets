import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct SectionHeader {
  title: ResourceStr = ''
  count?: number
  actionText?: ResourceStr
  onAction?: () => void

  build() {
    Row() {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)

      if (this.count !== undefined) {
        Text(this.count.toString())
          .fontSize(13)
          .fontColor(CloudThemeToken.textSecondary)
          .margin({ left: 8 })
      }

      Blank()

      if (this.actionText !== undefined && this.onAction !== undefined) {
        Button(this.actionText)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(13)
          .fontColor(CloudThemeToken.primary)
          .height(32)
          .onClick(() => {
            this.onAction?.()
          })
      }
    }
    .width('100%')
    .height(36)
    .alignItems(VerticalAlign.Center)
    .margin({ top: 4 })
  }
}
