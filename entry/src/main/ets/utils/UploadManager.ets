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
import AppLogger from './AppLogger';
import TransferDatabase, { UploadRecord } from '../model/TransferDatabase';

const TAG = 'UploadManager';
interface UploadTask {
  id: string
  uri: string
  remotePath: string
  fileName: string
  overwrite: boolean
  context: common.UIAbilityContext
  transportObject: TransportObject
  onDirChanged: () => void
  onTaskEnd?: () => void
  // 续传字段
  resumeCachePath?: string
  resumeSession?: UploadRequestResponse
  resumeOffset?: number
  resumeChunkIndex?: number
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

  private makeUploadId(remotePath: string): string {
    return remotePath
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
      const id = this.makeUploadId(remotePath);
      const fakeItem: ObjectInfo = {
        id, name: fileName, path: remoteDirPath,
        thumb: false, size: 0, type: 'file',
        date: '', create_date: '', source_enabled: false
      };
      const to = new TransportObject(fakeItem, uri, remotePath, id);
      to.type = TransportType.UPLOAD;
      to.state = FileModelState.WAITING;
      uploadObjects.pushData(to);

      const now = new Date().getTime();
      TransferDatabase.upsertUpload({
        id,
        uri,
        remotePath,
        fileName,
        overwrite,
        sessionId: '',
        chunkSize: 0,
        uploadUrls: [],
        credential: '',
        storagePolicyType: '',
        storagePolicyRelay: false,
        sessionExpiresAt: 0,
        total: 0,
        offset: 0,
        chunkIndex: 0,
        cachePath: '',
        state: FileModelState.WAITING,
        createdAt: now
      });

      this.pendingQueue.push({
        id, uri, remotePath, fileName, overwrite, context,
        transportObject: to, onDirChanged, onTaskEnd
      });
    });
    this._tryFlush();
  }

  resume(
    transportObject: TransportObject,
    context: common.UIAbilityContext,
    onDirChanged: () => void,
    onTaskEnd?: () => void
  ): void {
    const id = transportObject.id
    const records = TransferDatabase.listUploads()
    const record = records.find(r => r.id === id)
    if (!record) {
      AppLogger.warn(TAG, `resume: record not found, id=${id}`)
      transportObject.state = FileModelState.FAILED
      return
    }

    transportObject.state = FileModelState.WAITING
    transportObject.statusText = '等待中'
    TransferDatabase.updateUploadState(id, FileModelState.WAITING)

    const expiresMs = record.sessionExpiresAt < 1e12
      ? record.sessionExpiresAt * 1000
      : record.sessionExpiresAt
    const sessionAlive = record.sessionId.length > 0 &&
      record.cachePath.length > 0 &&
      expiresMs > new Date().getTime() &&
      fs.accessSync(record.cachePath)

    if (sessionAlive) {
      AppLogger.info(TAG, `resume from offset=${record.offset} chunk=${record.chunkIndex}`)
      const session: UploadRequestResponse = {
        sessionId: record.sessionId,
        chunkSize: record.chunkSize,
        expires: record.sessionExpiresAt,
        uploadUrls: record.uploadUrls,
        credential: record.credential,
        completeUrl: '',
        storagePolicyType: record.storagePolicyType,
        storagePolicyRelay: record.storagePolicyRelay
      }
      this.pendingQueue.push({
        id,
        uri: record.uri,
        remotePath: record.remotePath,
        fileName: record.fileName,
        overwrite: record.overwrite,
        context,
        transportObject,
        onDirChanged,
        onTaskEnd,
        resumeCachePath: record.cachePath,
        resumeSession: session,
        resumeOffset: record.offset,
        resumeChunkIndex: record.chunkIndex
      })
    } else {
      AppLogger.info(TAG, `resume: session expired or cache missing, restart from scratch`)
      if (record.cachePath.length > 0) {
        FileSystemUtil.unlinkIfExists(record.cachePath)
      }
      transportObject.trans = 0
      transportObject.progress = 0
      this.pendingQueue.push({
        id,
        uri: record.uri,
        remotePath: record.remotePath,
        fileName: record.fileName,
        overwrite: record.overwrite,
        context,
        transportObject,
        onDirChanged,
        onTaskEnd
      })
    }
    this._tryFlush()
  }

  restoreFromPersistence(uploadObjects: LazyDataSource<TransportObject>): void {
    const records = TransferDatabase.listUploads()
    records.forEach(record => {
      const fakeItem: ObjectInfo = {
        id: record.id,
        name: record.fileName,
        path: record.remotePath.substring(0, record.remotePath.lastIndexOf('/')) || '/',
        thumb: false,
        size: record.total,
        type: 'file',
        date: '',
        create_date: '',
        source_enabled: false
      }
      const to = new TransportObject(fakeItem, record.uri, record.remotePath, record.id)
      to.type = TransportType.UPLOAD
      to.trans = record.offset
      to.total = record.total
      to.progress = record.total > 0 ?
        Math.min(Constant.BACKGROUND_TASK_COMPLETE_PERCENT,
          Math.floor(record.offset / record.total * Constant.BACKGROUND_TASK_COMPLETE_PERCENT)) : 0
      to.state = (record.state === FileModelState.COMPLETED || record.state === FileModelState.FAILED)
        ? record.state
        : FileModelState.PAUSED
      uploadObjects.pushData(to)
    })
  }

  cancel(transportObject: TransportObject): void {
    transportObject.state = FileModelState.REMOVED
    const records = TransferDatabase.listUploads()
    const record = records.find(r => r.id === transportObject.id)
    if (record) {
      if (record.cachePath.length > 0) {
        FileSystemUtil.unlinkIfExists(record.cachePath)
      }
      if (record.sessionId.length > 0) {
        CloudApi.deleteUploadSession(record.remotePath, record.sessionId, {
          onSuccess: () => AppLogger.info(TAG, `cancelled upload session ${record.sessionId}`),
          onFailure: (msg) => AppLogger.warn(TAG, `cancel upload session failed: ${msg}`)
        })
      }
    }
    TransferDatabase.deleteUpload(transportObject.id)
  }

  private _tryFlush(): void {
    const raw = UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.UPLOAD_MAX_CONCURRENT,
      Constant.UPLOAD_CONCURRENT_DEFAULT
    );
    const maxConcurrent = Math.max(
      Constant.UPLOAD_CONCURRENT_MIN,
      Math.min(
        Constant.UPLOAD_CONCURRENT_MAX,
        typeof (raw as number) === 'number' ? (raw as number) : Constant.UPLOAD_CONCURRENT_DEFAULT
      )
    );
    while (this._activeCount < maxConcurrent && this.pendingQueue.length > 0) {
      const task = this.pendingQueue.shift()!;
      this._runTask(task);
    }
  }

  private async _runTask(task: UploadTask): Promise<void> {
    this._activeCount++;
    try {
      const id = task.id
      const transportObject = task.transportObject
      const context = task.context
      const onDirChanged = task.onDirChanged
      const onTaskEnd = task.onTaskEnd
      const fileName = task.fileName

      let cachePath = task.resumeCachePath ?? ''
      let session = task.resumeSession
      let startOffset = task.resumeOffset ?? 0
      let startIndex = task.resumeChunkIndex ?? 0

      // Clear any lingering PAUSED/STOPPED state before running. update() suppresses
      // RUNNING transitions while a user pause is in effect (so in-flight chunk callbacks
      // can't override the pause), but that gate must be reset here on resume.
      if (transportObject.state !== FileModelState.REMOVED &&
        transportObject.state !== FileModelState.COMPLETED &&
        transportObject.state !== FileModelState.FAILED) {
        transportObject.state = FileModelState.RUNNING
      }

      if (cachePath.length === 0) {
        cachePath = `${context.cacheDir}/upload_${new Date().getTime()}_${++this._taskCounter}_${fileName}`
        try {
          const sourceSize = FileSystemUtil.getFileSize(task.uri)
          if (sourceSize > 0) {
            transportObject.item.size = sourceSize
            transportObject.total = sourceSize
          }
          transportObject.statusText = '准备上传'
          transportObject.update(0, FileModelState.RUNNING)
          await FileSystemUtil.copyUriToPathFast(task.uri, cachePath)
        } catch (err) {
          AppLogger.error(TAG, `copy to cache failed: ${(err as Error)?.message ?? err}`)
          FileSystemUtil.unlinkIfExists(cachePath)
          transportObject.statusText = ''
          transportObject.state = FileModelState.FAILED
          TransferDatabase.updateUploadState(id, FileModelState.FAILED)
          this._finish(onTaskEnd)
          return
        }

        try {
          const stat = fs.statSync(cachePath)
          transportObject.item.size = stat.size
          transportObject.total = stat.size
        } catch {}
        transportObject.trans = 0
        transportObject.progress = 0
        transportObject.speed = 0
        transportObject.update(0, FileModelState.RUNNING)
        transportObject.statusText = ''
      } else {
        transportObject.update(startOffset, FileModelState.RUNNING)
        transportObject.statusText = ''
      }

      if (!session) {
        try {
          session = await this._createUploadSession(task.remotePath, fileName, transportObject.total, task.overwrite)
          TransferDatabase.updateUploadSession(
            id,
            session.sessionId,
            session.chunkSize,
            session.uploadUrls ?? [],
            session.credential ?? '',
            session.storagePolicyType ?? '',
            session.storagePolicyRelay ?? false,
            session.expires,
            cachePath,
            transportObject.total
          )
        } catch (err) {
          AppLogger.error(TAG, `create session failed: ${(err as Error)?.message ?? err}`)
          transportObject.state = FileModelState.FAILED
          TransferDatabase.updateUploadState(id, FileModelState.FAILED)
          FileSystemUtil.unlinkIfExists(cachePath)
          this._finish(onTaskEnd)
          return
        }
      }

      try {
        const finished = await this._uploadLocalFileByChunks(
          cachePath, task.remotePath, fileName, task.overwrite,
          transportObject, session, startOffset, startIndex, id
        )
        if (!finished) {
          this._finish(onTaskEnd)
          return
        }
        transportObject.trans = transportObject.total
        transportObject.state = FileModelState.COMPLETED
        transportObject.progress = Constant.BACKGROUND_TASK_COMPLETE_PERCENT
        transportObject.speed = 0
        TransferDatabase.updateUploadProgress(id, transportObject.total, startIndex, FileModelState.COMPLETED)
        FileSystemUtil.unlinkIfExists(cachePath)
        onDirChanged()
        this._finish(onTaskEnd)
      } catch (err) {
        const msg = (err as Error)?.message ?? String(err)
        AppLogger.error(TAG, `upload failed: ${msg}`)
        transportObject.speed = 0
        transportObject.state = FileModelState.FAILED
        TransferDatabase.updateUploadState(id, FileModelState.FAILED)
        FileSystemUtil.unlinkIfExists(cachePath)
        this._finish(onTaskEnd)
      }
    } catch (unexpected) {
      AppLogger.error(TAG, `unexpected error in _runTask: ${(unexpected as Error)?.message ?? unexpected}`)
      task.transportObject.state = FileModelState.FAILED
      TransferDatabase.updateUploadState(task.id, FileModelState.FAILED)
      this._finish(task.onTaskEnd)
    }
  }

  private async _uploadLocalFileByChunks(
    cachePath: string,
    remotePath: string,
    fileName: string,
    overwrite: boolean,
    transportObject: TransportObject,
    session: UploadRequestResponse,
    startOffset: number,
    startIndex: number,
    id: string
  ): Promise<boolean> {
    const uploadUrls = session.uploadUrls ?? []
    const completeUrl = session.completeUrl ?? ''
    const storagePolicyType = session.storagePolicyType ?? ''
    const relay = session.storagePolicyRelay ?? false
    console.info(TAG, `upload session: chunkSize=${session.chunkSize}, uploadUrls=${uploadUrls.length}, completeUrl=${completeUrl}, policy=${storagePolicyType}, relay=${relay}`)

    if (completeUrl.length > 0 && !relay && storagePolicyType !== Constant.STORAGE_POLICY_LOCAL &&
      storagePolicyType !== Constant.STORAGE_POLICY_REMOTE) {
      throw new Error(`当前存储策略(${storagePolicyType})需要云存储完成回调，暂不支持移动端分片上传`)
    }

    const chunkSize = session.chunkSize > 0 ? session.chunkSize : transportObject.total
    if (session.chunkSize <= 0) {
      transportObject.statusText = '单块上传中'
    } else {
      transportObject.statusText = ''
    }
    const useRemoteNode = uploadUrls.length === Constant.REMOTE_NODE_UPLOAD_URL_COUNT && !relay &&
      storagePolicyType === Constant.STORAGE_POLICY_REMOTE
    let offset = startOffset
    let index = startIndex
    let lastPersistAt = 0

    while (offset < transportObject.total) {
      if (transportObject.state === FileModelState.PAUSED ||
        transportObject.state === FileModelState.STOPPED ||
        transportObject.state === FileModelState.REMOVED) {
        AppLogger.info(TAG, `upload interrupted at offset=${offset}, chunk=${index}, state=${transportObject.state}`)
        if (transportObject.state !== FileModelState.REMOVED) {
          TransferDatabase.updateUploadProgress(id, offset, index, FileModelState.PAUSED)
        }
        return false
      }

      const length = Math.min(chunkSize, transportObject.total - offset)
      const chunkOffset = offset
      const uploaded = useRemoteNode
        ? await CloudApi.uploadLocalFileChunkToUrlWithProgress(
          cachePath,
          uploadUrls[Constant.FIRST_ARRAY_INDEX],
          session.credential ?? '',
          index,
          chunkOffset,
          length,
          (uploadedInChunk: number) => {
            const current = Math.min(transportObject.total, chunkOffset + Math.max(0, uploadedInChunk))
            transportObject.update(current, FileModelState.RUNNING)
          }
        )
        : session.chunkSize <= 0
          ? await CloudApi.uploadLocalFileChunkWithProgress(
            cachePath,
            session.sessionId,
            index,
            chunkOffset,
            length,
            (uploadedInChunk: number) => {
              const current = Math.min(transportObject.total, chunkOffset + Math.max(0, uploadedInChunk))
              transportObject.update(current, FileModelState.RUNNING)
            }
          )
          : await CloudApi.uploadLocalFileChunk(cachePath, session.sessionId, index, chunkOffset, length)
      offset += uploaded > 0 ? uploaded : length
      index++
      transportObject.update(offset, FileModelState.RUNNING)

      const now = new Date().getTime()
      if (offset >= transportObject.total || now - lastPersistAt > Constant.TRANSFER_PERSIST_INTERVAL_MS) {
        TransferDatabase.updateUploadProgress(id, offset, index, FileModelState.RUNNING)
        lastPersistAt = now
      }

      if (offset >= transportObject.total) {
        transportObject.statusText = ''
      }
    }
    return true
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

  private _finish(onTaskEnd?: () => void): void {
    this._activeCount--;
    this._tryFlush();
    if (onTaskEnd) {
      onTaskEnd();
    }
  }
}

export const uploadManager = new UploadManager();
