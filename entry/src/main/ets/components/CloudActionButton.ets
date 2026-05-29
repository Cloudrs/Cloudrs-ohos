import { CloudThemeToken } from "../model/CloudTheme";

export enum CloudActionButtonStyle {
  PRIMARY = 'primary',
  SURFACE = 'surface',
  DANGER = 'danger'
}

@Component
export struct CloudActionButton {
  @Prop icon: Resource
  @Prop text: ResourceStr = ''
  @Prop style: CloudActionButtonStyle = CloudActionButtonStyle.SURFACE
  @Prop isEnabled: boolean = true
  onAction?: () => void

  private getBackgroundColor(): ResourceColor {
    switch (this.style) {
      case CloudActionButtonStyle.PRIMARY:
        return CloudThemeToken.primary
      case CloudActionButtonStyle.DANGER:
        return CloudThemeToken.danger
      default:
        return CloudThemeToken.surface
    }
  }

  private getForegroundColor(): ResourceColor | Color {
    switch (this.style) {
      case CloudActionButtonStyle.PRIMARY:
      case CloudActionButtonStyle.DANGER:
        return CloudThemeToken.onPrimary
      default:
        return CloudThemeToken.textPrimary
    }
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: this.text === '' ? 0 : CloudThemeToken.actionButtonContentGap }) {
        Image(this.icon)
          .width(CloudThemeToken.actionButtonIconSize)
          .height(CloudThemeToken.actionButtonIconSize)
          .fillColor(this.getForegroundColor())

        if (this.text !== '') {
          Text(this.text)
            .fontSize(CloudThemeToken.actionButtonTextSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getForegroundColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .height(CloudThemeToken.actionButtonHeight)
    .padding({
      left: this.text === '' ? CloudThemeToken.actionButtonIconPadding : CloudThemeToken.actionButtonTextPadding,
      right: this.text === '' ? CloudThemeToken.actionButtonIconPadding : CloudThemeToken.actionButtonTextPadding
    })
    .borderRadius(CloudThemeToken.controlRadius)
    .backgroundColor(this.getBackgroundColor())
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.45)
    .onClick(() => {
      if (this.isEnabled && this.onAction) {
        this.onAction()
      }
    })
  }
}
