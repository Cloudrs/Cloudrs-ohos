import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import Constant from '../model/Constant';
import UserDatabase from '../model/UserDatabase';
import UserPreferences from '../model/UserPreferences';
import { AvatarUtil } from '../utils/AvatarUtil';
import { AppLockUtil } from '../utils/AppLockUtil';
import { VERSION_NAME } from 'BuildProfile';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    let windowClass: window.Window | undefined = undefined

    // 全屏及获取规避区域高度
    try {
      windowClass = windowStage.getMainWindowSync()
      const uiContext = windowClass.getUIContext()
      let bottomRectHeight = windowClass
        .getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
        .bottomRect.height
      AppStorage.setOrCreate(Constant.NAV_BOTTOM_RECT_HEIGHT, uiContext.px2vp(bottomRectHeight))
      let topRectHeight = windowClass
        .getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
        .topRect.height
      AppStorage.setOrCreate(Constant.SYSTEM_TOP_RECT_HEIGHT, uiContext.px2vp(topRectHeight))
      await this.applyImmersiveSystemBars(windowClass, Constant.APP_THEME_LIGHT)
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
    AvatarUtil.init(this.context)
    const themeMode = this.applySavedThemeMode()
    if (windowClass) {
      await this.applyImmersiveSystemBars(windowClass, themeMode)
    }

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
    const tick = AppStorage.get<number>(Constant.APP_FOREGROUND_TICK) ?? 0;
    AppStorage.setOrCreate(Constant.APP_FOREGROUND_TICK, tick + 1);
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    AppLockUtil.resetSession();
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }

  private async applyImmersiveSystemBars(windowClass: window.Window, themeMode: string): Promise<void> {
    const useLightIcon = themeMode === Constant.APP_THEME_DARK
    try {
      windowClass.setWindowLayoutFullScreen(true)
      await windowClass.setWindowSystemBarProperties({
        statusBarColor: Constant.SYSTEM_BAR_TRANSPARENT_COLOR,
        navigationBarColor: Constant.SYSTEM_BAR_TRANSPARENT_COLOR,
        statusBarContentColor: useLightIcon ? Constant.SYSTEM_BAR_LIGHT_CONTENT_COLOR : Constant.SYSTEM_BAR_DARK_CONTENT_COLOR,
        navigationBarContentColor: useLightIcon ? Constant.SYSTEM_BAR_LIGHT_CONTENT_COLOR : Constant.SYSTEM_BAR_DARK_CONTENT_COLOR,
        isStatusBarLightIcon: useLightIcon,
        isNavigationBarLightIcon: useLightIcon,
        enableStatusBarAnimation: Constant.SYSTEM_BAR_ANIMATION_ENABLED,
        enableNavigationBarAnimation: Constant.SYSTEM_BAR_ANIMATION_ENABLED
      })
    } catch (err) {
      hilog.error(0x0000, 'testTag', 'Failed to apply immersive system bars. Cause: %{public}s',
        JSON.stringify(err) ?? '');
    }
  }

  private getSavedThemeMode(): string {
    return UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.APP_THEME_MODE,
      Constant.APP_THEME_LIGHT
    ) as string
  }

  applySavedThemeMode(): string {
    const themeMode = this.getSavedThemeMode()
    try {
      this.context.setColorMode(themeMode === Constant.APP_THEME_DARK
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
    } catch (err) {
      hilog.error(0x0000, 'testTag', 'Failed to apply theme mode. Cause: %{public}s', JSON.stringify(err) ?? '');
    }
    return themeMode
  }
}
