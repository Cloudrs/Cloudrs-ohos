import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import Constant from '../model/Constant';
import UserPreferences from '../model/UserPreferences';
import { SystemAuthResult, SystemAuthUtil } from './SystemAuthUtil';
import AppLogger from './AppLogger';

const TAG: string = 'AppLockUtil';

export class AppLockUtil {
  private static sessionUnlocked: boolean = false;
  private static pendingUnlock?: Promise<SystemAuthResult> = undefined;
  private static mainWindow?: window.Window = undefined;

  static isEnabled(): boolean {
    return (UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.PRIVACY_SYSTEM_AUTH_ENABLED,
      false
    ) as boolean) === true;
  }

  static setEnabled(enabled: boolean): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PRIVACY_SYSTEM_AUTH_ENABLED, enabled);
    AppLockUtil.sessionUnlocked = enabled;
    AppLockUtil.syncLockPresentation();
  }

  static setMainWindow(mainWindow?: window.Window): void {
    AppLockUtil.mainWindow = mainWindow;
    AppLockUtil.syncLockPresentation();
  }

  static markSessionUnlocked(): void {
    AppLockUtil.sessionUnlocked = true;
    AppLockUtil.syncLockPresentation();
  }

  static resetSession(): void {
    if (AppLockUtil.isEnabled()) {
      AppLockUtil.sessionUnlocked = false;
    }
    AppLockUtil.syncLockPresentation();
  }

  static syncLockPresentation(): void {
    const locked = AppLockUtil.isEnabled() && !AppLockUtil.sessionUnlocked;
    AppStorage.setOrCreate(Constant.APP_LOCKED, locked);
    AppLockUtil.syncWindowPrivacyMode(locked);
  }

  private static syncWindowPrivacyMode(locked: boolean): void {
    if (!AppLockUtil.mainWindow) {
      return;
    }
    AppLockUtil.mainWindow.setWindowPrivacyMode(locked)
      .catch((err: Error) => {
        AppLogger.warn(TAG, `set window privacy mode failed: ${err.message}`);
      });
  }

  static async unlockIfNeeded(context: common.UIAbilityContext): Promise<SystemAuthResult> {
    if (!AppLockUtil.isEnabled()) {
      AppLockUtil.syncLockPresentation();
      return new SystemAuthResult(true);
    }
    if (AppLockUtil.sessionUnlocked) {
      AppLockUtil.syncLockPresentation();
      return new SystemAuthResult(true);
    }
    if (AppLockUtil.pendingUnlock) {
      return AppLockUtil.pendingUnlock;
    }

    AppLockUtil.syncLockPresentation();
    AppLogger.info(TAG, 'unlock prompt');
    const unlockPromise = SystemAuthUtil.authenticate(context, '解锁 Cloudrs')
      .then((result: SystemAuthResult) => {
        if (result.success) {
          AppLockUtil.sessionUnlocked = true;
          AppLogger.info(TAG, 'unlock ok');
        } else {
          AppLogger.warn(TAG, `unlock failed: ${result.message}`);
        }
        AppLockUtil.syncLockPresentation();
        AppLockUtil.pendingUnlock = undefined;
        return result;
      })
      .catch((err: Error) => {
        AppLockUtil.pendingUnlock = undefined;
        AppLockUtil.syncLockPresentation();
        AppLogger.warn(TAG, `unlock threw: ${err.message}`);
        return new SystemAuthResult(false, err.message);
      });
    AppLockUtil.pendingUnlock = unlockPromise;
    return unlockPromise;
  }

  static authenticateForSettings(
    context: common.UIAbilityContext,
    title: string
  ): Promise<SystemAuthResult> {
    return SystemAuthUtil.authenticate(context, title)
      .then((result: SystemAuthResult) => {
        if (result.success) {
          AppLockUtil.sessionUnlocked = true;
        }
        return result;
      });
  }
}
