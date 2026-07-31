import { CloudApi } from '../model/net/CloudApi';
import { FileModelState } from '../model/FileModel';
import PhotoBackupSessionStore, { PhotoBackupSessionData } from '../model/PhotoBackupSessionStore';
import TransferDatabase, { UploadRecord } from '../model/TransferDatabase';
import PhotoBackupUploader from './PhotoBackupUploader';
import { uploadManager } from './UploadManager';
import { FileSystemUtil } from './FileSystemUtil';
import AppLogger from './AppLogger';

const TAG: string = 'UploadSessionRelief';

/**
 * 一次删除操作里能拿到的所有占用信息。
 * 相册备份与文件 Tab 上传是两条独立的 session 来源：
 * PhotoBackupSessionStore（ETS 层 sessionId 存 UserPreferences）+
 * TransferDatabase 里 UploadManager 持久化的 session。
 * 兜底解除时两条源都要遍历，避免只清一边导致 Cloudreve 仍认为占用。
 */
export interface UploadSessionSummary {
  photoBackupSessions: PhotoBackupSessionData[]
  fileUploadRecords: UploadRecord[]
  count: number
}

function normalize(path: string): string {
  let value = (path ?? '').trim();
  if (value.length === 0) {
    return '/';
  }
  if (!value.startsWith('/')) {
    value = '/' + value;
  }
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/**
 * 只有还没走完的上传才可能真的占着服务端会话。
 * 传输列表里 COMPLETED / FAILED 的记录不会被删（要留给用户看历史，见 UploadManager
 * 上传成功只改 state 不删行），sessionId 也原样留着——不排掉的话，凡是从本机传过的文件
 * 一旦删除失败，都会被报成「文件被上传占用」，而真实原因可能是登录态失效之类的其它错误。
 */
function isActiveUploadState(state: FileModelState): boolean {
  return state === FileModelState.INITIALIZED || state === FileModelState.WAITING ||
    state === FileModelState.RUNNING || state === FileModelState.RETRYING ||
    state === FileModelState.PAUSED;
}

function matches(remotePath: string, fileSet: Set<string>, dirPrefixes: string[]): boolean {
  const target = normalize(remotePath);
  if (fileSet.has(target)) {
    return true;
  }
  for (const prefix of dirPrefixes) {
    if (target === prefix || target.startsWith(prefix + '/')) {
      return true;
    }
  }
  return false;
}

class UploadSessionReliefImpl {
  /**
   * 汇总本机对给定路径的活跃 session（已 create 但未完成/未 delete 的）。
   * @param filePaths 单文件路径（remotePath 精确匹配）
   * @param dirPaths 目录路径（remotePath 命中前缀 or 相等）
   */
  summarize(filePaths: string[], dirPaths: string[]): UploadSessionSummary {
    const fileSet: Set<string> = new Set<string>();
    filePaths.forEach((p: string) => fileSet.add(normalize(p)));
    const dirPrefixes: string[] = dirPaths.map(normalize);

    const photoBackupSessions = PhotoBackupSessionStore.list()
      .filter((data: PhotoBackupSessionData) => matches(data.remotePath, fileSet, dirPrefixes));
    const fileUploadRecords = TransferDatabase.listUploads()
      .filter((record: UploadRecord) =>
        record.sessionId.length > 0 && isActiveUploadState(record.state) &&
          matches(record.remotePath, fileSet, dirPrefixes));

    return {
      photoBackupSessions,
      fileUploadRecords,
      count: photoBackupSessions.length + fileUploadRecords.length
    };
  }

  /**
   * 逐条 deleteUploadSession + 清缓存 + 清本地记录。
   * 单条失败不阻断整体流程；即使服务端已 404 也算成功（本地清了就行）。
   */
  async relieve(summary: UploadSessionSummary, filePaths: string[], dirPaths: string[]): Promise<void> {
    const fileSet: Set<string> = new Set<string>();
    filePaths.forEach((p: string) => fileSet.add(normalize(p)));
    const dirPrefixes: string[] = dirPaths.map(normalize);
    // 先把 UploadManager 内存队列里未开跑的匹配任务丢弃，防止本次解除后又新起 session
    uploadManager.dropByRemotePath(fileSet, dirPrefixes);

    for (const data of summary.photoBackupSessions) {
      try {
        await PhotoBackupUploader.cleanupSession(data);
      } catch (err) {
        AppLogger.warn(TAG, `photo cleanup failed: ${(err as Error)?.message ?? err}`);
      }
    }
    for (const record of summary.fileUploadRecords) {
      try {
        await this.deleteFileUploadSession(record);
      } catch (err) {
        AppLogger.warn(TAG, `file cleanup failed: ${(err as Error)?.message ?? err}`);
      }
    }
    if (summary.count > 0) {
      AppLogger.info(TAG, `relieved ${summary.count} upload sessions (photo=${summary.photoBackupSessions.length}, file=${summary.fileUploadRecords.length})`);
    }
  }

  private async deleteFileUploadSession(record: UploadRecord): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      CloudApi.deleteUploadSession(record.remotePath, record.sessionId, {
        onSuccess: () => resolve(),
        onFailure: (msg: string) => {
          // 服务端可能已 404 / 网络异常，本地清了就行，日志留痕
          AppLogger.warn(TAG, `delete upload session failed ${record.sessionId}: ${msg}`);
          resolve();
        }
      });
    });
    if (record.cachePath.length > 0) {
      await FileSystemUtil.unlinkIfExists(record.cachePath);
    }
    TransferDatabase.deleteUpload(record.id);
  }
}

const UploadSessionRelief = new UploadSessionReliefImpl();
export default UploadSessionRelief;
