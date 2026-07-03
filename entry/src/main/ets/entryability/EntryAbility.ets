import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import Constant from '../model/Constant';
import UserDatabase from '../model/UserDatabase';
import TransferDatabase from '../model/TransferDatabase';
import UserPreferences from '../model/UserPreferences';
import { AvatarUtil } from '../utils/AvatarUtil';
import { AppLockUtil } from '../utils/AppLockUtil';
import { AppBoot } from '../utils/AppBoot';
import AppLogger from '../utils/AppLogger';
import { VERSION_NAME } from 'BuildProfile';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    const t0 = Date.now()
    let tPrev = t0
    const perfMark = (label: string): void => {
      const now = Date.now()
      hilog.info(0x0000, 'bootPerf', '%{public}s +%{public}d ms (total %{public}d ms)', label, now - tPrev, now - t0)
      tPrev = now
    }
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    let windowClass: window.Window | undefined = undefined
    try {
      windowClass = windowStage.getMainWindowSync()
    } catch (err) {
      hilog.error(0x0000, 'testTag', 'getMainWindowSync failed. Cause: %{public}s', JSON.stringify(err) ?? '');
    }

    // 首帧前只做必须项：主题（避免暗色模式闪白）与沉浸式系统栏（不 await，IPC 与首帧并行）
    UserPreferences.init(this.context, Constant.USER_PREFERENCES)
    const themeMode = this.applySavedThemeMode()
    if (windowClass) {
      this.applyImmersiveSystemBars(windowClass, themeMode)
    }
    AppStorage.setOrCreate(Constant.APP_VERSION, VERSION_NAME)
    perfMark('preLoadContent')

    // 尽早 loadContent 触发首帧，其余初始化移到其后；依赖方通过 AppBoot.whenReady() 等待
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
    });
    perfMark('loadContent dispatched')

    try {
      this.publishWindowInsets(windowClass)
      AppLockUtil.setMainWindow(windowClass)
      AppLockUtil.resetSession()
      AvatarUtil.init(this.context)
      AppLogger.init(this.context)
      AppLogger.info('EntryAbility', `app start, version=${VERSION_NAME}`)
      this.logBootSnapshot(windowClass)
      perfMark('sync init')
      await UserDatabase.init(this.context)
      perfMark('UserDatabase.init')
      await TransferDatabase.init(this.context)
      perfMark('TransferDatabase.init')
      this.prepareActiveAvatarCache()
    } finally {
      AppBoot.markReady()
      perfMark('bootReady')
    }
  }

  private publishWindowInsets(windowClass: window.Window | undefined): void {
    try {
      if (!windowClass) {
        throw new Error('main window unavailable')
      }
      const uiContext = windowClass.getUIContext()
      const bottomRectHeight = windowClass
        .getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
        .bottomRect.height
      AppStorage.setOrCreate(Constant.NAV_BOTTOM_RECT_HEIGHT, uiContext.px2vp(bottomRectHeight))
      const topRectHeight = windowClass
        .getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
        .topRect.height
      AppStorage.setOrCreate(Constant.SYSTEM_TOP_RECT_HEIGHT, uiContext.px2vp(topRectHeight))
    } catch (err) {
      // 早期窗口可能未就绪（1300002）；Index.publishWindowSize 会兜底刷新
      hilog.error(0x0000, 'testTag', 'Failed to initialize window layout. Cause: %{public}s', JSON.stringify(err) ?? '');
      AppStorage.setOrCreate(Constant.NAV_BOTTOM_RECT_HEIGHT, 0)
      AppStorage.setOrCreate(Constant.SYSTEM_TOP_RECT_HEIGHT, 0)
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    AppLockUtil.setMainWindow(undefined)
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    AppLockUtil.syncLockPresentation();
    const tick = AppStorage.get<number>(Constant.APP_FOREGROUND_TICK) ?? 0;
    AppStorage.setOrCreate(Constant.APP_FOREGROUND_TICK, tick + 1);
    AppLogger.info('EntryAbility', `foreground, tick=${tick + 1}`);
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    AppLockUtil.resetSession();
    AppLogger.info('EntryAbility', 'background');
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }

  private logBootSnapshot(windowClass: window.Window | undefined): void {
    try {
      const parts: string[] = [];
      parts.push(`brand=${deviceInfo.brand}`);
      parts.push(`model=${deviceInfo.productModel}`);
      parts.push(`osFullName=${deviceInfo.osFullName}`);
      parts.push(`sdkApi=${deviceInfo.sdkApiVersion}`);
      parts.push(`deviceType=${deviceInfo.deviceType}`);
      if (windowClass) {
        try {
          const props = windowClass.getWindowProperties();
          parts.push(`window=${props.windowRect.width}x${props.windowRect.height}`);
        } catch (_) {
        }
      }
      AppLogger.info('EntryAbility', `device ${parts.join(', ')}`);
    } catch (err) {
      AppLogger.warn('EntryAbility', `boot snapshot failed: ${(err as Error)?.message ?? err}`);
    }
  }

  private prepareActiveAvatarCache(): void {
    const activeUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string
    if (!activeUser || activeUser.length === 0) {
      return
    }
    const activeUrl = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string
    const dbUserInfo = UserDatabase.getUserInfo(activeUser, activeUrl)
    if (!dbUserInfo) {
      return
    }
    try {
      AvatarUtil.getDbUserAvatarCacheUri(dbUserInfo)
    } catch (err) {
      hilog.warn(0x0000, 'testTag', 'Prepare active avatar cache failed. Cause: %{public}s',
        (err as Error)?.message ?? '');
    }
  }

  private async applyImmersiveSystemBars(windowClass: window.Window, themeMode: string): Promise<void> {
    const useLightIcon = themeMode === Constant.APP_THEME_DARK
    try {
      if (deviceInfo.deviceType === '2in1') {
        // 2in1 上隐藏窗口装饰条，由应用自绘控制
        try {
          windowClass.setWindowDecorVisible(false)
          windowClass.setWindowDecorHeight(64)
        } catch (err) {
          hilog.warn(0x0000, 'testTag', 'setWindowDecor failed. Cause: %{public}s',
            (err as Error)?.message ?? '')
        }
      } else {
        windowClass.setWindowLayoutFullScreen(true)
      }
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
