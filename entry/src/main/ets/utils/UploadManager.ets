import fs from '@ohos.file.fs';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { CloudApi } from '../model/net/CloudApi';
import { FileModelState } from '../model/FileModel';
import { HttpCallback, ObjectInfo, UploadRequestResponse } from '../model/net/ApiTypes';
import { ObjectUpload } from '../model/net/ObjectParam';
import { TransportObject, TransportType } from '../model/TransportObject';
import LazyDataSource from './LazyDataSource';
import UserPreferences from '../model/UserPreferences';
import Constant from '../model/Constant';
import { FileSystemUtil } from './FileSystemUtil';

const TAG = 'UploadManager';
interface UploadTask {
  uri: string
  remotePath: string
  overwrite: boolean
  context: common.UIAbilityContext
  transportObject: TransportObject
  onDirChanged: () => void
  onTaskEnd?: () => void
}

class UploadManager {
  private pendingQueue: UploadTask[] = [];
  private _activeCount: number = 0;
  private _taskCounter: number = 0;

  extractFileName(uri: string): string {
    try {
      return new fileUri.FileUri(uri).name;
    } catch {
      return `upload_${new Date().getTime()}`;
    }
  }

  enqueue(
    uris: string[],
    remoteDirPath: string,
    overwrite: boolean,
    context: common.UIAbilityContext,
    uploadObjects: LazyDataSource<TransportObject>,
    onDirChanged: () => void,
    onTaskEnd?: () => void
  ): void {
    uris.forEach(uri => {
      const fileName = this.extractFileName(uri);
      const sep = remoteDirPath.endsWith('/') ? '' : '/';
      const remotePath = `${remoteDirPath}${sep}${fileName}`;
      const fakeItem: ObjectInfo = {
        id: '', name: fileName, path: remoteDirPath,
        thumb: false, size: 0, type: 'file',
        date: '', create_date: '', source_enabled: false
      };
      const to = new TransportObject(fakeItem, uri, remotePath);
      to.type = TransportType.UPLOAD;
      to.state = FileModelState.WAITING;
      uploadObjects.pushData(to);
      this.pendingQueue.push({
        uri, remotePath, overwrite, context,
        transportObject: to, onDirChanged, onTaskEnd
      });
    });
    this._tryFlush();
  }

