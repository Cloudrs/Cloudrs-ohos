import { takeRefreshedSession } from 'libcloudreve.so';
import Constant from '../model/Constant';
import UserDatabase from '../model/UserDatabase';
import UserPreferences from '../model/UserPreferences';
import { DbUserInfo } from '../model/net/ApiTypes';
import AppLogger from './AppLogger';

const TAG: string = 'SessionSync';

const REFRESHED_ACCESS_INDEX: number = 0;
const REFRESHED_REFRESH_INDEX: number = 1;
const REFRESHED_EXPIRES_INDEX: number = 2;

/**
 * native 静默续期结果的回收站。
 *
 * v4 的 access token 只活一小时，native 侧遇到 401 会自己拿 refresh token 换一套新的
 * （见 api.rs 的 run_api_with_v4_refresh）。但那套新 token 原先只更新进程内的 client，
 * 应用一重启就退回 ETS 存的旧值——库里的 cookie 因此长期是个早已失效的 access token。
 * 这里在每次 API 调用之后把 native 攒下的新会话取走并落库，让两边不再漂移。
 */
export class SessionSync {
  /**
   * 服务端给的到期时间优先；拿不到或格式不对时，退回按天数估一个。
   * 登录与静默续期共用这一份，免得两处各估各的。
   */
  static resolveExpires(serverExpires: string): string {
    let expiresDate = serverExpires.length > 0 ? new Date(serverExpires) : new Date();
    if (serverExpires.length === 0 || Number.isNaN(expiresDate.getTime())) {
      expiresDate = new Date();
      expiresDate.setDate(expiresDate.getDate() + Constant.CLOUD_COOKIE_EXPIRE_DAYS);
    }
    return expiresDate.toUTCString();
  }

  /**
   * 取走 native 上一次静默续期的产物并落库；没有就立刻返回。
   * 每次 API 调用后都会走一遍，所以绝大多数时候只是一次空取。
   */
  static pull(): void {
    let refreshed: string[] = [];
    try {
      refreshed = takeRefreshedSession();
    } catch (err) {
      AppLogger.warn(TAG, `take refreshed session failed: ${(err as Error)?.message ?? err}`);
      return;
    }
    if (refreshed.length === 0) {
      return;
    }

    const accessToken: string = refreshed[REFRESHED_ACCESS_INDEX] ?? '';
    const refreshToken: string = refreshed[REFRESHED_REFRESH_INDEX] ?? '';
    if (accessToken.length === 0) {
      return;
    }
    // 静默续期只发生在 v4，cookie 一律带 v4 前缀，与 restoreSession 的读法对齐
    const cookie = `${Constant.CLOUD_V4_COOKIE_PREFIX}${accessToken}`;
    const expires = SessionSync.resolveExpires(refreshed[REFRESHED_EXPIRES_INDEX] ?? '');

    AppStorage.setOrCreate(Constant.CLOUD_COOKIE, cookie);
    AppStorage.setOrCreate(Constant.CLOUD_COOKIE_EXPIRES, expires);
    AppStorage.setOrCreate(Constant.CLOUD_REFRESH_TOKEN, refreshToken);

    SessionSync.persist(cookie, refreshToken, expires);
  }

  private static persist(cookie: string, refreshToken: string, expires: string): void {
    const username =
      (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string) ?? '';
    const url =
      (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string) ?? '';
    if (username.length === 0) {
      return;
    }

    const dbUserInfo: DbUserInfo | null = UserDatabase.getUserInfo(username, url);
    if (!dbUserInfo) {
      return;
    }
    if (dbUserInfo.cookie === cookie && dbUserInfo.refresh_token === refreshToken &&
      dbUserInfo.expires === expires) {
      return;
    }

    dbUserInfo.cookie = cookie;
    dbUserInfo.refresh_token = refreshToken;
    dbUserInfo.expires = expires;
    UserDatabase.insertUserInfo(dbUserInfo);
    AppLogger.info(TAG, `refreshed session persisted for ${username}, expires=${expires}`);
  }
}
