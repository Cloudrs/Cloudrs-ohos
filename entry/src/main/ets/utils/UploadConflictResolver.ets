import { CloudApi } from '../model/net/CloudApi';
import { DirectoryInfo, ObjectInfo } from '../model/net/ApiTypes';
import AppLogger from './AppLogger';

const TAG: string = 'UploadConflictResolver';

/**
 * 目录清单缓存的有效期。相册备份一批几十张全撞 40054 是常态，
 * 每张都去列一次父目录太贵（反馈里那台机器列根目录花了 43 秒）。
 * 造成 40054 的占位都是本次上传之前就在服务端的，所以一次清单足够覆盖整批。
 */
const DIR_CACHE_TTL_MS: number = 30000;

interface DirListingCache {
  at: number;
  /** 文件名 → 对象 id */
  ids: Map<string, string>;
}

/**
 * 处理创建上传会话时的 40054「上传会话已存在」。
 *
 * Cloudreve 建会话时会先插一条占位文件记录占住文件名。上传没走完就中断——进程被杀、
 * 网络断在半路、或者早期版本里 delete 会话在 V3 上根本是空操作——占位就留在服务端。
 * 之后同名文件每次建会话都撞 40054，要等服务端 GC（V3 的 upload_session_timeout
 * 默认 24h）才自己好，用户看到的就是"反复上传，永远失败"。
 *
 * 清理有两条路：
 * 1. 手里还有 sessionId（本地传输记录 / 备份会话存档里）→ 按 id 删会话，最轻。
 * 2. sessionId 已经丢了 → 按路径删掉那个同名对象。
 *    这条路的安全性来自 40054 本身：服务端只有在同名对象**带 UploadSessionID**
 *    时才回 40054，撞上真实文件回的是 40004。所以拿到 40054 就等于确认了
 *    同名的那个一定是占位，删它不会碰到用户的真数据。
 *
 * 两条路都失败就返回 false，调用方不要重试——重试只会再撞一次同样的 40054。
 */
class UploadConflictResolverImpl {
  private dirCache: Map<string, DirListingCache> = new Map();

  /**
   * 清掉 remotePath 上的残留上传会话。
   * @param remotePath 目标文件的完整远端路径
   * @param knownSessionId 本地记录里的 sessionId，没有就传空串
   * @param allowPathLookup 允不允许退到"按路径删同名对象"。
   *   **只有服务端明确回了 40054 才能传 true**：那时同名对象一定是占位。
   *   40004 撞上的可能是用户的真实文件，传 true 会误删。
   * @returns 是否真的清掉了东西——只有 true 才值得重建会话重试
   */
  async clear(remotePath: string, knownSessionId: string, allowPathLookup: boolean): Promise<boolean> {
    if (knownSessionId.length > 0) {
      const removed = await this.deleteBySessionId(remotePath, knownSessionId);
      if (removed) {
        return true;
      }
      AppLogger.warn(TAG, `delete by sessionId failed: ${remotePath}`);
    }
    if (!allowPathLookup) {
      return false;
    }
    return this.deletePlaceholderByPath(remotePath);
  }

  private deleteBySessionId(remotePath: string, sessionId: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      CloudApi.deleteUploadSession(remotePath, sessionId, {
        onSuccess: () => {
          AppLogger.info(TAG, `cleared stale session ${sessionId} @ ${remotePath}`);
          resolve(true);
        },
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `delete upload session ${sessionId} failed: ${msg}`);
          resolve(false);
        }
      });
    });
  }

  /** 列父目录找同名对象再删。列目录不便宜，所以只在按 id 删不掉时才走。 */
  private async deletePlaceholderByPath(remotePath: string): Promise<boolean> {
    const cut = remotePath.lastIndexOf('/');
    if (cut < 0) {
      return false;
    }
    const parent = cut === 0 ? '/' : remotePath.substring(0, cut);
    const name = remotePath.substring(cut + 1);
    if (name.length === 0) {
      return false;
    }

    const ids = await this.listFileIds(parent);
    const placeholderId = ids.get(name);
    if (!placeholderId || placeholderId.length === 0) {
      AppLogger.warn(TAG, `no placeholder named ${name} under ${parent}, nothing to clear`);
      return false;
    }
    const deleted = await this.deleteObject(placeholderId, name);
    if (deleted) {
      // 清单还要给同一批里剩下的文件用，把删掉的这条从缓存里摘掉
      ids.delete(name);
    }
    return deleted;
  }

  /** 取父目录的「文件名 → id」清单，TTL 内复用。目录项不收进来，我们只删文件。 */
  private async listFileIds(parent: string): Promise<Map<string, string>> {
    const now = new Date().getTime();
    const cached = this.dirCache.get(parent);
    if (cached && now - cached.at < DIR_CACHE_TTL_MS) {
      return cached.ids;
    }
    const ids = await this.fetchFileIds(parent);
    this.dirCache.set(parent, { at: now, ids });
    return ids;
  }

  private fetchFileIds(parent: string): Promise<Map<string, string>> {
    return new Promise<Map<string, string>>((resolve: (value: Map<string, string>) => void) => {
      CloudApi.getFilesInfo(parent, {
        onSuccess: (data: DirectoryInfo) => {
          const ids = new Map<string, string>();
          (data.objects ?? []).forEach((object: ObjectInfo) => {
            if (object.type !== 'dir' && object.id.length > 0) {
              ids.set(object.name, object.id);
            }
          });
          resolve(ids);
        },
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `list ${parent} failed while clearing placeholder: ${msg}`);
          resolve(new Map<string, string>());
        }
      });
    });
  }

  private deleteObject(id: string, name: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      CloudApi.deleteObject(id, false, {
        onSuccess: () => {
          AppLogger.info(TAG, `deleted upload placeholder ${name}`);
          resolve(true);
        },
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `delete upload placeholder ${name} failed: ${msg}`);
          resolve(false);
        }
      });
    });
  }
}

const UploadConflictResolver = new UploadConflictResolverImpl();

export default UploadConflictResolver;
