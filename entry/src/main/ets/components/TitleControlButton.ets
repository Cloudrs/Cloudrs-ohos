import { SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit'
import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { CloudMaterial } from '../model/CloudMaterial'

/**
 * 自绘方块键：侧栏折叠键、2in1 窗口三键、相册下拉、离线下载新建、文本预览顶栏等，
 * 40vp 方块，宽屏小圆角方块、窄屏圆形，同 actionRadiusForWidth。
 * 沉浸光感（材质 + 交互形变）只在 Navigation 标题栏 / 底部 TabBar 内生效：
 * - inTitleBar（放在 HdsNavigation 标题栏 stackBuilder 里）：底色置透明交给 titleControlMaterial，
 *   效果随设备档位由系统自适应，另加细白光边与 HDS 标题栏键观感对齐；
 * - 其余位置材质不生效（2in1 上实测仍会出按压形变，故照挂），用 surfaceSubtle 实底保证各设备都看得见，
 *   与 HDS 菜单键的实色底一致。
 * 用容器而非 Button：Button 挂不上 systemMaterial，也就没有 Button 自带的悬停态，
 * 用 hoverEffect(Highlight) 补上（同 HDS）；danger 键悬停另铺危险色。
 */
@Component
export struct TitleControlButton {
  @Prop icon: Resource
  @Prop label: string = ''
  @Prop danger: boolean = false
  @Prop isEnabled: boolean = true
  // 是否放在 Navigation 标题栏内（沉浸光感生效范围），见类注释
  @Prop inTitleBar: boolean = false
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
    .backgroundColor(this.inTitleBar ? CloudMaterial.materialSurface(CloudThemeToken.surfaceSubtle) :
    CloudThemeToken.surfaceSubtle)
    .border(this.inTitleBar ? { width: CloudThemeToken.controlRimWidth, color: CloudThemeToken.controlRim } :
      { width: CloudThemeToken.zero })
    // 容器没有 Button 自带的悬停态，用系统 Highlight 补上（与 HDS 按钮悬停压暗/提亮一致）
    .hoverEffect(HoverEffect.Highlight)
    .borderRadius(CloudThemeToken.actionRadiusForWidth(this.windowWidthVp, CloudThemeToken.controlRadius))
    .clip(true)
    // 官方要求 systemMaterial 写在背景色、边框等样式属性之后
    .systemMaterial(CloudMaterial.titleControlMaterial())
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
