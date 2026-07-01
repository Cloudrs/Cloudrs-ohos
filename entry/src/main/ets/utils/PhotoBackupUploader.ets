import fs from '@ohos.file.fs';
import Constant from '../model/Constant';
import { CloudApi } from '../model/net/CloudApi';
import { HttpCallback, UploadRequestResponse } from '../model/net/ApiTypes';
import { ObjectUpload } from '../model/net/ObjectParam';
import PhotoBackupSessionStore, { PhotoBackupSessionData } from '../model/PhotoBackupSessionStore';
import { FileSystemUtil } from './FileSystemUtil';
import AppLogger from './AppLogger';

const TAG: string = 'PhotoBackupUploader';

export enum PhotoBackupUploadResult {
  COMPLETED = 'completed',
  PAUSED = 'paused',
  CANCELED = 'canceled'
}

export interface PhotoBackupUploadCallbacks {
  onSessionCreated?: (session: PhotoBackupSessionData) => void
  onProgress?: (uploadedBytes: number) => void
  isPauseRequested?: () => boolean
  isCancelRequested?: () => boolean
}

export class PhotoBackupUploadInterrupted extends Error {
  reason: PhotoBackupUploadResult;

  constructor(reason: PhotoBackupUploadResult) {
    super(reason);
    this.reason = reason;
  }
}

/**
 * 相册备份的分块上传器：把 Cloudreve upload session 的生命周期落到 ETS 层。
 *
 * 与文件 Tab 的 UploadManager 走同一底层 chunk API（uploadLocalFileChunk*），
 * 但不共享 TransferDatabase / TransportObject / LazyDataSource — 避免把相册备份
 * 塞进文件 Tab 的传输列表。sessionId 存到独立的 PhotoBackupSessionStore，
 * 让「暂停 / 关闭备份 / App 被杀 / 网络断」都能显式 deleteUploadSession，
 * 从根上避免 Cloudreve 侧 orphan session 占位导致父目录/文件删不掉。
 */
