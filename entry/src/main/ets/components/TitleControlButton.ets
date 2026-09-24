import { SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit'
import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { CloudMaterial } from '../model/CloudMaterial'

/**
 * 标题栏自绘方块键：侧栏折叠键、2in1 窗口三键、相册下拉、离线下载新建等，
 * 与 HDS 标题栏菜单键并排时观感一致——40vp、surfaceSubtle 底（实测即 HDS 菜单键常态底色）
 * + titleControlMaterial 光感与按压形变；宽屏小圆角方块、窄屏圆形，同 actionRadiusForWidth。
 * 用容器而非 Button：Button 挂不上 systemMaterial。danger 键悬停时在材质之上铺一层危险色。
 */
@Component
export struct TitleControlButton {
  @Prop icon: Resource
  @Prop label: string = ''
  @Prop danger: boolean = false
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
    // 材质会盖住底色，故材质本身也染同色（见 CloudMaterial.titleControlMaterial）
    .backgroundColor(CloudThemeToken.surfaceSubtle)
    .systemMaterial(CloudMaterial.titleControlMaterial())
    .borderRadius(CloudThemeToken.actionRadiusForWidth(this.windowWidthVp, CloudThemeToken.controlRadius))
    .clip(true)
    .accessibilityText(this.label)
    .onHover((isHover: boolean) => {
      this.hovered = isHover
    })
    .onClick(() => {
      this.onAction?.()
    })
  }
}
