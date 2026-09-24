import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import Constant from '../model/Constant'
import AppLogger from './AppLogger'

const TAG = 'WindowMover'

/**
 * 2in1 隐藏系统标题栏后，窗口拖动由应用自绘区域承担（侧栏顶行、各页标题文字与空白处）。
 * 系统要求在 TouchType.Down 回调里调用 startMoving，窗口才会跟随指针移动。
 * 只挂在标题文字/空白上，不要挂在含按钮的整行上——触摸事件会从按钮冒泡上来，按按钮也会拖动窗口。
 * 主窗口由 MainAbility 在 loadContent 生效后注入；非 2in1 不注入，onTouch 即为空操作。
 *
 * 系统三键隐藏后，最小化/最大化/关闭也由这里代办（WindowControls 调用），
 * 窗口状态同步到 AppStorage(WINDOW_STATUS) 供最大化键切换图标。
 */
export class WindowMover {
  private static mainWindow?: window.Window

  static attach(win: window.Window): void {
    if (deviceInfo.deviceType !== '2in1') {
      return
    }
    WindowMover.mainWindow = win
    try {
      AppStorage.setOrCreate(Constant.WINDOW_STATUS, win.getWindowStatus())
      win.on('windowStatusChange', (status: window.WindowStatusType) => {
        AppStorage.setOrCreate(Constant.WINDOW_STATUS, status)
      })
    } catch (err) {
      AppLogger.warn(TAG, `watch window status failed: ${(err as Error)?.message ?? ''}`)
    }
  }

  static onTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down || !WindowMover.mainWindow) {
      return
    }
    WindowMover.mainWindow.startMoving().catch((err: Error) => {
      AppLogger.warn(TAG, `start moving window failed: ${err.message}`)
    })
  }

  static minimize(): void {
    WindowMover.mainWindow?.minimize().catch((err: Error) => {
      AppLogger.warn(TAG, `minimize window failed: ${err.message}`)
    })
  }

  static toggleMaximize(): void {
    const win = WindowMover.mainWindow
    if (!win) {
      return
    }
    try {
      const status = win.getWindowStatus()
      // 普通最大化保留程序坞与标题栏悬停，不走沉浸全屏（默认跟随应用沉浸设置，2in1 上会进全屏）；
      // 全屏态（如视频全屏遗留）也按还原处理，保证总能退出
      const maximized = status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN
      const action = maximized ? win.recover() : win.maximize(window.MaximizePresentation.EXIT_IMMERSIVE)
      action.catch((err: Error) => {
        AppLogger.warn(TAG, `toggle maximize failed: ${err.message}`)
      })
    } catch (err) {
      AppLogger.warn(TAG, `toggle maximize failed: ${(err as Error)?.message ?? ''}`)
    }
  }

  static close(context: common.UIAbilityContext): void {
    context.terminateSelf().catch((err: Error) => {
      AppLogger.warn(TAG, `close window failed: ${err.message}`)
    })
  }
}
