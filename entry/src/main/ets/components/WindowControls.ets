import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { WindowMover } from '../utils/WindowMover'
import { TitleControlButton } from './TitleControlButton'

/**
 * 2in1 自绘窗口三键（最小化 / 最大化·还原 / 关闭），替代隐藏掉的系统三键。
 * 按键用 TitleControlButton，与侧栏折叠键、HDS 标题栏按钮同一套；关闭键悬停转危险色。
 *由 Index 叠在整棵页面树之上、贴右上角，视频全屏时隐藏。
 */
@Component
export struct WindowControls {
  @StorageProp(Constant.WINDOW_STATUS) windowStatus: number = window.WindowStatusType.UNDEFINED
  // 视频全屏播放时由 Index 置 true：全屏态让出画面；其它来源的全屏仍显示，保证能还原
  @Prop hideInFullScreen: boolean = false

  private isMaximized(): boolean {
    return this.windowStatus === window.WindowStatusType.MAXIMIZE ||
      this.windowStatus === window.WindowStatusType.FULL_SCREEN
  }

  build() {
    if (!(this.hideInFullScreen && this.windowStatus === window.WindowStatusType.FULL_SCREEN)) {
      Row({ space: CloudThemeToken.windowControlGap }) {
        Divider()
          .vertical(true)
          .height(CloudThemeToken.windowControlDividerHeight)
          .strokeWidth(CloudThemeToken.windowControlDividerWidth)
          .color(CloudThemeToken.line)

        TitleControlButton({ icon: $r('app.media.ic_window_minimize'), label: '最小化', onAction: () => {
          WindowMover.minimize()
        } })
        // 图标随窗口状态切换：必须经子组件 @Prop 传入，@Builder 按值传参不会重渲染
        TitleControlButton({
          icon: this.isMaximized() ? $r('app.media.ic_window_restore') : $r('app.media.ic_window_maximize'),
          label: this.isMaximized() ? '还原' : '最大化',
          onAction: () => {
            WindowMover.toggleMaximize()
          }
        })
        TitleControlButton({ icon: $r('app.media.ic_window_close'), label: '关闭', danger: true, onAction: () => {
          WindowMover.close(this.getUIContext().getHostContext() as common.UIAbilityContext)
        } })
      }
      .height(CloudThemeToken.rowHeight5xl)
      .padding({ right: CloudThemeToken.windowControlEndMargin })
      .alignItems(VerticalAlign.Center)
    }
  }
}
