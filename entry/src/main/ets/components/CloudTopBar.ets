import { CloudThemeToken } from '../model/CloudTheme';
import { CloudIconButton } from './CloudIconButton';

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
      Column({ space: CloudThemeToken.topBarTextGap }) {
        Text(this.title)
          .fontSize(CloudThemeToken.topBarTitleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.subtitle !== undefined) {
          Text(this.subtitle)
            .fontSize(CloudThemeToken.topBarSubtitleSize)
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
    CloudIconButton({
      icon: icon,
      iconSize: CloudThemeToken.actionIconSize,
      buttonBackground: CloudThemeToken.surface,
      iconColor: CloudThemeToken.textPrimary,
      onAction: onClick
    })
    .margin({ left: CloudThemeToken.topBarActionGap })
  }
}
