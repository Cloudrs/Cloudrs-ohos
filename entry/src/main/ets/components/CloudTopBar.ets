import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct CloudTopBar {
  title: ResourceStr = ''
  subtitle?: ResourceStr
  actionIcon?: ResourceStr
  secondaryActionIcon?: ResourceStr
  onAction?: () => void
  onSecondaryAction?: () => void

  build() {
    Row() {
      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.subtitle !== undefined) {
          Text(this.subtitle)
            .fontSize(13)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.secondaryActionIcon !== undefined && this.onSecondaryAction !== undefined) {
        this.iconButton(this.secondaryActionIcon, this.onSecondaryAction)
      }

      if (this.actionIcon !== undefined && this.onAction !== undefined) {
        this.iconButton(this.actionIcon, this.onAction)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder iconButton(icon: ResourceStr, onClick: () => void) {
    Button() {
      Image(icon)
        .width(CloudThemeToken.actionIconSize)
        .height(CloudThemeToken.actionIconSize)
        .fillColor(CloudThemeToken.textPrimary)
        .draggable(false)
    }
    .width(CloudThemeToken.iconButtonSize)
    .height(CloudThemeToken.iconButtonSize)
    .borderRadius(CloudThemeToken.controlRadius)
    .backgroundColor(CloudThemeToken.surface)
    .margin({ left: 8 })
    .onClick(onClick)
  }
}
