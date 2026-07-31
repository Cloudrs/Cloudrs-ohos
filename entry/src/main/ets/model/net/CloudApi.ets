import {
  nativeInit, nativeGetApiVersionInfo, nativeRestoreSession,
  nativeGetSiteConfig, nativeLogin, nativeLogin2fa, nativeLoginWithRefreshToken,
  nativeGetUserStorage, nativeGetUserSetting,
  nativeGetUserAvatar,
  nativeGetDirectory, nativeGetObjectDetail,
  nativeDeleteObjects, nativeDeleteObjectLockAware, nativeUnlockFiles,
  nativeGetFileMetadata, nativeSearchFiles,
  nativeMoveObjects, nativeCopyObjects,
  nativeRenameObject, nativeNewDirectory, nativeNewFile,
  nativeGetDownloadUri, nativeGetUploadUri, nativeDeleteUploadSession,
  nativeUploadLocalFile, nativeUploadLocalFileChunk,
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
  BaseResponse, HttpCallback, ObjectDetail, ProgressCallback,
  ObjectInfo, SiteConfig, UploadRequestResponse,
  UserInfo, UserSetting, UserStorage, UserTasks,
  TwoFactorCallback
} from './ApiTypes';
import { ObjectSrc, ObjectCopy, ObjectMove, ObjectUpload } from './ObjectParam';
import Constant from '../Constant';
import AppLogger from '../../utils/AppLogger';

const CLOUD_API_TAG: string = 'CloudApi';

// 单文件补 metadata 的数量上限，防止异常目录里大量空文件把请求打爆
const METADATA_PROBE_LIMIT: number = 20;

export interface FileLockApplication {
  type?: string;
  viewer_id?: string;
}

export interface FileLockOwner {
  application?: FileLockApplication;
}

export interface FileLockConflict {
  path?: string;
  token?: string;
  type: number;
  owner?: FileLockOwner;
}

export interface LockAwareDeleteCallback {
  onStart?: () => void;
  onSuccess: () => void;
  onFailure: (msg: string, conflicts: FileLockConflict[]) => void;
}

export class CloudApi {
  private static withApiLogging<T>(name: string, callback?: HttpCallback<T>): HttpCallback<T> | undefined {
    if (!callback) {
      return callback;
    }
    const onStart = callback.onStart;
    const onSuccess = callback.onSuccess;
    const onFailure = callback.onFailure;
    return {
      onStart: onStart,
      onSuccess: (data: T) => onSuccess(data),
      onFailure: (msg: string) => {
        AppLogger.warn(CLOUD_API_TAG, `${name} failed: ${msg}`);
        onFailure(msg);
      }
    };
  }

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

  static getApiVersionInfo(callback?: HttpCallback<string[]>): void {
    nativeGetApiVersionInfo(CloudApi.withApiLogging('getApiVersionInfo', callback));
  }

  static restoreSession(url: string, token: string, refreshToken: string, isV3: boolean): void {
    AppStorage.setOrCreate(Constant.CLOUD_BASE_URL, url);
    AppStorage.setOrCreate(Constant.CLOUD_COOKIE,
      isV3 ? token : `${Constant.CLOUD_V4_COOKIE_PREFIX}${token}`);
    AppStorage.setOrCreate(Constant.CLOUD_REFRESH_TOKEN, refreshToken);
    nativeRestoreSession(url, token, refreshToken, isV3);
  }

  static getSiteConfig(callback?: HttpCallback<SiteConfig>): void {
    nativeGetSiteConfig(CloudApi.withApiLogging('getSiteConfig', callback));
  }

  static getLogo(_baseUrl?: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Logo fetch not supported via native layer
  }

