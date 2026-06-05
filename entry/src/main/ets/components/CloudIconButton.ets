import { hdsEffect } from '@kit.UIDesignKit';
import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct CloudIconButton {
  @Prop icon: ResourceStr = ''
  @Prop buttonSize: number = CloudThemeToken.iconButtonSize
  @Prop iconSize: number = CloudThemeToken.actionIconSize
  @Prop iconPadding: number = CloudThemeToken.zero
  @Prop buttonRadius: number = CloudThemeToken.controlRadius
  @Prop buttonBackground: ResourceColor = CloudThemeToken.surface
  @Prop iconColor: ResourceColor = CloudThemeToken.textPrimary
  @Prop isEnabled: boolean = true
  @Prop badgeCount: number = CloudThemeToken.zero
  @Prop badgeSize: number = CloudThemeToken.filesHeaderBadgeSize
  onAction?: () => void

  @Builder iconContent() {
    Image(this.icon)
      .width(this.iconSize)
      .height(this.iconSize)
      .padding(this.iconPadding)
      .fillColor(this.iconColor)
      .draggable(false)
  }

  @Builder defaultContent() {
    if (this.badgeCount > CloudThemeToken.zero) {
      Badge({
        count: this.badgeCount,
        style: { badgeSize: this.badgeSize },
        position: BadgePosition.RightTop
      }) {
        this.iconContent()
      }
    } else {
      this.iconContent()
    }
  }

  private getPressEffect(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: CloudThemeToken.onPrimary,
          intensity: CloudThemeToken.hdsIconButtonLightIntensity,
          height: CloudThemeToken.hdsIconButtonLightHeight,
          bloom: CloudThemeToken.hdsIconButtonLightBloom
        }
      })
      .buildEffect()
  }

  build() {
    if (this.onAction) {
      Button({ type: ButtonType.Normal }) {
        this.defaultContent()
      }
      .width(this.buttonSize)
      .height(this.buttonSize)
      .borderRadius(this.buttonRadius)
      .backgroundColor(this.buttonBackground)
      .enabled(this.isEnabled)
      .opacity(this.isEnabled ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
      .visualEffect(this.getPressEffect())
      .onClick(() => {
        if (this.isEnabled && this.onAction) {
          this.onAction()
        }
      })
    } else {
      Button({ type: ButtonType.Normal }) {
        this.defaultContent()
      }
      .width(this.buttonSize)
      .height(this.buttonSize)
      .borderRadius(this.buttonRadius)
      .backgroundColor(this.buttonBackground)
      .enabled(this.isEnabled)
      .opacity(this.isEnabled ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
      .visualEffect(this.getPressEffect())
    }
  }
}
