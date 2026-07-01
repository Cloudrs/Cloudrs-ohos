import UserPreferences from './UserPreferences';
import Constant from './Constant';
import AppLogger from '../utils/AppLogger';

const TAG: string = 'PhotoBackupSessionStore';

/**
 * 服务端偶尔不返 expires 时，用 updatedAt 兜底：超过这个时长的 session 视作孤儿。
 * 24h 是给正常用户的续传保留窗口 —— 大部分场景一次备份任务不会跨天。
 */
const FALLBACK_TTL_MS: number = 24 * 60 * 60 * 1000;

/**
 * 单张相册备份任务的 Cloudreve upload session 快照。
 *
 * 存在意义：native uploadLocalFile 是一把梭，session 生命周期埋在 native 里；
 * 备份中途失败/App 被杀会在服务端留下未完成的 session 占位，父目录/文件就删不掉。
 * 改造后 ETS 层显式管理 session：create → 分块 → complete；持久化这份快照后，
 * 断电/切换用户/App 被回收 都能在下次启动时按快照把 orphan session 通过
 * deleteUploadSession 清干净，也能从 offset/chunkIndex 续传。
 */
export interface PhotoBackupSessionData {
  itemId: string
  remotePath: string
  cachePath: string
  sessionId: string
  chunkSize: number
  uploadUrls: string[]
  credential: string
  storagePolicyType: string
  storagePolicyRelay: boolean
  /** 服务端返回的过期时间，秒级或毫秒级；读取时按当前时钟归一处理 */
  expiresAt: number
  total: number
  offset: number
  chunkIndex: number
  updatedAt: number
}

interface PhotoBackupSessionsPayload {
  sessions?: PhotoBackupSessionData[]
}

class PhotoBackupSessionStoreImpl {
  private cache: Map<string, PhotoBackupSessionData> = new Map<string, PhotoBackupSessionData>();
  private loaded: boolean = false;

  private load(): void {
    if (this.loaded) {
      return;
    }
    const raw = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SESSIONS, '') as string;
    this.loaded = true;
    if (!raw || raw.length === 0) {
      return;
    }
    try {
      const payload = JSON.parse(raw) as PhotoBackupSessionsPayload;
      (payload.sessions ?? []).forEach((data: PhotoBackupSessionData) => {
        if (data.itemId && data.itemId.length > 0) {
          this.cache.set(data.itemId, data);
        }
      });
    } catch (err) {
      AppLogger.error(TAG, `load failed: ${(err as Error)?.message ?? err}`);
      this.cache.clear();
    }
  }

  private persist(): void {
    const payload: PhotoBackupSessionsPayload = { sessions: Array.from(this.cache.values()) };
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SESSIONS, JSON.stringify(payload));
  }

  get(itemId: string): PhotoBackupSessionData | undefined {
    this.load();
    return this.cache.get(itemId);
  }

  list(): PhotoBackupSessionData[] {
    this.load();
    return Array.from(this.cache.values());
  }

  put(data: PhotoBackupSessionData): void {
    this.load();
    this.cache.set(data.itemId, data);
    this.persist();
  }

  updateProgress(itemId: string, offset: number, chunkIndex: number): void {
    this.load();
    const existing = this.cache.get(itemId);
    if (!existing) {
      return;
    }
    existing.offset = offset;
    existing.chunkIndex = chunkIndex;
    existing.updatedAt = new Date().getTime();
    this.cache.set(itemId, existing);
    this.persist();
  }

  remove(itemId: string): void {
    this.load();
    if (!this.cache.has(itemId)) {
      return;
    }
    this.cache.delete(itemId);
    this.persist();
  }

  clear(): void {
    this.load();
    if (this.cache.size === 0) {
      return;
    }
    this.cache.clear();
    this.persist();
  }

  /** 服务端 expires 有时给秒、有时给毫秒；> 1e12 视作毫秒，其余按秒放大 */
  static toExpireMs(raw: number): number {
    if (raw <= 0) {
      return 0;
    }
    return raw > 1e12 ? raw : raw * 1000;
  }

  isExpired(data: PhotoBackupSessionData, nowMs: number): boolean {
    const expireMs = PhotoBackupSessionStoreImpl.toExpireMs(data.expiresAt);
    if (expireMs > 0) {
      return expireMs <= nowMs;
    }
    // 服务端没给 expires 时用 updatedAt 兜底，避免 session 永远躺在 store 里出不了 prune
    if (data.updatedAt > 0 && nowMs - data.updatedAt >= FALLBACK_TTL_MS) {
      return true;
    }
    return false;
  }
}

const PhotoBackupSessionStore = new PhotoBackupSessionStoreImpl();
export default PhotoBackupSessionStore;
