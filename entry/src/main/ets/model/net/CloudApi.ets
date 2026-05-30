import {
  nativeInit, nativeRestoreSession,
  nativeGetSiteConfig, nativeLogin, nativeLogin2fa,
  nativeGetUserStorage, nativeGetUserSetting,
  nativeGetDirectory, nativeGetObjectDetail,
  nativeDeleteObjects, nativeMoveObjects, nativeCopyObjects,
  nativeRenameObject, nativeNewDirectory, nativeNewFile,
  nativeGetDownloadUri, nativeGetUploadUri, nativeUploadLocalFile, nativeUploadLocalFileChunk,
  nativeUploadLocalFileChunkWithProgress, nativeUploadLocalFileChunkToUrl,
  nativeUploadLocalFileChunkToUrlWithProgress,
  nativeAria2Downloading, nativeAria2Finished,
  nativeAria2CreateTask, nativeAria2DeleteTask,
  nativeGetUserTasks,
  nativeGetThumb,
  nativeCreateShareLink, nativeListShareLinks, nativeDeleteShareLink,
  nativeCreateArchive, nativeExtractArchive
} from '../../utils/CloudreveNative';
import { FileType } from '../../utils/CommonUtil';
import {
  Aria2Downloading, Aria2Finished, DirectoryInfo,
  HttpCallback, ObjectDetail, ProgressCallback,
  ObjectInfo, SiteConfig, UploadRequestResponse,
  UserInfo, UserSetting, UserStorage, UserTasks,
  TwoFactorCallback
} from './ApiTypes';
import { ObjectSrc, ObjectCopy, ObjectMove, ObjectUpload } from './ObjectParam';
import Constant from '../Constant';

export class CloudApi {
  static getTotalPath(item: ObjectInfo): string {
    if (item.type === 'dir') {
      return item.path === '/' ? item.path + item.name : `${item.path}/${item.name}`;
    }
    return item.path;
  }

  static getBaseURL(): string {
    return AppStorage.get<string>(Constant.CLOUD_BASE_URL) ?? '';
  }

  static init(url: string, callback?: HttpCallback<string>): void {
    AppStorage.setOrCreate(Constant.CLOUD_BASE_URL, url);
    nativeInit(url, callback);
  }

  static restoreSession(url: string, token: string, refreshToken: string, isV3: boolean): void {
    AppStorage.setOrCreate(Constant.CLOUD_BASE_URL, url);
    nativeRestoreSession(url, token, refreshToken, isV3);
  }

  static getSiteConfig(callback?: HttpCallback<SiteConfig>): void {
    nativeGetSiteConfig(callback);
  }

  static getLogo(_baseUrl?: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Logo fetch not supported via native layer
  }

  static login(username: string, password: string, callback?: HttpCallback<UserInfo>, twoFactorCallback?: TwoFactorCallback): void {
    if (callback?.onStart) { callback.onStart(); }
    nativeLogin(username, password, {
      onSuccess: (result: string[]) => {
        if (result[Constant.LOGIN_RESULT_USER_INDEX] === Constant.LOGIN_TWO_FACTOR_REQUIRED) {
          twoFactorCallback?.onTwoFactorRequired();
          return;
        }
        CloudApi.storeLoginResult(result);
        callback?.onSuccess(JSON.parse(result[Constant.LOGIN_RESULT_USER_INDEX]) as UserInfo);
      },
      onFailure: (msg: string) => callback?.onFailure(msg),
    });
  }

  static login2fa(code: string, callback?: HttpCallback<UserInfo>): void {
    if (callback?.onStart) { callback.onStart(); }
    nativeLogin2fa(code, {
      onSuccess: (result: string[]) => {
        CloudApi.storeLoginResult(result);
        callback?.onSuccess(JSON.parse(result[Constant.LOGIN_RESULT_USER_INDEX]) as UserInfo);
      },
      onFailure: (msg: string) => callback?.onFailure(msg),
    });
  }

