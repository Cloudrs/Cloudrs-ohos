import { AbilityConstant, contextConstant, StartOptions, Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import AppLogger from '../utils/AppLogger';
import { CloudStatusBar } from '../utils/CloudStatusBar';
import { ContinuationCenter } from '../utils/ContinuationCenter';
import MainAbility from './MainAbility';

const TAG: string = 'EntryAbility';

/**
 * 桌面入口。Ability 名保持与线上 1.1.0 一致(EntryAbility),升级不重建桌面图标。
 *
 * - phone/tablet:即完整应用,全部生命周期走 MainAbility(父类)。
 * - 2in1:仅作跳板 —— 状态栏挂接要求主界面由另一个 Ability 以
 *   ATTACH_TO_STATUS_BAR_ITEM 拉起,这里拉起 MainAbility 后自行退出,不加载 UI。
 */
export default class EntryAbility extends MainAbility {
  private readonly isTwoInOneLauncher: boolean = deviceInfo.deviceType === '2in1'
  private launchRequested: boolean = false
  private targetStarted: boolean = false
  private launcherBackgrounded: boolean = false
  private terminating: boolean = false
  // 2in1 跳板扣下的接续载荷，转发给 MainAbility 后清空
  private pendingContinueParams: Record<string, Object> | undefined = undefined

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (!this.isTwoInOneLauncher) {
      super.onCreate(want, launchParam)
      return
    }
    // 2in1 跳板不加载 UI，先扣下接续载荷，onForeground 里随 MainAbility 一起拉起
    this.captureContinueParams(want)
    AppLogger.init(this.context)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (!this.isTwoInOneLauncher) {
      super.onNewWant(want, launchParam)
      return
    }
    this.captureContinueParams(want)
    // 跳板此前可能已拉起过 MainAbility，放开闸门让 onForeground 再转发一次带参 want
    this.launchRequested = false
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    if (this.isTwoInOneLauncher) {
      // 跳板不承载 UI，2in1 上的接续由 MainAbility 发起
      return AbilityConstant.OnContinueResult.REJECT
    }
    return super.onContinue(wantParam)
  }

  private captureContinueParams(want: Want): void {
    if (!ContinuationCenter.hasPayload(want)) {
      return
    }
    // 跳板与 MainAbility 同进程，载荷直接交给中枢即可；
    // MainAbility 已在运行时根本无法再用 want 传参（startAbility 会被拒）
    ContinuationCenter.acceptPayload(want)
    this.pendingContinueParams = want.parameters
  }

  onDestroy(): void {
    if (!this.isTwoInOneLauncher) {
      super.onDestroy()
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    if (!this.isTwoInOneLauncher) {
      await super.onWindowStageCreate(windowStage)
    }
    // 2in1 跳板不加载 UI,onForeground 中拉起 MainAbility 后退出
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    if (!this.isTwoInOneLauncher) {
      super.onWindowStageRestore(windowStage)
    }
    // 2in1 跳板不加载 UI，接续参数在 onForeground 中转发给 MainAbility
  }

  onWindowStageDestroy(): void {
    if (!this.isTwoInOneLauncher) {
      super.onWindowStageDestroy()
    }
  }

  onForeground(): void {
    if (!this.isTwoInOneLauncher) {
      super.onForeground()
      return
    }
    if (this.launchRequested) {
      return
    }
    this.launchRequested = true
    this.launchMainAbility().catch((err: Error) => {
      this.launchRequested = false
      AppLogger.error(TAG, `launch MainAbility failed: ${err.message}`)
      // 跳板不加载 UI，留在前台就是一块白屏，拉起失败也必须退场
      this.terminateLauncher()
    })
  }

  onBackground(): void {
    if (!this.isTwoInOneLauncher) {
      super.onBackground()
      return
    }
    this.launcherBackgrounded = true
    this.terminateAfterTargetStarted()
  }

  private async launchMainAbility(): Promise<void> {
    const continueParams = this.pendingContinueParams
    this.pendingContinueParams = undefined
    if (CloudStatusBar.isRegistered()) {
      // MainAbility 已在运行：再 startAbility 会被拒（The ability is already running），
      // 跳板就 terminateSelf 不掉，空白的跳板窗口滞留前台即表现为白屏。
      // 载荷已在 captureContinueParams 里同进程交接，这里只需唤起并驱动恢复。
      await CloudStatusBar.showAbility()
      if (continueParams) {
        ContinuationCenter.notifyRestore()
      }
    } else {
      await CloudStatusBar.register(this.context)
      const options: StartOptions = {
        processMode: contextConstant.ProcessMode.ATTACH_TO_STATUS_BAR_ITEM,
        startupVisibility: contextConstant.StartupVisibility.STARTUP_SHOW
      }
      const target: Want = {
        bundleName: this.context.applicationInfo.name,
        abilityName: 'MainAbility',
        moduleName: this.context.abilityInfo.moduleName
      }
      if (continueParams) {
        target.parameters = continueParams
        AppLogger.info(TAG, 'forward continuation payload to MainAbility')
      }
      await this.context.startAbility(target, options)
    }
    this.targetStarted = true
    this.terminateLauncher()
  }

  private terminateAfterTargetStarted(): void {
    if (!this.targetStarted || !this.launcherBackgrounded || this.terminating) {
      return
    }
    this.terminateLauncher()
  }

  private terminateLauncher(): void {
    if (this.terminating) {
      return
    }
    this.terminating = true
    this.context.terminateSelf().catch((err: Error) => {
      this.terminating = false
      AppLogger.error(TAG, `terminate launcher failed: ${err.message}`)
    })
  }
}
