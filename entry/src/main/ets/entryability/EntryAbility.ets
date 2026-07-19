import { AbilityConstant, contextConstant, StartOptions, Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import AppLogger from '../utils/AppLogger';
import { CloudStatusBar } from '../utils/CloudStatusBar';
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

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (!this.isTwoInOneLauncher) {
      super.onCreate(want, launchParam)
      return
    }
    AppLogger.init(this.context)
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
    if (CloudStatusBar.isRegistered()) {
      await CloudStatusBar.showAbility()
    } else {
      await CloudStatusBar.register(this.context)
      const options: StartOptions = {
        processMode: contextConstant.ProcessMode.ATTACH_TO_STATUS_BAR_ITEM,
        startupVisibility: contextConstant.StartupVisibility.STARTUP_SHOW
      }
      await this.context.startAbility({
        bundleName: this.context.applicationInfo.name,
        abilityName: 'MainAbility',
        moduleName: this.context.abilityInfo.moduleName
      }, options)
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
