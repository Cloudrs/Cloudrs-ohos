import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import Constant from '../model/Constant';
import UserDatabase from '../model/UserDatabase';
import { HMRouterMgr } from '@hadss/hmrouter';
import UserPreferences from '../model/UserPreferences';
import { VERSION_NAME } from 'BuildProfile';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');

    // HMRouter初始化
    HMRouterMgr.init({context: this.context})
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // 全屏及获取规避区域高度
    try {
      let windowClass = windowStage.getMainWindowSync()
      const uiContext = windowClass.getUIContext()
      windowClass.setWindowLayoutFullScreen(true)
      let bottomRectHeight = windowClass
        .getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
        .bottomRect.height
      AppStorage.setOrCreate(Constant.NAV_BOTTOM_RECT_HEIGHT, uiContext.px2vp(bottomRectHeight))
      let topRectHeight = windowClass
        .getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
        .topRect.height
      AppStorage.setOrCreate(Constant.SYSTEM_TOP_RECT_HEIGHT, uiContext.px2vp(topRectHeight))
    } catch (err) {
      hilog.error(0x0000, 'testTag', 'Failed to initialize window layout. Cause: %{public}s', JSON.stringify(err) ?? '');
      AppStorage.setOrCreate(Constant.NAV_BOTTOM_RECT_HEIGHT, 0)
      AppStorage.setOrCreate(Constant.SYSTEM_TOP_RECT_HEIGHT, 0)
    }
    AppStorage.setOrCreate(Constant.APP_VERSION, VERSION_NAME)

    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 初始化用户加密首选项
    UserPreferences.init(this.context, Constant.USER_PREFERENCES)
    this.applySavedThemeMode()

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

  applySavedThemeMode(): void {
    const themeMode = UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.APP_THEME_MODE,
      Constant.APP_THEME_LIGHT
    ) as string
    try {
      this.context.setColorMode(themeMode === Constant.APP_THEME_DARK
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
    } catch (err) {
      hilog.error(0x0000, 'testTag', 'Failed to apply theme mode. Cause: %{public}s', JSON.stringify(err) ?? '');
    }
  }
}
