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
import { CloudStatusBar } from '../utils/CloudStatusBar';
import { StorageMigration } from '../utils/StorageMigration';
import { ContinuationCenter } from '../utils/ContinuationCenter';
import { VERSION_NAME } from 'BuildProfile';

export default class MainAbility extends UIAbility {
  private windowStage: window.WindowStage | undefined = undefined
  private readonly windowStageCloseListener = (): boolean => {
    if (deviceInfo.deviceType !== '2in1') {
      return false
    }
    this.context.hideAbility().catch((err: Error) => {
      AppLogger.error('MainAbility', `hide ability on window close failed: ${err.message}`)
    })
    return true
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 冷启动接续：先把载荷收下，Index 就绪后消费。
    // 判定只认载荷不看 launchReason —— 2in1 经跳板转发过来时它已不是 CONTINUATION
    ContinuationCenter.acceptPayload(want)
    // 接续图标默认可见，进视频页才放开，其余页面不提供接续入口
    ContinuationCenter.setMissionContinueState(this.context, false)
    if (deviceInfo.deviceType === '2in1') {
      CloudStatusBar.bindContext(this.context)
    }
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // 热启动接续：Index 已存在，收下载荷后要主动驱动恢复。
  // 载荷被拒时也要通知——中枢可能挂了一条"版本不兼容"待告知
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ContinuationCenter.acceptPayload(want)
    ContinuationCenter.notifyRestore()
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    // 无可接续内容（不在视频页）：先判掉，免得给用户报无关的版本问题
    if (!ContinuationCenter.hasVideoState()) {
      return AbilityConstant.OnContinueResult.REJECT
    }
    // 对端版本读不懂当前载荷时明确报版本不匹配，而不是让它接到半截数据
    if (!ContinuationCenter.isTargetVersionCompatible(wantParam)) {
      return AbilityConstant.OnContinueResult.MISMATCH
    }
    if (!ContinuationCenter.writeTo(wantParam)) {
      return AbilityConstant.OnContinueResult.REJECT
    }
    return AbilityConstant.OnContinueResult.AGREE
  }

  onDestroy(): void {
    CloudStatusBar.dispose()
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
      this.windowStage = windowStage
      this.registerTwoInOneCloseHandler(windowStage)
    } catch (err) {
      hilog.error(0x0000, 'testTag', 'getMainWindowSync failed. Cause: %{public}s', JSON.stringify(err) ?? '');
    }

    // 首帧前只做必须项：主题（避免暗色模式闪白）与沉浸式系统栏（不 await，IPC 与首帧并行）
    StorageMigration.migrate(this.context)
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
      AppLogger.info('MainAbility', `app start, version=${VERSION_NAME}`)
      if (deviceInfo.deviceType === '2in1') {
        CloudStatusBar.register(this.context).catch((err: Error) => {
          AppLogger.error('MainAbility', `register status bar failed: ${err.message}`)
        })
      }
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

  /**
   * 接续启动时系统只回调本函数，不走 onWindowStageCreate，
   * loadContent 在那边，不接管就是白屏。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageRestore');
    this.onWindowStageCreate(windowStage).catch((err: Error) => {
      hilog.error(0x0000, 'testTag', 'onWindowStageRestore failed. Cause: %{public}s', err.message);
    })
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
    if (this.windowStage && deviceInfo.deviceType === '2in1') {
      try {
        this.windowStage.off('windowStageClose', this.windowStageCloseListener)
      } catch (err) {
        AppLogger.warn('MainAbility', `unregister windowStageClose failed: ${(err as Error)?.message ?? err}`)
      }
    }
    this.windowStage = undefined
    AppLockUtil.setMainWindow(undefined)
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  private registerTwoInOneCloseHandler(windowStage: window.WindowStage): void {
    if (deviceInfo.deviceType !== '2in1') {
      return
    }
    try {
      windowStage.on('windowStageClose', this.windowStageCloseListener)
    } catch (err) {
      hilog.warn(0x0000, 'testTag', 'Register windowStageClose failed. Cause: %{public}s',
        (err as Error)?.message ?? '')
    }
  }

  onForeground(): void {
    // Ability has brought to foreground
    AppLockUtil.syncLockPresentation();
    const tick = AppStorage.get<number>(Constant.APP_FOREGROUND_TICK) ?? 0;
    AppStorage.setOrCreate(Constant.APP_FOREGROUND_TICK, tick + 1);
    AppLogger.info('MainAbility', `foreground, tick=${tick + 1}`);
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    AppLockUtil.resetSession();
    AppLogger.info('MainAbility', 'background');
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
      AppLogger.info('MainAbility', `device ${parts.join(', ')}`);
    } catch (err) {
      AppLogger.warn('MainAbility', `boot snapshot failed: ${(err as Error)?.message ?? err}`);
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
