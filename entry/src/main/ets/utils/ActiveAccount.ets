import Constant from '../model/Constant';
import UserPreferences from '../model/UserPreferences';

/**
 * 当前账号的唯一写入口。
 *
 * 账号信息落在 Preferences 里，只有需要它的代码主动去读；首页四个 Tab 是常驻组件，
 * 切换账号时不会重建，于是继续渲染上一个账号的数据（文件列表要手动下拉才刷新）。
 * 这里在写 Preferences 的同时把"账号作用域"发布到 AppStorage，常驻页 @Watch 它即可
 * 在账号变化的那一刻丢弃旧数据重新拉取。
 */
export class ActiveAccount {
  /** 站点 + 用户名才能唯一标识一个账号：同名用户可能分属不同站点 */
  static scopeOf(username: string, url: string): string {
    return username.length === 0 ? '' : `${url}|${username}`;
  }

  static current(): string {
    const username = (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string) ?? '';
    const url =
      (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string) ?? '';
    return ActiveAccount.scopeOf(username, url);
  }

  /** 登录成功 / 切换账号后记录当前账号并广播 */
  static apply(username: string, url: string): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, username);
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, url);
    ActiveAccount.publish(ActiveAccount.scopeOf(username, url));
  }

  /** 退出登录 / 删除当前凭证 */
  static clear(): void {
    UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY);
    UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY);
    ActiveAccount.publish('');
  }

  /**
   * 冷启动恢复会话时同步一次，让 AppStorage 与 Preferences 一致。
   * 否则首页建好后第一次 apply 会把"空 → 当前账号"当成一次切换，白刷一遍。
   */
  static publishCurrent(): void {
    ActiveAccount.publish(ActiveAccount.current());
  }

  private static publish(scope: string): void {
    AppStorage.setOrCreate(Constant.ACTIVE_ACCOUNT_SCOPE, scope);
  }
}
