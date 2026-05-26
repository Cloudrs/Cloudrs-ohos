import { HMLifecycle, HMLifecycleContext, IHMLifecycle } from '@hadss/hmrouter'
import { common } from '@kit.AbilityKit'
import { showToast } from '../utils/ToastUtil'

@HMLifecycle({ lifecycleName: 'ExitLifecycle' })
export class ExitLifecycle implements IHMLifecycle {
  private backTimeStamp: number = 0
  onBackPressedCallback?: () => boolean;

  onBackPressed(ctx: HMLifecycleContext): boolean {
    if (this.onBackPressedCallback) {
      if (this.onBackPressedCallback()) {
        return true
      }
    }

    let now = Date.now()
    if (now - this.backTimeStamp < 1000) {
      const abilityContext = ctx.uiContext.getHostContext() as common.UIAbilityContext | undefined
      if (!abilityContext) {
        showToast('退出失败')
        return true
      }
      abilityContext.terminateSelf().catch((err: Error) => {
        console.error('ExitLifecycle', `terminateSelf failed: ${err.message}`)
        showToast('退出失败')
      })
    } else {
      this.backTimeStamp = now
      showToast('再滑一次退出')
    }

    return true
  }
}
