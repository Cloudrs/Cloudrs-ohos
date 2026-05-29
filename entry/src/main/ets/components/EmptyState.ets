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
    Column({ space: CloudThemeToken.emptyStateGap }) {
      if (this.icon !== '') {
        Image(this.icon)
          .width(CloudThemeToken.emptyStateIconSize)
          .height(CloudThemeToken.emptyStateIconSize)
          .draggable(false)
      }

      Text(this.title)
        .fontSize(CloudThemeToken.emptyStateTitleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .textAlign(TextAlign.Center)

      Text(this.description)
        .fontSize(CloudThemeToken.emptyStateDescriptionSize)
        .fontColor(CloudThemeToken.textSecondary)
        .textAlign(TextAlign.Center)
        .lineHeight(CloudThemeToken.emptyStateDescriptionLineHeight)

      if (this.actionText !== undefined && this.onAction !== undefined) {
        Button(this.actionText)
          .height(CloudThemeToken.emptyStatePrimaryActionHeight)
          .onClick(() => {
            this.onAction?.()
          })
      }

      if (this.secondaryActionText !== undefined && this.onSecondaryAction !== undefined) {
        Button(this.secondaryActionText)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(CloudThemeToken.emptyStateSecondaryActionSize)
          .fontColor(CloudThemeToken.primary)
          .height(CloudThemeToken.emptyStateSecondaryActionHeight)
          .onClick(() => {
            this.onSecondaryAction?.()
          })
      }
    }
    .width('100%')
    .padding(CloudThemeToken.emptyStatePadding)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .alignItems(HorizontalAlign.Center)
  }
}
