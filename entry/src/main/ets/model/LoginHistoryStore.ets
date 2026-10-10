import Constant from './Constant';
import UserPreferences from './UserPreferences';
import UserDatabase from './UserDatabase';
import { DbUserInfo } from './net/ApiTypes';
import { LoginHistoryEntry, LoginHistoryRules } from '../utils/LoginHistoryRules';
import AppLogger from '../utils/AppLogger';

const TAG: string = 'LoginHistory';

/**
 * 登录页网址 / 用户名历史候选的存取。
 *
 * 和「已保存账号」（UserDatabase）分开存：那边存的是凭据，删账号记录、删本机凭证都会清掉；
 * 这里只记网址和用户名，退出登录、删凭据后仍能在登录页候选，用户可在候选里单独删。
 * 条数上限 10，整表以 JSON 数组存在 Preferences 单个 key 下，规则见 LoginHistoryRules。
 */
export class LoginHistoryStore {
  static list(): LoginHistoryEntry[] {
    const raw = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.LOGIN_HISTORY_KEY, '') as string
    if (raw && raw.length > 0) {
      return LoginHistoryRules.parse(raw)
    }
    return LoginHistoryStore.seedFromAccounts()
  }

  static recordSite(url: string): void {
    LoginHistoryStore.write(LoginHistoryRules.recordSite(LoginHistoryStore.list(), url))
  }

  static recordLogin(url: string, username: string): void {
    LoginHistoryStore.write(LoginHistoryStore.recordAccount(LoginHistoryStore.list(), url, username))
  }

  static removeSite(url: string): void {
    LoginHistoryStore.write(LoginHistoryRules.removeSite(LoginHistoryStore.list(), url))
  }

  static removeUsername(url: string, username: string): void {
    LoginHistoryStore.write(LoginHistoryRules.removeUsername(LoginHistoryStore.list(), url, username))
  }

  /**
   * 首次读取（key 还不存在）时从已保存账号导入一次，老用户升级后立刻有候选。
   * 写过一次后哪怕删成空表也是 "[]"，不会再导入。数据库没就绪时不落盘，下次再试。
   */
  private static seedFromAccounts(): LoginHistoryEntry[] {
    if (!UserDatabase.rdbStore) {
      return []
    }
    // listUserInfo 按新到旧排；倒着逐条记录，最近登录的就落在最前
    const accounts = UserDatabase.listUserInfo()
    let list: LoginHistoryEntry[] = []
    for (let i = accounts.length - 1; i >= 0; i--) {
      const account: DbUserInfo = accounts[i]
      list = LoginHistoryStore.recordAccount(list, account.url, account.username)
    }
    AppLogger.info(TAG, `seed from saved accounts: ${list.length} sites`)
    LoginHistoryStore.write(list)
    return list
  }

  private static recordAccount(list: LoginHistoryEntry[], url: string, username: string): LoginHistoryEntry[] {
    const name = username === Constant.SCAN_LOGIN_FALLBACK_USERNAME ? '' : username
    return LoginHistoryRules.recordLogin(list, url, name)
  }

  private static write(list: LoginHistoryEntry[]): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.LOGIN_HISTORY_KEY, JSON.stringify(list))
  }
}