  private static storeLoginResult(result: string[]): void {
    const token: string = result[Constant.LOGIN_RESULT_TOKEN_INDEX];
    const refreshToken: string = result[Constant.LOGIN_RESULT_REFRESH_TOKEN_INDEX];
    const version: string = result[Constant.LOGIN_RESULT_VERSION_INDEX];
    const cookieToStore = version === Constant.CLOUD_VERSION_V3 ?
      `${Constant.CLOUD_V3_COOKIE_PREFIX}${token}` : `${Constant.CLOUD_V4_COOKIE_PREFIX}${token}`;
    const expiresDate = new Date();
    expiresDate.setDate(expiresDate.getDate() + Constant.CLOUD_COOKIE_EXPIRE_DAYS);
    AppStorage.setOrCreate(Constant.CLOUD_COOKIE, cookieToStore);
    AppStorage.setOrCreate(Constant.CLOUD_COOKIE_EXPIRES, expiresDate.toUTCString());
    AppStorage.setOrCreate(Constant.CLOUD_REFRESH_TOKEN, refreshToken);
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

  static getThumb(id: string, callback?: HttpCallback<string>): void {
    nativeGetThumb(id, callback);
  }

  static getPreview(_id: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Preview fetch not supported via native layer
  }

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
    nativeCopyObjects(copy.src.items ?? [], copy.src.dirs ?? [], copy.src_dir, copy.dst, callback);
  }

  static moveObjects(move: ObjectMove, callback?: HttpCallback<null>): void {
    nativeMoveObjects(move.src.items ?? [], move.src.dirs ?? [], move.src_dir, move.dst, callback);
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

  static getUploadUri(object: ObjectUpload, callback?: HttpCallback<UploadRequestResponse>, overwrite: boolean = false): void {
    nativeGetUploadUri(
      object.path, object.size, object.name,
      object.last_modified, object.mime_type,
      overwrite ? 1 : 0,
      callback
    );
  }

  static uploadLocalFile(localPath: string, remotePath: string, overwrite: boolean = false, callback?: HttpCallback<null>): void {
    nativeUploadLocalFile(localPath, remotePath, overwrite, callback);
  }

  static uploadLocalFileChunk(
    localPath: string,
    sessionId: string,
    index: number,
    offset: number,
    length: number
  ): Promise<number> {
    return nativeUploadLocalFileChunk(localPath, sessionId, index, offset, length);
  }

  static uploadLocalFileChunkWithProgress(
    localPath: string,
    sessionId: string,
    index: number,
    offset: number,
    length: number,
    progress: (uploaded: number) => void
  ): Promise<number> {
    return nativeUploadLocalFileChunkWithProgress(localPath, sessionId, index, offset, length, progress);
  }

  static uploadLocalFileChunkToUrl(
    localPath: string,
    uploadUrl: string,
    credential: string,
    index: number,
    offset: number,
    length: number
  ): Promise<number> {
    return nativeUploadLocalFileChunkToUrl(localPath, uploadUrl, credential, index, offset, length);
  }

  static uploadLocalFileChunkToUrlWithProgress(
    localPath: string,
    uploadUrl: string,
    credential: string,
    index: number,
    offset: number,
    length: number,
    progress: (uploaded: number) => void
  ): Promise<number> {
    return nativeUploadLocalFileChunkToUrlWithProgress(localPath, uploadUrl, credential, index, offset, length, progress);
  }

  static downloadFile(_uri: string, _filePath: string, _callback?: HttpCallback<string>, _progress?: ProgressCallback): void {
    // Implemented in RequestDownload.ets using HarmonyOS request.agent
  }

  static createShareLink(path: string, expireDays: number, password: string, callback?: HttpCallback<string>): void {
    nativeCreateShareLink(path, expireDays, password, callback);
  }

  static listShareLinks<T>(callback?: HttpCallback<T>): void {
    nativeListShareLinks(callback);
  }

  static deleteShareLink(shareId: string, callback?: HttpCallback<null>): void {
    nativeDeleteShareLink(shareId, callback);
  }

  static createArchive(srcPaths: string[], dstPath: string, callback?: HttpCallback<string>): void {
    nativeCreateArchive(srcPaths, dstPath, callback);
  }

  static extractArchive(srcPaths: string[], dstPath: string, callback?: HttpCallback<string>): void {
    nativeExtractArchive(srcPaths, dstPath, callback);
  }
}
