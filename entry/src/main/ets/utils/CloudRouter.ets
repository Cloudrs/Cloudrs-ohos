import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import Constant from '../model/Constant';
import UserDatabase from '../model/UserDatabase';
import UserPreferences from '../model/UserPreferences';
import { DbUserInfo } from '../model/net/ApiTypes';
import { LoginParam } from '../model/net/LoginParam';
import { CloudApi } from '../model/net/CloudApi';
import { CloudThemeToken } from '../model/CloudTheme';
import { AppLockUtil } from './AppLockUtil';
import { showToast, showToastTips, ToastType } from './ToastUtil';
import AppLogger from './AppLogger';

const TAG: string = 'CloudRouter'

export class CloudRouter {
  private static pathStack?: NavPathStack;
  private static homeUpdater?: (pageUrl: string, param: Object) => void;
  private static overlayUpdater?: (pageUrl: string, param: Object) => void;
  private static overlayPage: string = '';
  private static homeBackHandler?: () => boolean;
  private static homeBackEnabled: boolean = true;
  private static backTimeStamp: number = 0;

  static init(
    pathStack: NavPathStack,
    homeUpdater?: (pageUrl: string, param: Object) => void,
    overlayUpdater?: (pageUrl: string, param: Object) => void
  ): void {
    CloudRouter.pathStack = pathStack;
    CloudRouter.homeUpdater = homeUpdater;
    CloudRouter.overlayUpdater = overlayUpdater;
  }

  static showStartPage(): void {
    let hasSession = false;
    try {
      hasSession = CloudRouter.restoreCurrentSession(false);
    } catch (err) {
      AppLogger.error(TAG, `restore session failed: ${(err as Error)?.message ?? err}`);
    }
    if (hasSession) {
      CloudRouter.replaceRoot(Constant.HOME_PAGE);
    } else {
      CloudRouter.replaceRoot(Constant.LOGIN_PAGE, new LoginParam(false, Constant.HOME_PAGE));
    }
  }

  static push(pageUrl: string, param?: Object): void {
    if (!CloudRouter.canOpen(pageUrl)) {
      return;
    }
    if (CloudRouter.isRootPage(pageUrl)) {
      CloudRouter.replaceRoot(pageUrl, param);
      return;
    }
    const routeParam = CloudRouter.getRouteParam(param);
    if (CloudRouter.overlayUpdater) {
      CloudRouter.overlayPage = pageUrl;
      CloudRouter.overlayUpdater(pageUrl, routeParam);
      return;
    }
    CloudRouter.pathStack?.pushPath(new NavPathInfo(pageUrl, routeParam));
  }

  static replaceRoot(pageUrl: string, param?: Object): void {
    CloudRouter.clearOverlay();
    const routeParam = CloudRouter.getRouteParam(param);
    if (CloudRouter.homeUpdater) {
      CloudRouter.homeUpdater(pageUrl, routeParam);
      return;
    }
    CloudRouter.pathStack?.clear(false);
    CloudRouter.pathStack?.pushPath(new NavPathInfo(pageUrl, routeParam, undefined, true), false);
  }

  static goAfterLogin(nextPage?: string | null): void {
    const targetPage = nextPage && nextPage.length > CloudThemeToken.zero && nextPage !== Constant.LOGIN_PAGE
      ? nextPage
      : Constant.HOME_PAGE;
    AppLockUtil.markSessionUnlocked();
    CloudRouter.replaceRoot(Constant.HOME_PAGE);
    if (targetPage !== Constant.HOME_PAGE) {
      CloudRouter.push(targetPage);
    }
  }

  static resetToLogin(nextPage: string = Constant.HOME_PAGE): void {
    AppLogger.info(TAG, `reset to login, nextPage=${nextPage}`);
    CloudRouter.replaceRoot(Constant.LOGIN_PAGE, new LoginParam(false, nextPage));
  }

