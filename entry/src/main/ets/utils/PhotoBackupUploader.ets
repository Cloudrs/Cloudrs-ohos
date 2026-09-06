import Constant from '../model/Constant';
import { CloudApi } from '../model/net/CloudApi';
import { HttpCallback, UploadRequestResponse } from '../model/net/ApiTypes';
import { ObjectUpload } from '../model/net/ObjectParam';
import PhotoBackupSessionStore, { PhotoBackupSessionData } from '../model/PhotoBackupSessionStore';
import { FileSystemUtil } from './FileSystemUtil';
import { ApiErrorUtil } from './ApiErrorUtil';
import UploadConflictResolver from './UploadConflictResolver';
import AppLogger from './AppLogger';

const TAG: string = 'PhotoBackupUploader';

export enum PhotoBackupUploadResult {
  COMPLETED = 'completed',
  EXISTS = 'exists',
  PAUSED = 'paused',
  CANCELED = 'canceled'
}

/**
 * Cloudreve 创建上传会话时返回"对象已存在"（overwrite=false 撞到云端同名文件）。
 * 把冲突单独返回给上层，由相册备份策略选择新的 "(n)" 文件名重试。
 * 不能直接当成功：同名文件可能并不是同一张照片。
 */
function isObjectExistedError(err: Error): boolean {
  return ApiErrorUtil.isObjectExisted(err?.message ?? '');
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
    let session: PhotoBackupSessionData;
    try {
      session = await this.openSession(itemId, cachePath, remotePath, fileName, total, lastModifiedMs, callbacks);
    } catch (err) {
      if (err instanceof PhotoBackupUploadInterrupted) {
        return err.reason;
      }
      if (err instanceof Error && isObjectExistedError(err)) {
        AppLogger.info(TAG, `remote already has ${fileName}, request renamed retry`);
        PhotoBackupSessionStore.remove(itemId);
        return PhotoBackupUploadResult.EXISTS;
      }
      throw err instanceof Error ? err : new Error(String(err));
    }

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

  /**
   * 建会话（或续用本地存档的会话）；撞上 40054「上传会话已存在」时先清掉服务端
   * 残留的占位再试一次。
   *
   * 这条自愈路径是必需的：备份失败时 uploader 会删服务端会话再抹掉本地存档，
   * 而删除在 V3 上一直是空操作（native 侧误以为 V3 没有删除接口），于是每失败
   * 一次就在服务端留一个永久占位，本地却连 sessionId 都没了。之后这张照片每次
   * 备份都撞同一个 40054，要等服务端 GC（upload_session_timeout 默认 24h）。
   * 反馈里"47 张照片反复无法上传"就是这么来的。
   */
  private async openSession(
    itemId: string,
    cachePath: string,
    remotePath: string,
    fileName: string,
    total: number,
    lastModifiedMs: number,
    callbacks?: PhotoBackupUploadCallbacks
  ): Promise<PhotoBackupSessionData> {
    this.throwIfInterrupted(callbacks);
    try {
      return await this.resolveSession(itemId, cachePath, remotePath, fileName, total, lastModifiedMs, callbacks);
    } catch (err) {
      if (err instanceof PhotoBackupUploadInterrupted) {
        throw err;
      }
      const message = err instanceof Error ? err.message : String(err);
      if (!ApiErrorUtil.isUploadSessionExisted(message)) {
        throw err instanceof Error ? err : new Error(message);
      }
      const knownSessionId = PhotoBackupSessionStore.get(itemId)?.sessionId ?? '';
      AppLogger.warn(TAG, `create session hit 40054 for ${fileName}, clearing stale placeholder`);
      const cleared = await UploadConflictResolver.clear(remotePath, knownSessionId, true);
      if (!cleared) {
        // 没清掉任何东西就重试只会再撞一次同样的错，直接把原错误抛出去
        throw err instanceof Error ? err : new Error(message);
      }
      PhotoBackupSessionStore.remove(itemId);
      this.throwIfInterrupted(callbacks);
      return await this.resolveSession(itemId, cachePath, remotePath, fileName, total, lastModifiedMs, callbacks);
    }
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
        && existing.sessionId.length > 0) {
      if (existing.cachePath !== cachePath) {
        if (existing.cachePath.length > 0) {
          await FileSystemUtil.unlinkIfExists(existing.cachePath);
        }
        existing.cachePath = cachePath;
        existing.updatedAt = now;
        PhotoBackupSessionStore.put(existing);
      }
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
      // 两条分支都是 native 侧从文件流式读取上传。此前 chunkSize > 0 时走的
      // uploadLocalFileChunk 会把整个分片读进内存（上游还会再 to_vec 一份），
      // Cloudreve 默认 25MB 分片 × 5 并发就是上百 MB 的瞬时占用。
      const uploaded = useRemoteNode
        ? await CloudApi.uploadLocalFileChunkToUrlWithProgress(
          cachePath, uploadUrls[Constant.FIRST_ARRAY_INDEX], session.credential,
          index, chunkOffset, length, progressCallback)
        : await CloudApi.uploadLocalFileChunkWithProgress(
          cachePath, session.sessionId, index, chunkOffset, length, progressCallback);
      // 必须严格校验实际上传字节数，不能"没传够就当传满了"。
      // 原先是 offset += uploaded > 0 ? uploaded : length —— 本地文件比 session 登记的
      // total 短时（媒体库 size 过时，见 backupItem 里的真实大小回填），native 读到文件尾
      // 会返回 0，这里却按 length 把 offset 直接推到 total，循环正常结束、上报 COMPLETED；
      // 而服务端收到的字节数不足声明值，会把文件一直挂在"上传中"、大小 0B，
      // 预览是黑屏。宁可这张明确失败让用户看见，也不要静默产出空文件。
      if (uploaded < length) {
        throw new Error(`分片 ${index} 只上传了 ${uploaded} / ${length} 字节` +
          `（本地文件比登记的 ${total} 字节短），已中止以免在云端留下空文件`);
      }
      offset += uploaded;
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
