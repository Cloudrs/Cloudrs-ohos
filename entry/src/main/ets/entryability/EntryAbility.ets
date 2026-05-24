import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DialogHelper } from '@pura/harmony-dialog'
import Constant from '../model/Constant';
import UserDatabase from '../model/UserDatabase';
import { HMRouterMgr } from '@hadss/hmrouter';
import UserPreferences from '../model/UserPreferences';
import { VERSION_NAME } from 'BuildProfile';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    DialogHelper.setDefaultConfig((config) => {
      config.uiAbilityContext = this.context
    })

    // HMRouter初始化
    HMRouterMgr.init({context: this.context})
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // 全屏及获取规避区域高度
    let windowClass = windowStage.getMainWindowSync()
    windowClass.setWindowLayoutFullScreen(true)
    let bottomRectHeight = windowClass
      .getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      .bottomRect.height
    AppStorage.setOrCreate(Constant.NAV_BOTTOM_RECT_HEIGHT, px2vp(bottomRectHeight))
    let topRectHeight = windowClass
      .getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      .topRect.height
    AppStorage.setOrCreate(Constant.SYSTEM_TOP_RECT_HEIGHT, px2vp(topRectHeight))
    AppStorage.setOrCreate(Constant.APP_VERSION, VERSION_NAME)

    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 初始化用户加密首选项
    UserPreferences.init(this.context, Constant.USER_PREFERENCES)

    // 初始化用户信息数据库
    await UserDatabase.init(this.context)

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