  static login(username: string, password: string, callback?: HttpCallback<UserInfo>, twoFactorCallback?: TwoFactorCallback): void {
    AppLogger.info(CLOUD_API_TAG, `login user=${username}`);
    if (callback?.onStart) { callback.onStart(); }
    nativeLogin(username, password, {
      onSuccess: (result: string[]) => {
        if (result[Constant.LOGIN_RESULT_USER_INDEX] === Constant.LOGIN_TWO_FACTOR_REQUIRED) {
          AppLogger.info(CLOUD_API_TAG, 'login 2fa required');
          twoFactorCallback?.onTwoFactorRequired();
          return;
        }
        AppLogger.info(CLOUD_API_TAG, 'login ok');
        CloudApi.storeLoginResult(result);
        callback?.onSuccess(JSON.parse(result[Constant.LOGIN_RESULT_USER_INDEX]) as UserInfo);
      },
      onFailure: (msg: string) => {
        AppLogger.warn(CLOUD_API_TAG, `login failed: ${msg}`);
        callback?.onFailure(msg);
      },
    });
  }

  static login2fa(code: string, callback?: HttpCallback<UserInfo>): void {
    if (callback?.onStart) { callback.onStart(); }
    nativeLogin2fa(code, {
      onSuccess: (result: string[]) => {
        AppLogger.info(CLOUD_API_TAG, 'login2fa ok');
        CloudApi.storeLoginResult(result);
        callback?.onSuccess(JSON.parse(result[Constant.LOGIN_RESULT_USER_INDEX]) as UserInfo);
      },
      onFailure: (msg: string) => {
        AppLogger.warn(CLOUD_API_TAG, `login2fa failed: ${msg}`);
        callback?.onFailure(msg);
      },
    });
  }

  static loginWithRefreshToken(baseUrl: string, refreshToken: string, callback?: HttpCallback<UserInfo>): void {
    if (callback?.onStart) { callback.onStart(); }
    AppLogger.info(CLOUD_API_TAG, `session refresh baseUrl=${baseUrl}`);
    nativeLoginWithRefreshToken(baseUrl, refreshToken, {
      onSuccess: (result: string[]) => {
        AppLogger.info(CLOUD_API_TAG, 'session refresh ok');
        CloudApi.storeLoginResult(result);
        callback?.onSuccess(JSON.parse(result[Constant.LOGIN_RESULT_USER_INDEX]) as UserInfo);
      },
      onFailure: (msg: string) => {
        AppLogger.warn(CLOUD_API_TAG, `session refresh failed: ${msg}`);
        callback?.onFailure(msg);
      },
    });
  }

  private static storeLoginResult(result: string[]): void {
    const token: string = result[Constant.LOGIN_RESULT_TOKEN_INDEX];
    const refreshToken: string = result[Constant.LOGIN_RESULT_REFRESH_TOKEN_INDEX];
    const version: string = result[Constant.LOGIN_RESULT_VERSION_INDEX];
    const refreshExpires: string = result[Constant.LOGIN_RESULT_REFRESH_EXPIRES_INDEX] ?? '';
    const cookieToStore = version === Constant.CLOUD_VERSION_V3 ?
      `${Constant.CLOUD_V3_COOKIE_PREFIX}${token}` : `${Constant.CLOUD_V4_COOKIE_PREFIX}${token}`;
    let expiresDate = refreshExpires.length > 0 ? new Date(refreshExpires) : new Date();
    if (refreshExpires.length === 0 || Number.isNaN(expiresDate.getTime())) {
      expiresDate = new Date();
      expiresDate.setDate(expiresDate.getDate() + Constant.CLOUD_COOKIE_EXPIRE_DAYS);
    }
    AppStorage.setOrCreate(Constant.CLOUD_COOKIE, cookieToStore);
    AppStorage.setOrCreate(Constant.CLOUD_COOKIE_EXPIRES, expiresDate.toUTCString());
    AppStorage.setOrCreate(Constant.CLOUD_REFRESH_TOKEN, refreshToken);
  }

  static userSetting(callback?: HttpCallback<UserSetting>): void {
    nativeGetUserSetting(CloudApi.withApiLogging('userSetting', callback));
  }

  static userStorage(callback?: HttpCallback<UserStorage>): void {
    nativeGetUserStorage(CloudApi.withApiLogging('userStorage', callback));
  }

