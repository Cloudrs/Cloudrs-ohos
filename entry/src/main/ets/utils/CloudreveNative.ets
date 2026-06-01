import {
  init, restoreSession,
  getSiteConfig, login, login2fa, loginWithRefreshToken,
  getUserStorage, getUserSetting,
  getUserAvatar,
  getDirectory, getObjectDetail,
  deleteObjects, moveObjects, copyObjects,
  renameObject, newDirectory, newFile,
  getDownloadUri, getUploadUri, uploadLocalFile, uploadLocalFileChunk, uploadLocalFileChunkWithProgress,
  uploadLocalFileChunkToUrl, uploadLocalFileChunkToUrlWithProgress,
  aria2Downloading, aria2Finished,
  aria2CreateTask, aria2DeleteTask,
  getUserTasks,
  getThumb,
  createShareLink, listShareLinks, deleteShareLink,
  createArchive, extractArchive
} from 'libcloudreve.so';
import { HttpCallback } from '../model/net/ApiTypes';

function wrap<T>(promise: Promise<T>, callback?: HttpCallback<T>): void {
  if (callback?.onStart) { callback.onStart(); }
  promise
    .then((data: T) => callback?.onSuccess(data))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

function wrapJson<T>(promise: Promise<string>, callback?: HttpCallback<T>): void {
  if (callback?.onStart) { callback.onStart(); }
  promise
    .then((json: string) => callback?.onSuccess(JSON.parse(json) as T))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeInit(url: string, callback?: HttpCallback<string>): void {
  wrap(init(url), callback);
}

export function nativeRestoreSession(url: string, accessToken: string, refreshToken: string, isV3: boolean): void {
  restoreSession(url, accessToken, refreshToken, isV3);
}

export function nativeGetSiteConfig<T>(callback?: HttpCallback<T>): void {
  wrapJson(getSiteConfig(), callback);
}

export function nativeLogin(
  username: string,
  password: string,
  callback?: HttpCallback<string[]>
): void {
  wrap(login(username, password), callback);
}

export function nativeLogin2fa(
  code: string,
  callback?: HttpCallback<string[]>
): void {
  wrap(login2fa(code), callback);
}

export function nativeLoginWithRefreshToken(
  baseUrl: string,
  refreshToken: string,
  callback?: HttpCallback<string[]>
): void {
  wrap(loginWithRefreshToken(baseUrl, refreshToken), callback);
}

export function nativeGetUserStorage<T>(callback?: HttpCallback<T>): void {
  wrapJson(getUserStorage(), callback);
}

export function nativeGetUserSetting<T>(callback?: HttpCallback<T>): void {
  wrapJson(getUserSetting(), callback);
}

export function nativeGetUserAvatar(userId: string, callback?: HttpCallback<ArrayBuffer>): void {
  wrap(getUserAvatar(userId), callback);
}

export function nativeGetDirectory<T>(path: string, callback?: HttpCallback<T>): void {
  wrapJson(getDirectory(path), callback);
}

export function nativeGetObjectDetail<T>(id: string, isFolder: boolean, callback?: HttpCallback<T>): void {
  wrapJson(getObjectDetail(id, isFolder), callback);
}

export function nativeDeleteObjects(items: string[], dirs: string[], callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  deleteObjects(items, dirs)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeMoveObjects(items: string[], dirs: string[], srcDir: string, dst: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  moveObjects(items, dirs, srcDir, dst)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeCopyObjects(items: string[], dirs: string[], srcDir: string, dst: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  copyObjects(items, dirs, srcDir, dst)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeRenameObject(id: string, newName: string, isDir: boolean, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  renameObject(id, newName, isDir)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeNewDirectory(path: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  newDirectory(path)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeNewFile(path: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  newFile(path)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeGetDownloadUri(id: string, callback?: HttpCallback<string>): void {
  wrap(getDownloadUri(id), callback);
}

export function nativeGetUploadUri<T>(
  path: string, size: number, name: string,
  lastModified: number, mimeType: string, chunkSize: number,
  callback?: HttpCallback<T>
): void {
  wrapJson(getUploadUri(path, size, name, lastModified, mimeType, chunkSize), callback);
}

export function nativeUploadLocalFile(
  localPath: string,
  remotePath: string,
  overwrite: boolean,
  callback?: HttpCallback<null>
): void {
  if (callback?.onStart) { callback.onStart(); }
  uploadLocalFile(localPath, remotePath, overwrite)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeUploadLocalFileChunk(
  localPath: string,
  sessionId: string,
  index: number,
  offset: number,
  length: number
): Promise<number> {
  return uploadLocalFileChunk(localPath, sessionId, index, offset, length);
}

export function nativeUploadLocalFileChunkWithProgress(
  localPath: string,
  sessionId: string,
  index: number,
  offset: number,
  length: number,
  progress: (uploaded: number) => void
): Promise<number> {
  return uploadLocalFileChunkWithProgress(localPath, sessionId, index, offset, length, progress);
}

export function nativeUploadLocalFileChunkToUrl(
  localPath: string,
  uploadUrl: string,
  credential: string,
  index: number,
  offset: number,
  length: number
): Promise<number> {
  return uploadLocalFileChunkToUrl(localPath, uploadUrl, credential, index, offset, length);
}

export function nativeUploadLocalFileChunkToUrlWithProgress(
  localPath: string,
  uploadUrl: string,
  credential: string,
  index: number,
  offset: number,
  length: number,
  progress: (uploaded: number) => void
): Promise<number> {
  return uploadLocalFileChunkToUrlWithProgress(localPath, uploadUrl, credential, index, offset, length, progress);
}

export function nativeAria2Downloading<T>(callback?: HttpCallback<T>): void {
  wrapJson(aria2Downloading(), callback);
}

export function nativeAria2Finished<T>(page: number, callback?: HttpCallback<T>): void {
  wrapJson(aria2Finished(page), callback);
}

export function nativeAria2CreateTask(dst: string, urls: string[], callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  aria2CreateTask(dst, urls)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeAria2DeleteTask(gid: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  aria2DeleteTask(gid)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeGetUserTasks<T>(page: number, callback?: HttpCallback<T>): void {
  wrapJson(getUserTasks(page), callback);
}

export function nativeGetThumb(id: string, callback?: HttpCallback<string>): void {
  if (callback?.onStart) { callback.onStart(); }
  getThumb(id)
    .then((url: string) => callback?.onSuccess(url))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeCreateShareLink(path: string, expireDays: number, password: string, callback?: HttpCallback<string>): void {
  wrap(createShareLink(path, expireDays, password), callback);
}

export function nativeListShareLinks<T>(callback?: HttpCallback<T>): void {
  wrapJson(listShareLinks(), callback);
}

export function nativeDeleteShareLink(shareId: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  deleteShareLink(shareId)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeCreateArchive(srcPaths: string[], dstPath: string, callback?: HttpCallback<string>): void {
  wrap(createArchive(srcPaths, dstPath), callback);
}

export function nativeExtractArchive(srcPaths: string[], dstPath: string, callback?: HttpCallback<string>): void {
  wrap(extractArchive(srcPaths, dstPath), callback);
}
