import { common } from '@kit.AbilityKit';
import Constant from '../model/Constant';
import UserPreferences from '../model/UserPreferences';
import { SystemAuthResult, SystemAuthUtil } from './SystemAuthUtil';

export class AppLockUtil {
  private static sessionUnlocked: boolean = false;
  private static pendingUnlock?: Promise<SystemAuthResult> = undefined;

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
  }

  static resetSession(): void {
    if (AppLockUtil.isEnabled()) {
      AppLockUtil.sessionUnlocked = false;
    }
  }

  static async unlockIfNeeded(context: common.UIAbilityContext): Promise<SystemAuthResult> {
    if (!AppLockUtil.isEnabled()) {
      return new SystemAuthResult(true);
    }
    if (AppLockUtil.sessionUnlocked) {
      return new SystemAuthResult(true);
    }
    if (AppLockUtil.pendingUnlock) {
      return AppLockUtil.pendingUnlock;
    }

    const unlockPromise = SystemAuthUtil.authenticate(context, '解锁 Cloudrs')
      .then((result: SystemAuthResult) => {
        if (result.success) {
          AppLockUtil.sessionUnlocked = true;
        }
        AppLockUtil.pendingUnlock = undefined;
        return result;
      })
      .catch((err: Error) => {
        AppLockUtil.pendingUnlock = undefined;
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
