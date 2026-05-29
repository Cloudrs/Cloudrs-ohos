import { CloudThemeToken } from "../model/CloudTheme";

@Component
export struct GlassSurface {
  @Prop radius: number = CloudThemeToken.surfaceRadius
  @Prop paddingValue: Padding | Length = CloudThemeToken.pagePadding
  @Prop background: ResourceColor = CloudThemeToken.surfaceTranslucent
  @BuilderParam content: () => void

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.paddingValue)
    .borderRadius(this.radius)
    .backgroundColor(this.background)
    .border({ width: CloudThemeToken.glassSurfaceBorderWidth, color: CloudThemeToken.line })
  }
}
