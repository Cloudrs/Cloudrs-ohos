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
        .fontSize(CloudThemeToken.sectionHeaderTitleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)

      if (this.count !== undefined) {
        Text(this.count.toString())
          .fontSize(CloudThemeToken.sectionHeaderCountSize)
          .fontColor(CloudThemeToken.textSecondary)
          .margin({ left: CloudThemeToken.sectionHeaderCountGap })
      }

      Blank()

      if (this.actionText !== undefined && this.onAction !== undefined) {
        Button(this.actionText)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(CloudThemeToken.sectionHeaderActionSize)
          .fontColor(CloudThemeToken.primary)
          .height(CloudThemeToken.sectionHeaderActionHeight)
          .onClick(() => {
            this.onAction?.()
          })
      }
    }
    .width('100%')
    .height(CloudThemeToken.sectionHeaderHeight)
    .alignItems(VerticalAlign.Center)
    .margin({ top: CloudThemeToken.sectionHeaderTopMargin })
  }
}
