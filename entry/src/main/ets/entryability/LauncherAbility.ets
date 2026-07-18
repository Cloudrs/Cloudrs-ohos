import { AbilityConstant, contextConstant, StartOptions, UIAbility, Want } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import AppLogger from '../utils/AppLogger'
import { CloudStatusBar } from '../utils/CloudStatusBar'

const TAG: string = 'LauncherAbility'

export default class LauncherAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    AppLogger.init(this.context)
    try {
      if (deviceInfo.deviceType === '2in1') {
        await this.launchTwoInOneAbility()
      } else {
        await this.context.startAbility({
          bundleName: this.context.applicationInfo.name,
          abilityName: 'EntryAbility',
          moduleName: 'entry'
        })
      }
    } catch (err) {
      AppLogger.error(TAG, `launch EntryAbility failed: ${(err as Error)?.message ?? err}`)
    } finally {
      await this.context.terminateSelf()
    }
  }

  private async launchTwoInOneAbility(): Promise<void> {
    if (CloudStatusBar.isRegistered()) {
      await CloudStatusBar.showAbility()
      return
    }

    await CloudStatusBar.register(this.context)
    const options: StartOptions = {
      processMode: contextConstant.ProcessMode.ATTACH_TO_STATUS_BAR_ITEM,
      startupVisibility: contextConstant.StartupVisibility.STARTUP_SHOW
    }
    await this.context.startAbility({
      bundleName: this.context.applicationInfo.name,
      abilityName: 'EntryAbility',
      moduleName: 'entry'
    }, options)
  }
}
