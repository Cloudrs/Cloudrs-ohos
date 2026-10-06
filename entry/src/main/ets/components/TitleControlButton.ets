import { SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit'
import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { CloudMaterial } from '../model/CloudMaterial'

/**
 * 标题栏自绘方块键：侧栏折叠键、2in1 窗口三键、相册下拉、离线下载新建等，
 * 40vp 方块 + titleControlMaterial 光感与按压形变（高算力档为通透玻璃，同相册页时间/相册胶囊；
 * 低档与 HDS 菜单键同为 surfaceSubtle 底）；宽屏小圆角方块、窄屏圆形，同 actionRadiusForWidth。
 * 用容器而非 Button：Button 挂不上 systemMaterial，也就没有 Button 自带的悬停态，
 * 用 hoverEffect(Highlight) 补上（同 HDS）；danger 键悬停另铺危险色。
 */
@Component
export struct TitleControlButton {
  @Prop icon: Resource
  @Prop label: string = ''
  @Prop danger: boolean = false
  @Prop isEnabled: boolean = true
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0
  @State hovered: boolean = false
  onAction?: () => void

  @SuppressWarnings({ rules: [SuppressWarningsType.COMPATIBILITY] })
  build() {
    Stack() {
      if (this.danger && this.hovered) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(CloudThemeToken.danger)
      }
      Image(this.icon)
        .width(CloudThemeToken.windowControlIconSize)
        .height(CloudThemeToken.windowControlIconSize)
        .fillColor(this.danger && this.hovered ? CloudThemeToken.onPrimary : CloudThemeToken.textPrimary)
        .draggable(false)
    }
    .width(CloudThemeToken.windowControlSize)
    .height(CloudThemeToken.windowControlSize)
    // EXQUISITE 档置透明交给通透材质；其余档与低版本用 surfaceSubtle 实色（见 CloudMaterial.titleControlMaterial）
    .backgroundColor(CloudMaterial.controlSurface(CloudThemeToken.surfaceSubtle))
    .systemMaterial(CloudMaterial.titleControlMaterial())
    // 容器没有 Button 自带的悬停态，用系统 Highlight 补上（与 HDS 按钮悬停压暗/提亮一致）
    .hoverEffect(HoverEffect.Highlight)
    .borderRadius(CloudThemeToken.actionRadiusForWidth(this.windowWidthVp, CloudThemeToken.controlRadius))
    .clip(true)
    .accessibilityText(this.label)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
    .onHover((isHover: boolean) => {
      this.hovered = isHover
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.()
      }
    })
  }
}