class PhotoBackupUploaderImpl {
  async uploadOne(
    itemId: string,
    cachePath: string,
    remotePath: string,
    fileName: string,
    total: number,
    lastModifiedMs: number,
    callbacks?: PhotoBackupUploadCallbacks
  ): Promise<PhotoBackupUploadResult> {
    this.throwIfInterrupted(callbacks);
    let session = await this.resolveSession(itemId, cachePath, remotePath, fileName, total, lastModifiedMs, callbacks);

    try {
      await this.uploadByChunks(itemId, cachePath, session, total, callbacks);
      PhotoBackupSessionStore.remove(itemId);
      return PhotoBackupUploadResult.COMPLETED;
    } catch (err) {
      if (err instanceof PhotoBackupUploadInterrupted) {
        if (err.reason === PhotoBackupUploadResult.CANCELED) {
          await this.deleteSession(remotePath, session.sessionId);
          PhotoBackupSessionStore.remove(itemId);
        }
        return err.reason;
      }
      // 真失败（网络 / 服务端）：主动 delete session 防 orphan，再向上抛
      await this.deleteSession(remotePath, session.sessionId);
      PhotoBackupSessionStore.remove(itemId);
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  /** 主动清理某个 item 的 session（用于外部检测到孤儿 / 关闭备份时批量清理） */
  async cleanupSession(data: PhotoBackupSessionData): Promise<void> {
    await this.deleteSession(data.remotePath, data.sessionId);
    if (data.cachePath.length > 0) {
      await FileSystemUtil.unlinkIfExists(data.cachePath);
    }
    PhotoBackupSessionStore.remove(data.itemId);
  }

  /** 清所有已知 session（关闭备份 / 用户切换等场景） */
  async cleanupAll(): Promise<void> {
    const all = PhotoBackupSessionStore.list();
    for (const data of all) {
      await this.deleteSession(data.remotePath, data.sessionId);
      if (data.cachePath.length > 0) {
        await FileSystemUtil.unlinkIfExists(data.cachePath);
      }
    }
    PhotoBackupSessionStore.clear();
  }

  private async resolveSession(
    itemId: string,
    cachePath: string,
    remotePath: string,
    fileName: string,
    total: number,
    lastModifiedMs: number,
    callbacks?: PhotoBackupUploadCallbacks
  ): Promise<PhotoBackupSessionData> {
    const existing = PhotoBackupSessionStore.get(itemId);
    const now = new Date().getTime();
    if (existing && !PhotoBackupSessionStore.isExpired(existing, now)
        && existing.remotePath === remotePath && existing.total === total
        && this.cacheFileExists(existing.cachePath)) {
      AppLogger.info(TAG, `resume session ${existing.sessionId} offset=${existing.offset} chunk=${existing.chunkIndex}`);
      return existing;
    }
    if (existing) {
      // 旧 session 不能续用（过期 / 路径变了 / cache 丢了）：先把服务端占位删掉
      await this.deleteSession(existing.remotePath, existing.sessionId);
      PhotoBackupSessionStore.remove(itemId);
    }
    this.throwIfInterrupted(callbacks);
    const created = await this.createSession(remotePath, fileName, total, lastModifiedMs);
    const data: PhotoBackupSessionData = {
      itemId,
      remotePath,
      cachePath,
      sessionId: created.sessionId,
      chunkSize: created.chunkSize,
      uploadUrls: created.uploadUrls ?? [],
      credential: created.credential ?? '',
      storagePolicyType: created.storagePolicyType ?? '',
      storagePolicyRelay: created.storagePolicyRelay ?? false,
      expiresAt: created.expires,
      total,
      offset: 0,
      chunkIndex: 0,
      updatedAt: now
    };
    PhotoBackupSessionStore.put(data);
    if (callbacks?.onSessionCreated) {
      callbacks.onSessionCreated(data);
    }
    return data;
  }

  private createSession(
    remotePath: string,
    fileName: string,
    total: number,
    lastModifiedMs: number
  ): Promise<UploadRequestResponse> {
    const request = new ObjectUpload(remotePath, total, fileName, '', lastModifiedMs > 0 ? lastModifiedMs : new Date().getTime());
    return new Promise<UploadRequestResponse>((resolve: (data: UploadRequestResponse) => void,
      reject: (err: Error) => void) => {
      const callback: HttpCallback<UploadRequestResponse> = {
        onSuccess: (data: UploadRequestResponse) => {
          if (!data.sessionId || data.sessionId.length === 0) {
            reject(new Error('创建上传会话失败：sessionId 为空'));
            return;
          }
          resolve(data);
        },
        onFailure: (msg: string) => reject(new Error(msg))
      };
      // 相册备份不做覆盖：同名文件已存在时 create 会失败，backupItem 上层的 remotePhotoExists 已提前拦截
      CloudApi.getUploadUri(request, callback, false);
    });
  }

  private async uploadByChunks(
    itemId: string,
    cachePath: string,
    session: PhotoBackupSessionData,
    total: number,
    callbacks?: PhotoBackupUploadCallbacks
  ): Promise<void> {
    const uploadUrls = session.uploadUrls;
    const relay = session.storagePolicyRelay;
    const storagePolicyType = session.storagePolicyType;
    // 只支持 local / remote 存储策略下的移动端分片；云存储 relay 需要 completeUrl 回调，暂不支持
    if (uploadUrls.length > 0 && !relay && storagePolicyType !== Constant.STORAGE_POLICY_LOCAL
        && storagePolicyType !== Constant.STORAGE_POLICY_REMOTE) {
      throw new Error(`当前存储策略(${storagePolicyType})需要云存储完成回调，暂不支持移动端分片上传`);
    }
    const chunkSize = session.chunkSize > 0 ? session.chunkSize : total;
    const useRemoteNode = uploadUrls.length === Constant.REMOTE_NODE_UPLOAD_URL_COUNT && !relay
      && storagePolicyType === Constant.STORAGE_POLICY_REMOTE;
    let offset = session.offset;
    let index = session.chunkIndex;
    let lastPersistAt = 0;

    while (offset < total) {
      this.throwIfInterrupted(callbacks, itemId, offset, index);
      const length = Math.min(chunkSize, total - offset);
      const chunkOffset = offset;
      const progressCallback = (uploadedInChunk: number): void => {
        if (callbacks?.onProgress) {
          const current = Math.min(total, chunkOffset + Math.max(0, uploadedInChunk));
          callbacks.onProgress(current);
        }
      };
      const uploaded = useRemoteNode
        ? await CloudApi.uploadLocalFileChunkToUrlWithProgress(
          cachePath, uploadUrls[Constant.FIRST_ARRAY_INDEX], session.credential,
          index, chunkOffset, length, progressCallback)
        : session.chunkSize <= 0
          ? await CloudApi.uploadLocalFileChunkWithProgress(
            cachePath, session.sessionId, index, chunkOffset, length, progressCallback)
          : await CloudApi.uploadLocalFileChunk(cachePath, session.sessionId, index, chunkOffset, length);
      offset += uploaded > 0 ? uploaded : length;
      index++;
      if (callbacks?.onProgress) {
        callbacks.onProgress(Math.min(offset, total));
      }
      const now = new Date().getTime();
      if (offset >= total || now - lastPersistAt > Constant.TRANSFER_PERSIST_INTERVAL_MS) {
        PhotoBackupSessionStore.updateProgress(itemId, offset, index);
        lastPersistAt = now;
      }
    }
  }

  private deleteSession(remotePath: string, sessionId: string): Promise<void> {
    if (!sessionId || sessionId.length === 0) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      CloudApi.deleteUploadSession(remotePath, sessionId, {
        onSuccess: () => {
          AppLogger.info(TAG, `deleted upload session ${sessionId} @ ${remotePath}`);
          resolve();
        },
        onFailure: (msg: string) => {
          // 服务端可能已经把它清了（404），或者网络不通；下次启动扫孤儿时还会再试
          AppLogger.warn(TAG, `delete upload session failed ${sessionId}: ${msg}`);
          resolve();
        }
      });
    });
  }

  /**
   * fs.accessSync 在 ArkTS 里对不存在文件会抛异常（不同 API 版本行为不完全一致）。
   * 用 try-catch 包一层保稳，异常一律视作文件不存在，让 resolveSession 走 create 新 session 分支——
   * 而不是让整个 uploadOne 因这一次 accessSync 抛出而挂掉。
   */
  private cacheFileExists(path: string): boolean {
    if (!path || path.length === 0) {
      return false;
    }
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private throwIfInterrupted(callbacks?: PhotoBackupUploadCallbacks,
    itemId?: string, offset?: number, chunkIndex?: number): void {
    if (callbacks?.isCancelRequested && callbacks.isCancelRequested()) {
      throw new PhotoBackupUploadInterrupted(PhotoBackupUploadResult.CANCELED);
    }
    if (callbacks?.isPauseRequested && callbacks.isPauseRequested()) {
      if (itemId !== undefined && offset !== undefined && chunkIndex !== undefined) {
        PhotoBackupSessionStore.updateProgress(itemId, offset, chunkIndex);
      }
      throw new PhotoBackupUploadInterrupted(PhotoBackupUploadResult.PAUSED);
    }
  }
}

const PhotoBackupUploader = new PhotoBackupUploaderImpl();
export default PhotoBackupUploader;
