import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct EmptyState {
  icon: ResourceStr = ''
  title: ResourceStr = ''
  description: ResourceStr = ''
  actionText?: ResourceStr
  secondaryActionText?: ResourceStr
  onAction?: () => void
  onSecondaryAction?: () => void

  build() {
    Column({ space: 12 }) {
      if (this.icon !== '') {
        Image(this.icon)
          .width(56)
          .height(56)
          .draggable(false)
      }

      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .textAlign(TextAlign.Center)

      Text(this.description)
        .fontSize(13)
        .fontColor(CloudThemeToken.textSecondary)
        .textAlign(TextAlign.Center)
        .lineHeight(19)

      if (this.actionText !== undefined && this.onAction !== undefined) {
        Button(this.actionText)
          .height(38)
          .onClick(() => {
            this.onAction?.()
          })
      }

      if (this.secondaryActionText !== undefined && this.onSecondaryAction !== undefined) {
        Button(this.secondaryActionText)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(14)
          .fontColor(CloudThemeToken.primary)
          .height(34)
          .onClick(() => {
            this.onSecondaryAction?.()
          })
      }
    }
    .width('100%')
    .padding(24)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .alignItems(HorizontalAlign.Center)
  }
}
