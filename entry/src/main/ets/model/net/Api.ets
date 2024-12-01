import { cloudGet, cloudPost } from "../../utils/AxiosRequest";
import { DirectoryInfo, HttpCallback, LoginData, SiteConfig, SiteURI, UserInfo, UserStorage } from "./ApiTypes";

/**
 * 网站测试
 * @param callback  回调
 */
export function cloudPing(callback?: HttpCallback<string>): void {
  return cloudGet(SiteURI.PING, callback)
}

/**
 * 获取网站配置
 * @param callback  回调
 */
export function cloudSiteConfig(callback?: HttpCallback<SiteConfig>): void {
  return cloudGet(SiteURI.PING, callback)
}

/**
 * 网站登录，目前只支持用户密码登录
 * @param username  用户名或邮箱
 * @param password  用户密码
 * @param callback  回调
 */
export function cloudLogin(username: string, password: string, callback?: HttpCallback<UserInfo>): void {
    let loginData: LoginData = {username, password, captchaCode: ''};
    return cloudPost(SiteURI.LOGIN, loginData, callback)
}

/**
 * 获取用户存储信息
 * @param callback  回调
 */
export function cloudUserStorage(callback?: HttpCallback<UserStorage>): void {
  return cloudGet(SiteURI.USER_STORAGE, callback)
}

/**
 * 获取指定路径下的文件
 * @param callback  回调
 */
export function cloudGetFiles(path: string = '/', callback?: HttpCallback<DirectoryInfo>): void {
  return cloudGet(SiteURI.LIST_DIR + path, callback)
}