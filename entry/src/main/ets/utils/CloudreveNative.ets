import {
  setBaseUrl, getBaseUrl, setCookie,
  ping, getSiteConfig, login,
  getUserStorage, getUserSetting,
  getDirectory, getObjectDetail,
  deleteObjects, moveObjects, copyObjects,
  renameObject, newDirectory, newFile,
  getDownloadUri, getUploadUri,
  aria2Downloading, aria2Finished,
  aria2CreateTask, aria2DeleteTask,
  getUserTasks
} from 'libcloudreve.so';
import { HttpCallback } from '../model/net/ApiTypes';

export { setBaseUrl, getBaseUrl, setCookie };

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

export function nativePing(callback?: HttpCallback<string>): void {
  wrap(ping(), callback);
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

export function nativeGetUserStorage<T>(callback?: HttpCallback<T>): void {
  wrapJson(getUserStorage(), callback);
}

export function nativeGetUserSetting<T>(callback?: HttpCallback<T>): void {
  wrapJson(getUserSetting(), callback);
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

export function nativeMoveObjects(items: string[], dirs: string[], dst: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  moveObjects(items, dirs, dst)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message ?? String(err)));
}

export function nativeCopyObjects(items: string[], dirs: string[], dst: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  copyObjects(items, dirs, dst)
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