  static getFilesInfo(path: string = '/', callback?: HttpCallback<DirectoryInfo>): void {
    const startedAt = new Date().getTime();
    nativeGetDirectory(path, {
      onStart: callback?.onStart,
      onSuccess: (data: DirectoryInfo) => {
        const listedAt = new Date().getTime();
        CloudApi.enrichV4DirectoryMetadata(path, data).then((enriched: DirectoryInfo) => {
          const doneAt = new Date().getTime();
          AppLogger.info(CLOUD_API_TAG, `[timing] getFilesInfo(${path}) objects=${(enriched.objects ?? []).length} ` +
            `list=${listedAt - startedAt}ms metadata=${doneAt - listedAt}ms`);
          callback?.onSuccess(enriched);
        });
      },
      onFailure: (msg: string) => {
        AppLogger.warn(CLOUD_API_TAG, `getFilesInfo(${path}) failed: ${msg}`);
        callback?.onFailure(msg);
      }
    });
  }

  /**
   * 对少量文件逐个查 metadata（走 /file/info 单文件接口）。
   *
   * 用途：目录列表补 metadata 只拉第一页（page_size=2000），几千个文件的目录里
   * 排在后面的拿不到 metadata，"上传中"角标就丢了。但真正需要这个字段的只有
   * 0 字节的上传占位，一个目录通常也就零星几个，逐个点查远比翻完整个目录便宜
   * （翻页是串行的，几千张的备份目录一次要好几秒，每次刷新都付这个代价不值得）。
   *
   * 数量上兜一道 METADATA_PROBE_LIMIT，避免异常目录里几百个空文件把请求打爆。
   */
  private static async fillMetadataOneByOne(dirPath: string, targets: ObjectInfo[]): Promise<number> {
    if (targets.length === 0) {
      return 0;
    }
    const probes = targets.slice(0, METADATA_PROBE_LIMIT);
    let uploadingCount = 0;
    for (const item of probes) {
      try {
        const separator = dirPath.endsWith('/') ? '' : '/';
        const metadata =
          JSON.parse(await nativeGetFileMetadata(`${dirPath}${separator}${item.name}`)) as Record<string, string>;
        if (Object.keys(metadata).length === 0) {
          continue;
        }
        item.metadata = metadata;
        if (metadata['sys:upload_session_id'] !== undefined) {
          uploadingCount++;
        }
      } catch (err) {
        AppLogger.warn(CLOUD_API_TAG, `probe metadata failed name=${item.name}: ${(err as Error)?.message ?? err}`);
      }
    }
    if (targets.length > probes.length) {
      AppLogger.info(CLOUD_API_TAG, `metadata probe capped at ${METADATA_PROBE_LIMIT}, skipped ${targets.length - probes.length}`);
    }
    return uploadingCount;
  }

