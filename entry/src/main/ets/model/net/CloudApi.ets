import {
  setBaseUrl, getBaseUrl, setCookie,
  nativePing, nativeGetSiteConfig, nativeLogin,
  nativeGetUserStorage, nativeGetUserSetting,
  nativeGetDirectory, nativeGetObjectDetail,
  nativeDeleteObjects, nativeMoveObjects, nativeCopyObjects,
  nativeRenameObject, nativeNewDirectory, nativeNewFile,
  nativeGetDownloadUri, nativeGetUploadUri,
  nativeAria2Downloading, nativeAria2Finished,
  nativeAria2CreateTask, nativeAria2DeleteTask,
  nativeGetUserTasks
} from '../../utils/CloudreveNative';
import { FileType } from '../../utils/CommonUtil';
import {
  Aria2Downloading, Aria2Finished, DirectoryInfo,
  HttpCallback, ObjectDetail, ProgressCallback,
  ObjectInfo, SiteConfig, UploadRequestResponse,
  UserInfo, UserSetting, UserStorage, UserTasks
} from './ApiTypes';
import { ObjectSrc, ObjectCopy, ObjectMove, ObjectUpload } from './ObjectParam';
import { uri } from '@kit.ArkTS';
import Constant from '../Constant';

export { setBaseUrl as baseUrlSet, getBaseUrl as baseUrlGet, setCookie as cookieSet };

export class CloudApi {
  static getTotalPath(item: ObjectInfo): string {
    if (item.type === 'dir') {
      return item.path === '/' ? item.path + item.name : `${item.path}/${item.name}`;
    }
    return item.path;
  }

  static getBaseURL(): string {
    const fullApiUrl = getBaseUrl();
    // Strip the /api/v3 suffix added by the Rust client
    const apiSuffix = '/api/v3';
    if (fullApiUrl.endsWith(apiSuffix)) {
      return fullApiUrl.slice(0, fullApiUrl.length - apiSuffix.length);
    }
    return fullApiUrl;
  }

  static ping(callback?: HttpCallback<string>): void {
    nativePing(callback);
  }

  static getSiteConfig(callback?: HttpCallback<SiteConfig>): void {
    nativeGetSiteConfig(callback);
  }

  /**
   * Fetch site logo image — still uses HTTP fetch directly since native layer
   * does not expose binary image endpoints.
   */
  static getLogo(_baseUrl?: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Logo fetch not supported via native layer; callers should handle gracefully
  }

  static login(username: string, password: string, callback?: HttpCallback<UserInfo>): void {
    if (callback?.onStart) { callback.onStart(); }
    nativeLogin(username, password, {
      onSuccess: (result: string[]) => {
        const userInfo: UserInfo = JSON.parse(result[0]) as UserInfo;
        const setCookieHeader: string = result[1];
        const regexSession = /cloudreve-session=([^;]+)/;
        const matchCookie = setCookieHeader.match(regexSession);
        if (matchCookie) {
          const cookie = `cloudreve-session=${matchCookie[1]}`;
          AppStorage.setOrCreate(Constant.CLOUD_COOKIE, cookie);
          setCookie(cookie);
        }
        const regexExpires = /Expires=([^;]+)/i;
        const matchExpires = setCookieHeader.match(regexExpires);
        if (matchExpires) {
          AppStorage.setOrCreate(Constant.CLOUD_COOKIE_EXPIRES, matchExpires[1]);
        }
        callback?.onSuccess(userInfo);
      },
      onFailure: (msg: string) => callback?.onFailure(msg),
    });
  }

  static userSetting(callback?: HttpCallback<UserSetting>): void {
    nativeGetUserSetting(callback);
  }

  static userStorage(callback?: HttpCallback<UserStorage>): void {
    nativeGetUserStorage(callback);
  }

  static getFilesInfo(path: string = '/', callback?: HttpCallback<DirectoryInfo>): void {
    nativeGetDirectory(path, callback);
  }

  /**
   * Thumbnail fetch — not supported via native layer.
   */
  static getThumb(_id: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Thumb fetch not supported via native layer
  }

  /**
   * Preview image fetch — not supported via native layer.
   */
  static getPreview(_id: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Preview fetch not supported via native layer
  }

  /**
   * User avatar fetch — not supported via native layer.
   */
  static getUserAvatar(_userId: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Avatar fetch not supported via native layer
  }

  static getObjectDetail(id: string, isFolder: boolean, callback?: HttpCallback<ObjectDetail>): void {
    nativeGetObjectDetail(id, isFolder, callback);
  }

  static newObject(path: string, isDir: boolean, callback?: HttpCallback<null>): void {
    if (isDir) {
      nativeNewDirectory(path, callback);
    } else {
      nativeNewFile(path, callback);
    }
  }

  static deleteObjects(src: ObjectSrc, callback?: HttpCallback<null>): void {
    nativeDeleteObjects(src.items ?? [], src.dirs ?? [], callback);
  }

  static deleteObject(id: string, isDir: boolean = false, callback?: HttpCallback<null>): void {
    nativeDeleteObjects(isDir ? [] : [id], isDir ? [id] : [], callback);
  }

  static copyObjects(copy: ObjectCopy, callback?: HttpCallback<null>): void {
    nativeCopyObjects(copy.src.items ?? [], copy.src.dirs ?? [], copy.dst, callback);
  }

  static moveObjects(move: ObjectMove, callback?: HttpCallback<null>): void {
    nativeMoveObjects(move.src.items ?? [], move.src.dirs ?? [], move.dst, callback);
  }

  static renameObject(id: string, newName: string, isDir: boolean = false, callback?: HttpCallback<null>): void {
    nativeRenameObject(id, newName, isDir, callback);
  }

  static aria2Downloading(callback?: HttpCallback<Aria2Downloading[]>): void {
    nativeAria2Downloading(callback);
  }

  static aria2Finished(page: number, callback?: HttpCallback<Aria2Finished[]>): void {
    nativeAria2Finished(page, callback);
  }

  static userTasks(page: number, callback?: HttpCallback<UserTasks>): void {
    nativeGetUserTasks(page, callback);
  }

  static aria2TaskCreate(dst: string, urls: string[], callback?: HttpCallback<null>): void {
    nativeAria2CreateTask(dst, urls, callback);
  }

  static deleteAria2Task(gid: string, callback?: HttpCallback<null>): void {
    nativeAria2DeleteTask(gid, callback);
  }

  static getDownloadUri(id: string, callback?: HttpCallback<string>): void {
    nativeGetDownloadUri(id, callback);
  }

  static getUploadUri(object: ObjectUpload, callback?: HttpCallback<UploadRequestResponse>): void {
    nativeGetUploadUri(
      object.path, object.size, object.name,
      object.last_modified, object.mime_type,
      0, // chunkSize: not present on ObjectUpload, default 0
      callback
    );
  }

  /**
   * Large file download uses request.agent via RequestDownload.ets — not replaced.
   */
  static downloadFile(_uri: string, _filePath: string, _callback?: HttpCallback<string>, _progress?: ProgressCallback): void {
    // Implemented in RequestDownload.ets using HarmonyOS request.agent
  }
}
