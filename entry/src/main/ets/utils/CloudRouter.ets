import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import Constant from '../model/Constant';
import UserDatabase from '../model/UserDatabase';
import UserPreferences from '../model/UserPreferences';
import { DbUserInfo } from '../model/net/ApiTypes';
import { LoginParam } from '../model/net/LoginParam';
import { CloudApi } from '../model/net/CloudApi';
import { CloudThemeToken } from '../model/CloudTheme';
import { ActiveAccount } from './ActiveAccount';
import { AppLockUtil } from './AppLockUtil';
import { ContinuationCenter } from './ContinuationCenter';
import { showToast, showToastTips, ToastType } from './ToastUtil';
import AppLogger from './AppLogger';

const TAG: string = 'CloudRouter'

/** 账号切换结果。接续场景要按失败原因给不同提示，不能一律说"未登录" */
export enum UserSwitchResult {
  Ok,
  NotFound,
  Expired
}

export class CloudRouter {
  private static pathStack?: NavPathStack;
  private static homeUpdater?: (pageUrl: string, param: Object) => void;
  private static overlayUpdater?: (pageUrl: string, param: Object) => void;
  private static overlayPage: string = '';
  private static homeBackHandler?: () => boolean;
  private static exitGuard?: () => boolean;
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
    // 接续因对端未登录而挂起时，登录成功即续播（恢复入口由 Index 注册）
    ContinuationCenter.notifyRestore();
  }

  static resetToLogin(nextPage: string = Constant.HOME_PAGE): void {
    AppLogger.info(TAG, `reset to login, nextPage=${nextPage}`);
    CloudRouter.replaceRoot(Constant.LOGIN_PAGE, new LoginParam(false, nextPage));
  }

  static switchToUser(username: string, url?: string, showExpiredTip: boolean = true): boolean {
    const result = CloudRouter.switchToUserSilently(username, url);
    if (result === UserSwitchResult.NotFound) {
      AppLogger.warn(TAG, `switch user not found: ${username}`);
      showToastTips('未找到该账号的登录信息', ToastType.Warn);
      return false;
    }
    if (result === UserSwitchResult.Expired) {
      AppLogger.warn(TAG, `switch user session expired: ${username}`);
      if (showExpiredTip) {
        showToastTips('登录信息过期，重新登录!', ToastType.Warn);
      }
      return false;
    }
    AppLogger.info(TAG, `switch user ok: ${username}`);
    // 手动切账号也可能正好切到接续来源账号，顺势完成挂起的续播
    ContinuationCenter.notifyRestore();
    return true;
  }

  /** 本机当前是否有可用登录态（顺带恢复该会话） */
  static hasActiveSession(): boolean {
    return CloudRouter.restoreCurrentSession(false);
  }

  /** 不弹任何提示的账号切换，调用方按结果自行决定文案（接续恢复用） */
  static switchToUserSilently(username: string, url?: string): UserSwitchResult {
    const dbUserInfo: DbUserInfo | null = UserDatabase.getUserInfo(username, url);
    if (!dbUserInfo) {
      return UserSwitchResult.NotFound;
    }
    if (!CloudRouter.restoreUserSession(dbUserInfo, false)) {
      return UserSwitchResult.Expired;
    }
    ActiveAccount.apply(dbUserInfo.username, dbUserInfo.url);
    return UserSwitchResult.Ok;
  }

  static pop(): void {
    // 有未保存内容的页面在这里拦一道，覆盖返回键、返回手势和页内返回按钮三条路径
    if (CloudRouter.exitGuard?.()) {
      return;
    }
    CloudRouter.popForced();
  }

  /** 绕过拦截直接离开，供拦截方在用户确认放弃后调用 */
  static popForced(): void {
    if (CloudRouter.overlayPage.length > CloudThemeToken.zero) {
      CloudRouter.clearOverlay();
      return;
    }
    CloudRouter.pathStack?.pop();
  }

  /**
   * 设置离开拦截。返回 true 表示本次离开被拦下（通常是弹了确认框）。
   * 页面必须在 aboutToDisappear 里清掉，否则会挡住后续所有返回。
   */
  static setExitGuard(guard?: () => boolean): void {
    CloudRouter.exitGuard = guard;
  }

  /** NavDestination 的 onBackPressed 用：返回 true 表示已消费本次返回 */
  static interceptBack(): boolean {
    return CloudRouter.exitGuard?.() === true;
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

    if (!CloudRouter.restoreUserSession(dbUserInfo, showExpiredTip)) {
      return false;
    }
    // 冷启动恢复的会话不经过 apply，这里补广播一次，保证首页建好前 AppStorage 已是当前账号
    ActiveAccount.publishCurrent();
    return true;
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
