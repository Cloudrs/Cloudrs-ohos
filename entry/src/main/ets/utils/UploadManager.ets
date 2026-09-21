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
import { ApiErrorUtil } from './ApiErrorUtil';
import UploadConflictResolver from './UploadConflictResolver';
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
      // 入队即读真实大小，排队中的任务也能显示 0B/14MB 而不是 0B/0B
      const sourceSize = FileSystemUtil.getFileSize(uri);
      const fakeItem: ObjectInfo = {
        id, name: fileName, path: remoteDirPath,
        thumb: false, size: sourceSize > 0 ? sourceSize : 0, type: 'file',
        date: '', create_date: '', source_enabled: false
      };
      const to = new TransportObject(fakeItem, uri, remotePath, id);
      to.type = TransportType.UPLOAD;
      to.state = FileModelState.WAITING;
      uploadObjects.addData(0, to);

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
        total: fakeItem.size,
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

  /**
   * 解除占用兜底路径专用：按 remote 路径把 pendingQueue 里未开跑的任务清掉，
   * 并把对应 transportObject 状态置 REMOVED（也顺带让 running 任务下轮 chunk 循环退出）。
   * 服务端 deleteUploadSession + TransferDatabase 记录 + cache 由调用方（UploadSessionRelief）
   * 统一处理，这里只负责内存队列的清扫，避免和 relief 路径互相踩到 pendingQueue。
   */
  dropByRemotePath(fileSet: Set<string>, dirPrefixes: string[]): void {
    const isMatch = (remote: string): boolean => {
      if (fileSet.has(remote)) {
        return true;
      }
      for (const prefix of dirPrefixes) {
        if (remote === prefix || remote.startsWith(prefix + '/')) {
          return true;
        }
      }
      return false;
    };
    this.pendingQueue = this.pendingQueue.filter((task: UploadTask) => {
      if (!isMatch(task.remotePath)) {
        return true;
      }
      task.transportObject.state = FileModelState.REMOVED;
      return false;
    });
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
          try {
            session = await this._createUploadSession(task.remotePath, fileName, transportObject.total, task.overwrite)
          } catch (firstErr) {
            // 两种冲突都可能是上一次失败留在服务端的占位，清掉后重试一次，让「重试」真正可用：
            //   40004 对象已存在——撞上的可能是用户的真实文件，所以只有本任务之前建过
            //     会话时才敢按那个 sessionId 去清，且不允许按路径删。
            //   40054 上传会话已存在——服务端只在同名对象带 UploadSessionID 时才回这个码，
            //     等于已经替我们确认了那是占位，所以哪怕本地 sessionId 已经丢了
            //     （进程被杀 / 记录被清 / 旧版本 V3 删会话是空操作），也能按路径清掉。
            const firstMsg = (firstErr as Error)?.message ?? String(firstErr)
            const staleRecord = TransferDatabase.listUploads().find(r => r.id === id)
            const staleSessionId = staleRecord?.sessionId ?? ''
            const isSessionConflict = ApiErrorUtil.isUploadSessionExisted(firstMsg)
            const isOwnObjectConflict = ApiErrorUtil.isObjectExisted(firstMsg) && staleSessionId.length > 0
            if (!isSessionConflict && !isOwnObjectConflict) {
              throw firstErr as Error
            }
            AppLogger.warn(TAG, `create session conflicted (${firstMsg}), clearing stale upload state`)
            const cleared = await UploadConflictResolver.clear(task.remotePath, staleSessionId, isSessionConflict)
            if (!cleared) {
              // 没清掉任何东西就重试，只会再撞一次同样的错，白白多一轮请求
              throw firstErr as Error
            }
            session = await this._createUploadSession(task.remotePath, fileName, transportObject.total, task.overwrite)
          }
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
          const msg = (err as Error)?.message ?? String(err)
          AppLogger.error(TAG, `create session failed: ${msg}`)
          // 会话尚未建立，本地缓存留着也无法续传，直接清掉
          FileSystemUtil.unlinkIfExists(cachePath)
          if (ApiErrorUtil.isNetworkMessage(msg)) {
            transportObject.statusText = '网络中断'
            transportObject.state = FileModelState.PAUSED
            TransferDatabase.updateUploadState(id, FileModelState.PAUSED)
          } else {
            transportObject.state = FileModelState.FAILED
            TransferDatabase.updateUploadState(id, FileModelState.FAILED)
          }
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
        if (ApiErrorUtil.isNetworkMessage(msg)) {
          // 网络中断：保留本地缓存与服务端会话，标 PAUSED，网络恢复后点「继续」从断点续传
          transportObject.statusText = '网络中断'
          transportObject.state = FileModelState.PAUSED
          TransferDatabase.updateUploadState(id, FileModelState.PAUSED)
        } else {
          // 真失败：删掉服务端会话，避免留下同名 0KB 占位脏文件，也保证重试能重建会话
          transportObject.state = FileModelState.FAILED
          TransferDatabase.updateUploadState(id, FileModelState.FAILED)
          const record = TransferDatabase.listUploads().find(r => r.id === id)
          if (record && record.sessionId.length > 0) {
            await this._deleteSessionQuiet(record.remotePath, record.sessionId)
          }
          FileSystemUtil.unlinkIfExists(cachePath)
        }
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
    // 不分片时以前挂一句"单块上传中"，是因为那条路径整块传完才回调一次进度，
    // 显示速度只会是个一直不动的 0B/s。现在它也是流式带进度的，让位给真实速度。
    transportObject.statusText = ''
    const useRemoteNode = uploadUrls.length === Constant.REMOTE_NODE_UPLOAD_URL_COUNT && !relay &&
      storagePolicyType === Constant.STORAGE_POLICY_REMOTE
    let offset = startOffset
    let index = startIndex
    let lastPersistAt = 0
    let lastUiUpdateAt = 0

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
      // native 的回调是按字节步长来的（每 4MB 一次），网速快时一秒十几次，
      // 列表里的百分比和字节数会跳得很碎。这里按时间收敛到一秒一次，和下载侧
      // request.agent 的回调节奏对齐。每块传完后还有一次不受闸门限制的
      // update(offset)，所以精确的字节数不会被丢掉。
      const onChunkProgress = (uploadedInChunk: number): void => {
        const now = new Date().getTime()
        if (now - lastUiUpdateAt < Constant.TRANSFER_PROGRESS_UI_INTERVAL_MS) {
          return
        }
        lastUiUpdateAt = now
        const current = Math.min(transportObject.total, chunkOffset + Math.max(0, uploadedInChunk))
        transportObject.update(current, FileModelState.RUNNING)
      }
      // 三条分支全部走带进度的接口。此前 chunkSize > 0（多分片）走的是无进度的
      // uploadLocalFileChunk，进度只在每块传完时跳一次，25MB 分片下用户盯着的
      // 就是一个长时间不动的百分比；而且它会把整块读进内存再交给 reqwest。
      const uploaded = useRemoteNode
        ? await CloudApi.uploadLocalFileChunkToUrlWithProgress(
          cachePath,
          uploadUrls[Constant.FIRST_ARRAY_INDEX],
          session.credential ?? '',
          index,
          chunkOffset,
          length,
          onChunkProgress
        )
        : await CloudApi.uploadLocalFileChunkWithProgress(
          cachePath,
          session.sessionId,
          index,
          chunkOffset,
          length,
          onChunkProgress
        )
      // 严格校验实际上传字节数，不能"没传够就当传满了"（相册备份侧同理）。
      // 本地缓存比会话登记的 total 短时，native 读到文件尾只会返回实际字节数，
      // 按 length 推 offset 会让循环正常结束、上报 COMPLETED，而服务端收到的
      // 字节数不足声明值，云端留下一个 0B 挂在"上传中"的空文件。
      // 宁可这次明确失败让用户看见。
      if (uploaded < length) {
        throw new Error(`分片 ${index} 只上传了 ${uploaded} / ${length} 字节` +
          `（本地文件比登记的 ${transportObject.total} 字节短），已中止以免在云端留下空文件`)
      }
      offset += uploaded
      index++
      lastUiUpdateAt = new Date().getTime()
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

  /** 删除服务端上传会话（连带清掉占位文件），失败只记日志不上抛。 */
  private _deleteSessionQuiet(remotePath: string, sessionId: string): Promise<void> {
    return new Promise<void>((resolve) => {
      CloudApi.deleteUploadSession(remotePath, sessionId, {
        onSuccess: () => {
          AppLogger.info(TAG, `deleted upload session ${sessionId}`)
          resolve()
        },
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `delete upload session failed: ${msg}`)
          resolve()
        }
      })
    })
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
