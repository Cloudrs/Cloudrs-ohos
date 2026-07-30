import {
  nativeInit, nativeGetApiVersionInfo, nativeRestoreSession,
  nativeGetSiteConfig, nativeLogin, nativeLogin2fa, nativeLoginWithRefreshToken,
  nativeGetUserStorage, nativeGetUserSetting,
  nativeGetUserAvatar,
  nativeGetDirectory, nativeGetObjectDetail,
  nativeDeleteObjects, nativeMoveObjects, nativeCopyObjects,
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
import { http } from '@kit.NetworkKit';

const CLOUD_API_TAG: string = 'CloudApi';
const SERVER_SEARCH_PAGE_SIZE: number = 2000;
const SERVER_SEARCH_MAX_PAGES: number = 100;

interface V4SearchFile {
  id: string;
  name: string;
  path: string;
  type: number;
  size: number;
  created_at: string;
  updated_at: string;
  metadata?: Record<string, string>;
  capability?: string;
}

interface V4SearchPagination {
  page?: number;
  page_size?: number;
  next_page_token?: string;
}

interface V4SearchData {
  files: V4SearchFile[];
  pagination?: V4SearchPagination;
}

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

interface V4DeleteFileRequest {
  uris: string[];
}

interface V4UnlockFileRequest {
  tokens: string[];
}

export class CloudApi {
  private static v4RefreshPromise?: Promise<string>;

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
    nativeGetDirectory(path, {
      onStart: callback?.onStart,
      onSuccess: (data: DirectoryInfo) => {
        CloudApi.enrichV4DirectoryMetadata(path, data).then((enriched: DirectoryInfo) => {
          callback?.onSuccess(enriched);
        });
      },
      onFailure: (msg: string) => {
        AppLogger.warn(CLOUD_API_TAG, `getFilesInfo(${path}) failed: ${msg}`);
        callback?.onFailure(msg);
      }
    });
  }

  private static async enrichV4DirectoryMetadata(path: string, data: DirectoryInfo): Promise<DirectoryInfo> {
    const cookie = AppStorage.get<string>(Constant.CLOUD_COOKIE) ?? '';
    if (!cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX) || (data.objects ?? []).length === 0) {
      return data;
    }
    try {
      const uri = CloudApi.buildV4MyUri(path);
      const url = `${CloudApi.getApiBaseUrl()}/api/v4/file?uri=${encodeURIComponent(uri)}` +
        `&page=0&page_size=${SERVER_SEARCH_PAGE_SIZE}`;
      const response = await CloudApi.requestV4JsonWithRefresh<V4SearchData>(url, cookie);
      if (response.code !== 0 || !response.data) {
        AppLogger.warn(CLOUD_API_TAG, `V4 metadata list failed path=${path}, code=${response.code}, msg=${response.msg}`);
        return data;
      }
      const metadataById = new Map<string, Record<string, string>>();
      const metadataByName = new Map<string, Record<string, string>>();
      (response.data.files ?? []).forEach((file: V4SearchFile) => {
        if (file.metadata) {
          metadataById.set(file.id, file.metadata);
          metadataByName.set(file.name, file.metadata);
        }
      });
      let uploadingCount = 0;
      (data.objects ?? []).forEach((item: ObjectInfo) => {
        const metadata = metadataById.get(item.id) ?? metadataByName.get(item.name);
        if (metadata) {
          item.metadata = metadata;
          if (metadata['sys:upload_session_id'] !== undefined) {
            uploadingCount++;
          }
        }
      });
      if (uploadingCount > 0) {
        AppLogger.info(CLOUD_API_TAG, `V4 metadata enriched path=${path}, uploading=${uploadingCount}`);
      }
    } catch (err) {
      AppLogger.warn(CLOUD_API_TAG, `V4 metadata enrichment skipped path=${path}: ${(err as Error)?.message ?? err}`);
    }
    return data;
  }

  static searchFiles(keyword: string, path: string = '/', callback?: HttpCallback<ObjectInfo[]>): void {
    callback?.onStart?.();
    CloudApi.requestServerSearch(keyword, path)
      .then((objects: ObjectInfo[]) => callback?.onSuccess(objects))
      .catch((err: Error) => {
        const message = err.message ?? String(err);
        AppLogger.warn(CLOUD_API_TAG, `searchFiles failed: ${message}`);
        callback?.onFailure(message);
      });
  }

  private static async requestServerSearch(keyword: string, path: string): Promise<ObjectInfo[]> {
    const cookie = AppStorage.get<string>(Constant.CLOUD_COOKIE) ?? '';
    if (cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX)) {
      return CloudApi.requestV4Search(keyword, path, cookie);
    }
    return CloudApi.requestV3Search(keyword, path, cookie);
  }

  private static async requestV3Search(keyword: string, path: string, cookie: string): Promise<ObjectInfo[]> {
    const queryPath = path.length > 0 ? path : '/';
    const url = `${CloudApi.getApiBaseUrl()}/api/v3/file/search/keywords/${encodeURIComponent(keyword)}` +
      `?path=${encodeURIComponent(queryPath)}`;
    const response = await CloudApi.requestJson<BaseResponse<DirectoryInfo>>(url, {
      'Cookie': cookie.startsWith(Constant.CLOUD_V3_COOKIE_PREFIX) ?
        cookie : `${Constant.CLOUD_V3_COOKIE_PREFIX}${cookie}`
    });
    if (response.code !== 0 || !response.data) {
      throw new Error(response.msg || `V3 search failed (${response.code})`);
    }
    return response.data.objects ?? [];
  }

  private static async requestV4Search(keyword: string, path: string, cookie: string): Promise<ObjectInfo[]> {
    const fileUri = CloudApi.buildV4SearchUri(path, keyword);
    const objectsById: Map<string, ObjectInfo> = new Map<string, ObjectInfo>();
    let page = 0;
    let nextPageToken = '';

    while (page < SERVER_SEARCH_MAX_PAGES) {
      let url = `${CloudApi.getApiBaseUrl()}/api/v4/file?uri=${encodeURIComponent(fileUri)}` +
        `&page=${page}&page_size=${SERVER_SEARCH_PAGE_SIZE}`;
      if (nextPageToken.length > 0) {
        url += `&next_page_token=${encodeURIComponent(nextPageToken)}`;
      }
      const response = await CloudApi.requestV4JsonWithRefresh<V4SearchData>(url, cookie);
      if (response.code !== 0 || !response.data) {
        throw new Error(response.msg || `V4 search failed (${response.code})`);
      }

      const files = response.data.files ?? [];
      const previousSize = objectsById.size;
      files.forEach((item: V4SearchFile) => {
        objectsById.set(item.id, CloudApi.mapV4SearchFile(item));
      });
      if (files.length < SERVER_SEARCH_PAGE_SIZE || objectsById.size === previousSize) {
        break;
      }

      nextPageToken = response.data.pagination?.next_page_token ?? '';
      page += 1;
    }
    return Array.from(objectsById.values());
  }

  private static async requestJson<T>(url: string, headers: Record<string, string>): Promise<T> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== Constant.HTTP_STATUS_OK) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return JSON.parse(response.result as string) as T;
    } catch (err) {
      const message = (err as Error)?.message ?? String(err);
      throw new Error(message);
    } finally {
      request.destroy();
    }
  }

  private static getApiBaseUrl(): string {
    const baseUrl = CloudApi.getBaseURL();
    return baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  }

  private static buildV4SearchUri(path: string, keyword: string): string {
    const normalizedPath = path.length === 0 || path === '/' ? '' :
      path.split('/').filter((segment: string) => segment.length > 0)
        .map((segment: string) => encodeURIComponent(segment)).join('/');
    return `cloudreve://my/${normalizedPath}?name=${encodeURIComponent(keyword)}&case_folding=true`;
  }

  private static mapV4SearchFile(item: V4SearchFile): ObjectInfo {
    return {
      id: item.id,
      name: item.name,
      path: CloudApi.getV4ParentPath(item.path),
      thumb: item.metadata?.['thumb:disabled'] === undefined && item.type === 0,
      size: item.size ?? 0,
      type: item.type === 1 ? Constant.OBJECT_DIR_TYPE : Constant.OBJECT_FILE_TYPE,
      date: item.updated_at ?? item.created_at ?? '',
      create_date: item.created_at ?? '',
      source_enabled: true,
      metadata: item.metadata
    };
  }

  private static async requestV4JsonWithRefresh<T>(url: string,
    cookie: string): Promise<BaseResponse<T>> {
    let token = cookie.substring(Constant.CLOUD_V4_COOKIE_PREFIX.length);
    let response = await CloudApi.requestJson<BaseResponse<T>>(url, {
      'Authorization': `Bearer ${token}`
    });
    if (response.code !== 401) {
      return response;
    }
    AppLogger.info(CLOUD_API_TAG, 'V4 access token expired, refreshing before retry');
    token = await CloudApi.refreshV4AccessToken();
    response = await CloudApi.requestJson<BaseResponse<T>>(url, {
      'Authorization': `Bearer ${token}`
    });
    return response;
  }

  private static refreshV4AccessToken(): Promise<string> {
    if (CloudApi.v4RefreshPromise) {
      return CloudApi.v4RefreshPromise;
    }
    const refreshToken = AppStorage.get<string>(Constant.CLOUD_REFRESH_TOKEN) ?? '';
    if (refreshToken.length === 0) {
      return Promise.reject(new Error('V4 refresh token is missing'));
    }
    CloudApi.v4RefreshPromise = new Promise<string>((resolve: (token: string) => void,
      reject: (reason: Error) => void) => {
      nativeLoginWithRefreshToken(CloudApi.getBaseURL(), refreshToken, {
        onSuccess: (result: string[]) => {
          CloudApi.storeLoginResult(result);
          const token = result[Constant.LOGIN_RESULT_TOKEN_INDEX] ?? '';
          if (token.length > 0) {
            resolve(token);
          } else {
            reject(new Error('V4 access token refresh returned an empty token'));
          }
        },
        onFailure: (msg: string) => reject(new Error(msg))
      });
    }).finally(() => {
      CloudApi.v4RefreshPromise = undefined;
    });
    return CloudApi.v4RefreshPromise;
  }

  private static getV4ParentPath(uri: string): string {
    const schemeIndex = uri.indexOf('://');
    const pathStart = schemeIndex >= 0 ? uri.indexOf('/', schemeIndex + 3) : -1;
    const encodedPath = pathStart >= 0 ? uri.substring(pathStart) : uri;
    let decodedPath = encodedPath;
    try {
      decodedPath = decodeURIComponent(encodedPath);
    } catch (_) {
      decodedPath = encodedPath;
    }
    const lastSlash = decodedPath.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : decodedPath.substring(0, lastSlash);
  }

  static getThumb(id: string, callback?: HttpCallback<string>): void {
    nativeGetThumb(id, CloudApi.withApiLogging('getThumb', callback));
  }

  static getPreview(_id: string, _callback?: HttpCallback<ArrayBuffer>): void {
    // Preview fetch not supported via native layer
  }

  static getUserAvatar(_userId: string, _callback?: HttpCallback<ArrayBuffer>): void {
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
    const requestBody: V4DeleteFileRequest = {
      uris: [CloudApi.buildV4MyUri(remotePath)]
    };
    AppLogger.info(CLOUD_API_TAG, `lock-aware delete uri=${requestBody.uris[0]}`);
    CloudApi.requestV4FileMutation<FileLockConflict[]>('/api/v4/file',
      JSON.stringify(requestBody), cookie).then((response: BaseResponse<FileLockConflict[]>) => {
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
    const requestBody: V4UnlockFileRequest = { tokens: tokens };
    CloudApi.requestV4FileMutation<string>('/api/v4/file/lock', JSON.stringify(requestBody), cookie)
      .then((response: BaseResponse<string>) => {
        AppLogger.info(CLOUD_API_TAG, `force unlock response code=${response.code}, tokens=${tokens.length}`);
        if (response.code === 0) {
          callback.onSuccess(null);
        } else {
          callback.onFailure(`${response.code}: ${response.msg}`);
        }
      })
      .catch((err: Error) => callback.onFailure(err.message ?? String(err)));
  }

  private static buildV4MyUri(remotePath: string): string {
    const encodedPath = remotePath.split('/')
      .filter((segment: string) => segment.length > 0)
      .map((segment: string) => encodeURIComponent(segment))
      .join('/');
    return encodedPath.length > 0 ? `cloudreve://my/${encodedPath}` : 'cloudreve://my';
  }

  private static async requestV4FileMutation<T>(path: string, body: string,
    cookie: string): Promise<BaseResponse<T>> {
    let token = cookie.substring(Constant.CLOUD_V4_COOKIE_PREFIX.length);
    let response = await CloudApi.performV4FileMutation<T>(path, body, token);
    if (response.code !== 401) {
      return response;
    }
    AppLogger.info(CLOUD_API_TAG, `V4 mutation token expired path=${path}, refreshing before retry`);
    token = await CloudApi.refreshV4AccessToken();
    response = await CloudApi.performV4FileMutation<T>(path, body, token);
    return response;
  }

  private static async performV4FileMutation<T>(path: string, body: string,
    token: string): Promise<BaseResponse<T>> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${CloudApi.getApiBaseUrl()}${path}`, {
        method: http.RequestMethod.DELETE,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== Constant.HTTP_STATUS_OK) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return JSON.parse(response.result as string) as BaseResponse<T>;
    } finally {
      request.destroy();
    }
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
