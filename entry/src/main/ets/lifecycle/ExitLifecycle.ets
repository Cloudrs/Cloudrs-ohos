import { HMLifecycle, HMLifecycleContext, IHMLifecycle } from '@hadss/hmrouter'
import { common } from '@kit.AbilityKit'
import { showToast, showToastTips } from '../utils/ToastUtil'

@HMLifecycle({ lifecycleName: 'ExitLifecycle' })
export class ExitLifecycle implements IHMLifecycle {
  private backTimeStamp: number = 0

  onBackPressed(ctx: HMLifecycleContext): boolean {
    let now = Date.now()
    if (now - this.backTimeStamp < 1000) {
      const ctx = getContext(this) as common.UIAbilityContext
      ctx.terminateSelf() //终止程序
    } else {
      this.backTimeStamp = now
      showToast('再滑一次退出')
    }
    return true
  }
}