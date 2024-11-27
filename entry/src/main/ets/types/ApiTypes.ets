/**
 * 站点通用结构，T为具体
 */
export interface SiteCommon<T> {
  code: number;
  data: T;
  msg: string;
}

/**
 * 登录请求信息
 */
export interface LoginData {
  username: string;
  password: string;
  captchaCode: string;
}

/**
 * 用户组信息
 */
export interface GroupInfo {
  id: string;
  name: string;
  allowShare: boolean;
  allowRemoteDownload: boolean;
  allowArchiveDownload: boolean;
  shareDownload: boolean;
  compress: boolean;
  webdav: boolean;
  sourceBatch: number;
  advanceDelete: boolean;
  allowWebDAVProxy: boolean;
}

/**
 * 用户登录信息
 */
export interface UserInfo {
  id: string;
  user_name: string;
  nick_name: string;
  status: number;
  avatar: string;
  created_at: string;
  preferred_theme: string;
  anonymous: boolean;
  group: GroupInfo;
}

/**
 * 站点配置信息
 */
export interface SiteConfig {
  title: string;
  loginCaptcha: string;
  regCaptcha: false;
  forgetCaptcha: false;
  emailActive: false;
  themes: string;
  defaultTheme: string;
  home_view_method: string;
  share_view_method: string;
  authn: false;
  user: UserInfo;
  captcha_ReCaptchaKey: string;
  captcha_type: string;
  tcaptcha_captcha_app_id: string;
  registerEnabled: false;
  app_promotion: false;
  wopi_exts: string;
}

/**
 * 用户存储信息
 */
export interface UserStorage {
  used: number;
  free: number;
  total: number;
}

/**
 * 保存数据数据结构
 */
export interface DbUserInfo {
  url: string,
  username: string;
  password: string;
  cookie: string;
  expires: string;
  userinfo: UserInfo;
}