  /**
   * 给目录列表补 metadata，目前只用于显示"上传中"角标。
   *
   * 关键前提：只有未完成上传的占位文件才带 sys:upload_session_id，而这种文件必然是 0 字节。
   * 所以完全不需要为整个目录拉 metadata——先按列表里现成的 size 筛出候选（通常一个都没有），
   * 只对这几个点查即可。
   *
   * 之前的做法是无条件拉一次 /api/v4/file?page=0&page_size=2000：4882 个文件的目录实测
   * 要 344ms，而且是阻塞列表显示的，即便目录里一个空文件都没有也照付不误。
   */
  private static async enrichV4DirectoryMetadata(path: string, data: DirectoryInfo): Promise<DirectoryInfo> {
    const cookie = AppStorage.get<string>(Constant.CLOUD_COOKIE) ?? '';
    if (!cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX) || (data.objects ?? []).length === 0) {
      return data;
    }
    // 必须排除目录：文件夹的 size 本来就是 0，不加这个判断的话每进一个目录
    // 都会为它的每个子文件夹白发一次点查（实测 7 个子目录 = 291ms）。
    const empties = (data.objects ?? []).filter((item: ObjectInfo) =>
      item.size <= 0 && item.type !== Constant.OBJECT_DIR_TYPE);
    if (empties.length === 0) {
      return data;
    }
    try {
      const uploadingCount = await CloudApi.fillMetadataOneByOne(path, empties);
      if (uploadingCount > 0) {
        AppLogger.info(CLOUD_API_TAG, `V4 metadata enriched path=${path}, uploading=${uploadingCount}`);
      }
    } catch (err) {
      AppLogger.warn(CLOUD_API_TAG, `V4 metadata enrichment skipped path=${path}: ${(err as Error)?.message ?? err}`);
    }
    return data;
  }

  /** 服务端搜索。V3 / V4 的差异与翻页都在 native 里处理，这里只管解析结果。 */
  static searchFiles(keyword: string, path: string = '/', callback?: HttpCallback<ObjectInfo[]>): void {
    callback?.onStart?.();
    nativeSearchFiles(keyword, path)
      .then((json: string) => callback?.onSuccess(JSON.parse(json) as ObjectInfo[]))
      .catch((err: Error) => {
        const message = err.message ?? String(err);
        AppLogger.warn(CLOUD_API_TAG, `searchFiles failed: ${message}`);
        callback?.onFailure(message);
      });
  }

  static getThumb(id: string, callback?: HttpCallback<string>): void {
    nativeGetThumb(id, CloudApi.withApiLogging('getThumb', callback));
  }

  static getPreview(_id: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Preview fetch not supported via native layer
  }

  static getUserAvatar(_userId: string, _callback?: HttpCallback<Uint8Array>): void {
    nativeGetUserAvatar(_userId, _callback);
  }

  static getObjectDetail(id: string, isFolder: boolean, callback?: HttpCallback<ObjectDetail>): void {
    nativeGetObjectDetail(id, isFolder, CloudApi.withApiLogging('getObjectDetail', callback));
  }

  static newObject(path: string, isDir: boolean, callback?: HttpCallback<null>): void {
    if (isDir) {
      nativeNewDirectory(path, CloudApi.withApiLogging(`newDirectory(${path})`, callback));
    } else {
      nativeNewFile(path, CloudApi.withApiLogging(`newFile(${path})`, callback));
    }
  }

  static deleteObjects(src: ObjectSrc, callback?: HttpCallback<null>): void {
    nativeDeleteObjects(src.items ?? [], src.dirs ?? [], CloudApi.withApiLogging('deleteObjects', callback));
  }

  static deleteObject(id: string, isDir: boolean = false, callback?: HttpCallback<null>): void {
    nativeDeleteObjects(isDir ? [] : [id], isDir ? [id] : [], CloudApi.withApiLogging('deleteObject', callback));
  }

  /**
   * V4 删除必须保留 40073 响应里的锁 token，网页端正是用这些 token 调 /file/lock 强制解锁。
   * native deleteObjects 只上抛错误字符串，会丢失 data；V3 没有该锁接口，继续走 native 兼容路径。
   */
  static deleteObjectLockAware(id: string, isDir: boolean, remotePath: string,
    callback: LockAwareDeleteCallback): void {
    const cookie = AppStorage.get<string>(Constant.CLOUD_COOKIE) ?? '';
    if (!cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX)) {
      nativeDeleteObjects(isDir ? [] : [id], isDir ? [id] : [], {
        onStart: callback.onStart,
        onSuccess: () => callback.onSuccess(),
        onFailure: (msg: string) => callback.onFailure(msg, [])
      });
      return;
    }
    callback.onStart?.();
    AppLogger.info(CLOUD_API_TAG, `lock-aware delete path=${remotePath}`);
    nativeDeleteObjectLockAware(remotePath).then((json: string) => {
      const response = JSON.parse(json) as BaseResponse<FileLockConflict[]>;
      AppLogger.info(CLOUD_API_TAG, `lock-aware delete response code=${response.code}, ` +
        `conflicts=${Array.isArray(response.data) ? response.data.length : 0}`);
      if (response.code === 0) {
        callback.onSuccess();
        return;
      }
      const conflicts = response.code === 40073 && Array.isArray(response.data) ? response.data : [];
      callback.onFailure(`${response.code}: ${response.msg}`, conflicts);
    }).catch((err: Error) => {
      AppLogger.warn(CLOUD_API_TAG, `lock-aware delete request failed: ${err.message ?? String(err)}`);
      callback.onFailure(err.message ?? String(err), []);
    });
  }

  static unlockFiles(tokens: string[], callback: HttpCallback<null>): void {
    const cookie = AppStorage.get<string>(Constant.CLOUD_COOKIE) ?? '';
    if (!cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX) || tokens.length === 0) {
      callback.onFailure('当前站点不支持云端文件解锁');
      return;
    }
    callback.onStart?.();
    nativeUnlockFiles(tokens)
      .then(() => {
        AppLogger.info(CLOUD_API_TAG, `force unlock ok, tokens=${tokens.length}`);
        callback.onSuccess(null);
      })
      .catch((err: Error) => callback.onFailure(err.message ?? String(err)));
  }

  static copyObjects(copy: ObjectCopy, callback?: HttpCallback<null>): void {
    nativeCopyObjects(copy.src.items ?? [], copy.src.dirs ?? [], copy.src_dir, copy.dst, CloudApi.withApiLogging('copyObjects', callback));
  }

  static moveObjects(move: ObjectMove, callback?: HttpCallback<null>): void {
    nativeMoveObjects(move.src.items ?? [], move.src.dirs ?? [], move.src_dir, move.dst, CloudApi.withApiLogging('moveObjects', callback));
  }

  static renameObject(id: string, newName: string, isDir: boolean = false, callback?: HttpCallback<null>): void {
    nativeRenameObject(id, newName, isDir, CloudApi.withApiLogging('renameObject', callback));
  }

  static aria2Downloading(callback?: HttpCallback<Aria2Downloading[]>): void {
    nativeAria2Downloading(CloudApi.withApiLogging('aria2Downloading', callback));
  }

  static aria2Finished(page: number, callback?: HttpCallback<Aria2Finished[]>): void {
    nativeAria2Finished(page, CloudApi.withApiLogging('aria2Finished', callback));
  }

  static userTasks(page: number, callback?: HttpCallback<UserTasks>): void {
    nativeGetUserTasks(page, CloudApi.withApiLogging('userTasks', callback));
  }

  static aria2TaskCreate(dst: string, urls: string[], callback?: HttpCallback<null>): void {
    nativeAria2CreateTask(dst, urls, CloudApi.withApiLogging('aria2TaskCreate', callback));
  }

  static deleteAria2Task(gid: string, callback?: HttpCallback<null>): void {
    nativeAria2DeleteTask(gid, CloudApi.withApiLogging('deleteAria2Task', callback));
  }

  static getDownloadUri(id: string, callback?: HttpCallback<string>): void {
    nativeGetDownloadUri(id, CloudApi.withApiLogging('getDownloadUri', callback));
  }

  static deleteUploadSession(remotePath: string, sessionId: string, callback?: HttpCallback<null>): void {
    nativeDeleteUploadSession(remotePath, sessionId, CloudApi.withApiLogging(`deleteUploadSession(${remotePath})`, callback));
  }

  static getUploadUri(object: ObjectUpload, callback?: HttpCallback<UploadRequestResponse>, overwrite: boolean = false): void {
    nativeGetUploadUri(
      object.path, object.size, object.name,
      object.last_modified, object.mime_type,
      overwrite ? 1 : 0,
      CloudApi.withApiLogging(`getUploadUri(${object.name})`, callback)
    );
  }

  static uploadLocalFile(localPath: string, remotePath: string, overwrite: boolean = false,
    lastModifiedMs: number = 0, callback?: HttpCallback<null>): void {
    nativeUploadLocalFile(localPath, remotePath, overwrite, lastModifiedMs,
      CloudApi.withApiLogging(`uploadLocalFile(${remotePath})`, callback));
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
    nativeCreateShareLink(path, expireDays, password, CloudApi.withApiLogging('createShareLink', callback));
  }

  static listShareLinks<T>(callback?: HttpCallback<T>): void {
    nativeListShareLinks(CloudApi.withApiLogging('listShareLinks', callback));
  }

  static deleteShareLink(shareId: string, callback?: HttpCallback<null>): void {
    nativeDeleteShareLink(shareId, CloudApi.withApiLogging('deleteShareLink', callback));
  }

  static createArchive(srcPaths: string[], dstPath: string, callback?: HttpCallback<string>): void {
    nativeCreateArchive(srcPaths, dstPath, CloudApi.withApiLogging('createArchive', callback));
  }

  static extractArchive(srcPaths: string[], dstPath: string, callback?: HttpCallback<string>): void {
    nativeExtractArchive(srcPaths, dstPath, CloudApi.withApiLogging('extractArchive', callback));
  }
}
