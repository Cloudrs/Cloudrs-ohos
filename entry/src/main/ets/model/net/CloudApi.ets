import { cloudDelete, cloudGet, cloudGetFile, cloudPost, cloudPut } from "../../utils/AxiosRequest";
import { DirectoryInfo, HttpCallback, LoginData, ObjectDetail,SiteConfig, SiteURI, UserInfo, UserStorage } from "./ApiTypes";
import { ObjectNew, ObjectRename, ObjectSrc } from "./ObjectParam";

export class CloudApi {
  /**
   * 网站测试
   * @param callback  回调
   */
  static cloudPing(callback?: HttpCallback<string>): void {
    return cloudGet(SiteURI.PING, callback)
  }

  /**
   * 获取网站配置
   * @param callback  回调
   */
  static cloudSiteConfig(callback?: HttpCallback<SiteConfig>): void {
    return cloudGet(SiteURI.CONFIG, callback)
  }

  /**
   * 获取指定网站图标
   * @param callback  回调
   */
  static cloudGetLogo(baseUrl?: string, callback?: HttpCallback<ArrayBuffer>): void {
    return cloudGetFile(baseUrl ? baseUrl + SiteURI.LOGO : SiteURI.LOGO, callback)
  }

  /**
   * 网站登录，目前只支持用户密码登录
   * @param username  用户名或邮箱
   * @param password  用户密码
   * @param callback  回调
   */
  static cloudLogin(username: string, password: string, callback?: HttpCallback<UserInfo>): void {
    let loginData: LoginData = { username, password, captchaCode: '' };
    return cloudPost(SiteURI.LOGIN, loginData, callback)
  }

  /**
   * 获取用户存储信息
   * @param callback  回调
   */
  static cloudUserStorage(callback?: HttpCallback<UserStorage>): void {
    return cloudGet(SiteURI.USER_STORAGE, callback)
  }

  /**
   * 获取指定路径下的文件信息
   * @param callback  回调
   */
  static cloudGetFilesInfo(path: string = '/', callback?: HttpCallback<DirectoryInfo>): void {
    return cloudGet(SiteURI.DIRECTORY + path, callback)
  }

  /**
   * 获取指定id的缩略图
   * @param callback  回调
   */
  static cloudGetThumb(id: string, callback?: HttpCallback<ArrayBuffer>): void {
    return cloudGetFile(SiteURI.THUMB + '/' + id, callback)
  }

  /**
   * 获取指定id的图标
   * @param callback  回调
   */
  static cloudGetPreview(id: string, callback?: HttpCallback<ArrayBuffer>): void {
    return cloudGetFile(SiteURI.PREVIEW + '/' + id, callback)
  }

  /**
   * 获取指定id的详细信息
   * @param callback  回调
   */
  static cloudGetObjectDetail(id: string, isFolder: boolean, callback?: HttpCallback<ObjectDetail>): void {
    let uri = `/${id}?is_folder=${isFolder}&trace_root=false`
    return cloudGet(SiteURI.OBJECT_DETAIL + uri, callback)
  }

  /**
   * 新建对象
   * @param path 新建的路径名
   * @param isDir 是否为文件夹
   * @param callback  回调
   */
  static cloudNewObject(path: string, isDir: boolean, callback?: HttpCallback<null>): void {
    if (isDir) {
      return cloudPut(SiteURI.DIRECTORY, new ObjectNew(path), callback)
    } else {
      return cloudPost(SiteURI.NEW_FILE, new ObjectNew(path), callback)
    }
  }

  /**
   * 删除指定路径下对象，可一次删除多个文件及文件夹
   * @param src 需要删除的对象
   * @param callback  回调
   */
  static cloudDeleteObjects(src: ObjectSrc, callback?: HttpCallback<null>): void {
    return cloudDelete(SiteURI.OBJECT, src, callback)
  }

  /**
   * 删除指定路径下对象
   * @param id 需要删除的id
   * @param isDir 是否为文件夹
   * @param callback  回调
   */
  static cloudDeleteObject(id: string, isDir: boolean = false, callback?: HttpCallback<null>): void {
    let src = isDir ? new ObjectSrc(undefined, [id]) : new ObjectSrc([id], undefined)
    return cloudDelete(SiteURI.OBJECT, src, callback)
  }

  /**
   * 重命名指定ID对象
   * @param id 需要重命名的id
   * @param newName 需要重命名的名称
   * @param isDir 是否为文件夹
   * @param callback  回调
   */
  static cloudRenameObject(id: string, newName: string, isDir: boolean = false, callback?: HttpCallback<null>): void {
    let src = isDir ? new ObjectSrc(undefined, [id]) : new ObjectSrc([id], undefined)
    let rename = new ObjectRename(src, newName)
    return cloudPost(SiteURI.OBJECT_RENAME, rename, callback)
  }
}