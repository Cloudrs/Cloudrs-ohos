import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct EmptyState {
  icon: ResourceStr = ''
  title: ResourceStr = ''
  description: ResourceStr = ''
  // 不铺卡片底，直接放在半模态材质上（传输进度、路径选择）；卡片底和半模态的大圆角、材质对不上
  plain: boolean = false
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
    .backgroundColor(this.plain ? Color.Transparent : CloudThemeToken.surface)
    .alignItems(HorizontalAlign.Center)
  }
}