  static switchToUser(username: string, url?: string, showExpiredTip: boolean = true): boolean {
    const dbUserInfo: DbUserInfo | null = UserDatabase.getUserInfo(username, url);
    if (!dbUserInfo) {
      AppLogger.warn(TAG, `switch user not found: ${username}`);
      showToastTips('未找到该账号的登录信息', ToastType.Warn);
      return false;
    }

    if (!CloudRouter.restoreUserSession(dbUserInfo, showExpiredTip)) {
      AppLogger.warn(TAG, `switch user session restore failed: ${username}`);
      return false;
    }

    AppLogger.info(TAG, `switch user ok: ${username}`);
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, dbUserInfo.username);
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, dbUserInfo.url);
    return true;
  }

  static pop(): void {
    if (CloudRouter.overlayPage.length > CloudThemeToken.zero) {
      CloudRouter.clearOverlay();
      return;
    }
    CloudRouter.pathStack?.pop();
  }

  static hasOverlay(): boolean {
    return CloudRouter.overlayPage.length > CloudThemeToken.zero;
  }

  static setHomeBackHandler(handler?: () => boolean): void {
    CloudRouter.homeBackHandler = handler;
  }

  static setHomeBackEnabled(enabled: boolean): void {
    CloudRouter.homeBackEnabled = enabled;
  }

  static handleHomeBack(uiContext: UIContext): boolean {
    if (CloudRouter.homeBackEnabled && CloudRouter.homeBackHandler?.()) {
      return true;
    }
    return CloudRouter.handleExitBack(uiContext);
  }

  static handleExitBack(uiContext: UIContext): boolean {
    const now = Date.now();
    if (now - CloudRouter.backTimeStamp < Constant.EXIT_BACK_PRESS_INTERVAL_MS) {
      const abilityContext = uiContext.getHostContext() as common.UIAbilityContext | undefined;
      if (!abilityContext) {
        showToast('退出失败');
        return true;
      }
      abilityContext.terminateSelf().catch((err: Error) => {
        AppLogger.error(TAG, `terminateSelf failed: ${err.message}`);
        showToast('退出失败');
      });
    } else {
      CloudRouter.backTimeStamp = now;
      showToast('再滑一次退出');
    }
    return true;
  }

  private static canOpen(pageUrl: string): boolean {
    if (pageUrl === Constant.LOGIN_PAGE) {
      return true;
    }
    if (CloudRouter.restoreCurrentSession(true)) {
      return true;
    }
    CloudRouter.resetToLogin(pageUrl);
    return false;
  }

  private static getRouteParam(param?: Object): Object {
    return param ?? new EmptyRouteParam();
  }

  private static isRootPage(pageUrl: string): boolean {
    return pageUrl === Constant.HOME_PAGE || pageUrl === Constant.LOGIN_PAGE;
  }

  private static clearOverlay(): void {
    if (CloudRouter.overlayPage.length <= CloudThemeToken.zero) {
      return;
    }
    CloudRouter.overlayPage = '';
    CloudRouter.overlayUpdater?.('', new EmptyRouteParam());
  }

  private static restoreCurrentSession(showExpiredTip: boolean): boolean {
    const currentUser = (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY) as string) ?? '';
    if (currentUser.length <= CloudThemeToken.zero) {
      return false;
    }
    const currentUrl = (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string) ?? '';

    const dbUserInfo: DbUserInfo | null = UserDatabase.getUserInfo(currentUser, currentUrl);
    if (!dbUserInfo) {
      return false;
    }

    return CloudRouter.restoreUserSession(dbUserInfo, showExpiredTip);
  }

  private static restoreUserSession(dbUserInfo: DbUserInfo, showExpiredTip: boolean): boolean {
    const expiresDate = new Date(dbUserInfo.expires);
    if (Date.now() >= expiresDate.getTime()) {
      if (showExpiredTip) {
        showToastTips('登录信息过期，重新登录!', ToastType.Warn);
      }
      return false;
    }

    const cookie = dbUserInfo.cookie;
    const isV3 = !cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX);
    const token = isV3 ? cookie : cookie.slice(Constant.CLOUD_V4_COOKIE_PREFIX.length);
    const refreshToken = dbUserInfo.refresh_token ?? '';
    CloudApi.restoreSession(dbUserInfo.url, token, refreshToken, isV3);
    return true;
  }
}

class EmptyRouteParam {
}