  private _tryFlush(): void {
    const raw = UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.UPLOAD_MAX_CONCURRENT,
      3
    );
    const maxConcurrent = Math.max(1, Math.min(10, typeof (raw as number) === 'number' ? (raw as number) : 3));
    while (this._activeCount < maxConcurrent && this.pendingQueue.length > 0) {
      const task = this.pendingQueue.shift()!;
      this._runTask(task);
    }
  }

  private async _runTask(task: UploadTask): Promise<void> {
    this._activeCount++;
    try {
      const uri = task.uri;
      const remotePath = task.remotePath;
      const overwrite = task.overwrite;
      const context = task.context;
      const transportObject = task.transportObject;
      const onDirChanged = task.onDirChanged;
      const onTaskEnd = task.onTaskEnd;
      const fileName = this.extractFileName(uri);
      const cachePath = `${context.cacheDir}/upload_${new Date().getTime()}_${++this._taskCounter}_${fileName}`;

      try {
        await FileSystemUtil.copyUriToPath(uri, cachePath);
      } catch (err) {
        console.error(TAG, `copy to cache failed: ${(err as Error)?.message ?? err}`);
        FileSystemUtil.unlinkIfExists(cachePath);
        transportObject.state = FileModelState.FAILED;
        this._finish(onTaskEnd);
        return;
      }

      try {
        const stat = fs.statSync(cachePath);
        transportObject.item.size = stat.size;
        transportObject.total = stat.size;
      } catch {
        // size stays 0, not critical
      }
      transportObject.update(0, FileModelState.RUNNING);
      transportObject.statusText = '';

      try {
        await this._uploadLocalFileByChunks(cachePath, remotePath, fileName, overwrite, transportObject);
        transportObject.trans = transportObject.total;
        transportObject.state = FileModelState.COMPLETED;
        transportObject.progress = 100;
        transportObject.speed = 0;
        FileSystemUtil.unlinkIfExists(cachePath);
        onDirChanged();
        this._finish(onTaskEnd);
      } catch (err) {
        const msg = (err as Error)?.message ?? String(err);
        console.error(TAG, `upload failed: ${msg}`);
        transportObject.speed = 0;
        transportObject.state = FileModelState.FAILED;
        FileSystemUtil.unlinkIfExists(cachePath);
        this._finish(onTaskEnd);
      }
    } catch (unexpected) {
      console.error(TAG, `unexpected error in _runTask: ${(unexpected as Error)?.message ?? unexpected}`);
      task.transportObject.state = FileModelState.FAILED;
      this._finish(task.onTaskEnd);
    }
  }

  private async _uploadLocalFileByChunks(
    cachePath: string,
    remotePath: string,
    fileName: string,
    overwrite: boolean,
    transportObject: TransportObject
  ): Promise<void> {
    const session = await this._createUploadSession(remotePath, fileName, transportObject.total, overwrite);
    const uploadUrls = session.uploadUrls ?? [];
    const completeUrl = session.completeUrl ?? '';
    const storagePolicyType = session.storagePolicyType ?? '';
    const relay = session.storagePolicyRelay ?? false;
    console.info(TAG, `upload session: chunkSize=${session.chunkSize}, uploadUrls=${uploadUrls.length}, completeUrl=${completeUrl}, policy=${storagePolicyType}, relay=${relay}`);

    if (completeUrl.length > 0 && !relay && storagePolicyType !== 'local' && storagePolicyType !== 'remote') {
      throw new Error(`当前存储策略(${storagePolicyType})需要云存储完成回调，暂不支持移动端分片上传`);
    }

    const chunkSize = session.chunkSize > 0 ? session.chunkSize : transportObject.total;
    if (session.chunkSize <= 0) {
      transportObject.statusText = '单块上传中';
    } else {
      transportObject.statusText = '';
    }
    const useRemoteNode = uploadUrls.length === 1 && !relay && storagePolicyType === 'remote';
    let offset = 0;
    let index = 0;

    while (offset < transportObject.total) {
      const length = Math.min(chunkSize, transportObject.total - offset);
      const chunkOffset = offset;
      const uploaded = useRemoteNode
        ? await CloudApi.uploadLocalFileChunkToUrl(cachePath, uploadUrls[0], session.credential ?? '', index, chunkOffset, length)
        : session.chunkSize <= 0
          ? await CloudApi.uploadLocalFileChunkWithProgress(
            cachePath,
            session.sessionId,
            index,
            chunkOffset,
            length,
            (uploadedInChunk: number) => {
              const current = Math.min(transportObject.total, chunkOffset + Math.max(0, uploadedInChunk));
              transportObject.update(current, FileModelState.RUNNING);
            }
          )
          : await CloudApi.uploadLocalFileChunk(cachePath, session.sessionId, index, chunkOffset, length);
      offset += uploaded > 0 ? uploaded : length;
      transportObject.update(offset, FileModelState.RUNNING);
      if (offset >= transportObject.total) {
        transportObject.statusText = '';
      }
      index++;
    }
  }

  private _createUploadSession(
    remotePath: string,
    fileName: string,
    size: number,
    overwrite: boolean
  ): Promise<UploadRequestResponse> {
    const request = new ObjectUpload(remotePath, size, fileName, '', new Date().getTime());
    return new Promise<UploadRequestResponse>((resolve, reject) => {
      const callback: HttpCallback<UploadRequestResponse> = {
        onSuccess: (data: UploadRequestResponse) => {
          if (!data.sessionId) {
            reject(new Error('创建上传会话失败：sessionId 为空'));
            return;
          }
          resolve(data);
        },
        onFailure: (msg: string) => reject(new Error(msg))
      };
      CloudApi.getUploadUri(request, callback, overwrite);
    });
  }

  private _uploadLocalFileCompat(cachePath: string, remotePath: string, overwrite: boolean): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      CloudApi.uploadLocalFile(cachePath, remotePath, overwrite, {
        onSuccess: () => resolve(),
        onFailure: (msg: string) => reject(new Error(msg))
      });
    });
  }

  private _finish(onTaskEnd?: () => void): void {
    this._activeCount--;
    this._tryFlush();
    if (onTaskEnd) {
      onTaskEnd();
    }
  }
}

export const uploadManager = new UploadManager();
