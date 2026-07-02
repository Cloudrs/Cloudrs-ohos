import UserPreferences from './UserPreferences';
import Constant from './Constant';
import { PhotoBackupSettings } from './PhotoBackupModel';
import AppLogger from '../utils/AppLogger';

const TAG: string = 'PhotoBackup';
let lastLoggedEnabled: boolean | undefined = undefined;

/** AppStorage mirror key, used by album tab and mine tab via @StorageProp to observe changes */
export const PHOTO_BACKUP_ENABLED_KEY: string = 'photoBackupEnabledMirror';
export const PHOTO_BACKUP_PATH_KEY: string = 'photoBackupPathMirror';
export const PHOTO_BACKUP_REVISION_KEY: string = 'photoBackupSettingsRevision';
/** App 内从备份目录删除/移出的文件名累积列表（JSON 字符串）；相册变为活动时取用，精确撤销这些图的已备份标记 */
export const PHOTO_BACKUP_REMOVED_NAMES_KEY: string = 'photoBackupRemovedNames';
/** App 内把备份目录本身（或其祖先目录）整个删掉的标志；相册变为活动时取用，一次性撤销全部已备份标记 */
export const PHOTO_BACKUP_REMOVED_ALL_KEY: string = 'photoBackupRemovedAll';

export class PhotoBackupSettingsStore {
  static normalizeConcurrent(value: number): number {
    if (typeof value !== 'number' || Number.isNaN(value)) {
      return Constant.UPLOAD_CONCURRENT_DEFAULT;
    }
    return Math.min(
      Math.max(Math.floor(value), Constant.UPLOAD_CONCURRENT_MIN),
      Constant.UPLOAD_CONCURRENT_MAX
    );
  }

  static normalizeRemotePath(path: string): string {
    let value = (path ?? '').trim();
    if (value.length === 0) {
      return PhotoBackupSettings.DEFAULT_REMOTE_PATH;
    }
    if (!value.startsWith('/')) {
      value = `/${value}`;
    }
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static load(): PhotoBackupSettings {
    const json = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS, '') as string;
    const settings = PhotoBackupSettings.fromJson(json ?? '');
    settings.uploadConcurrent = PhotoBackupSettingsStore.normalizeConcurrent(settings.uploadConcurrent);
    settings.remotePath = PhotoBackupSettingsStore.normalizeRemotePath(settings.remotePath);
    return settings;
  }

  static save(settings: PhotoBackupSettings): void {
    const concurrent = PhotoBackupSettingsStore.normalizeConcurrent(settings.uploadConcurrent);
    const path = PhotoBackupSettingsStore.normalizeRemotePath(settings.remotePath);
    const normalized = new PhotoBackupSettings();
    normalized.enabled = settings.enabled;
    normalized.remotePath = path;
    normalized.wifiOnly = settings.wifiOnly;
    normalized.autoBackup = settings.autoBackup;
    normalized.uploadConcurrent = concurrent;
    normalized.lastScanAt = settings.lastScanAt;
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS, normalized.toJson());
    if (lastLoggedEnabled !== normalized.enabled) {
      AppLogger.info(TAG, `settings ${normalized.enabled ? 'enabled' : 'disabled'}, path=${normalized.remotePath}, wifiOnly=${normalized.wifiOnly}, concurrent=${normalized.uploadConcurrent}`);
      lastLoggedEnabled = normalized.enabled;
    }
    PhotoBackupSettingsStore.mirror(normalized);
  }

  /**
   * Push already-normalized values to AppStorage and increment the revision counter
   * to trigger cross-page refresh. Callers should prefer `save()`, which normalizes
   * values first and then delegates here; call `mirror()` directly only to rehydrate
   * AppStorage on startup from a settings object that was already normalized (e.g.
   * the result of `load()`).
   */
  static mirror(settings: PhotoBackupSettings): void {
    AppStorage.setOrCreate(PHOTO_BACKUP_ENABLED_KEY, settings.enabled);
    AppStorage.setOrCreate(PHOTO_BACKUP_PATH_KEY, settings.remotePath);
    const rev = (AppStorage.get<number>(PHOTO_BACKUP_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(PHOTO_BACKUP_REVISION_KEY, rev);
  }

  /** 当前备份根路径（已归一）。从持久化设置读，始终可用，不依赖易空的 AppStorage 镜像。 */
  static backupBasePath(): string {
    return PhotoBackupSettingsStore.normalizeRemotePath(PhotoBackupSettingsStore.load().remotePath);
  }

  /** 给定云端目录是否就是备份目录或其子目录——文件 Tab 据此判断删/移操作是否动了备份目录 */
  static isBackupPath(path: string): boolean {
    if ((path ?? '').length === 0) {
      return false;
    }
    const base = PhotoBackupSettingsStore.backupBasePath();
    const target = PhotoBackupSettingsStore.normalizeRemotePath(path);
    return target === base || target.startsWith(`${base}/`);
  }

  /**
   * isBackupPath 的反向判断：删除给定目录是否会把备份目录整个带走
   * （目录就是备份目录本身，或是它的祖先）。文件 Tab 删目录成功后据此置全量撤销标志。
   */
  static coversBackupPath(dirPath: string): boolean {
    if ((dirPath ?? '').length === 0) {
      return false;
    }
    const base = PhotoBackupSettingsStore.backupBasePath();
    const target = PhotoBackupSettingsStore.normalizeRemotePath(dirPath);
    return base === target || base.startsWith(`${target}/`);
  }

  /** App 内把备份目录（或其祖先）整个删掉后置位；相册变为活动时取用，一次性撤销全部已备份标记。 */
  static markRemoteRemovedAll(): void {
    AppStorage.setOrCreate(PHOTO_BACKUP_REMOVED_ALL_KEY, true);
  }

  /** 相册取用并复位全量撤销标志。 */
  static consumeRemoteRemovedAll(): boolean {
    const flag = AppStorage.get<boolean>(PHOTO_BACKUP_REMOVED_ALL_KEY) ?? false;
    if (flag) {
      AppStorage.setOrCreate(PHOTO_BACKUP_REMOVED_ALL_KEY, false);
    }
    return flag;
  }

  /** App 内从备份目录删除/移出文件后，累加文件名到待清理列表（去重）；相册变为活动时精确撤销标记。 */
  static markRemoteRemoved(names: string[]): void {
    if (names.length === 0) {
      return;
    }
    const set: Set<string> = new Set<string>(PhotoBackupSettingsStore.readRemovedNames());
    names.forEach((name: string) => {
      if (name.length > 0) {
        set.add(name);
      }
    });
    AppStorage.setOrCreate(PHOTO_BACKUP_REMOVED_NAMES_KEY, JSON.stringify(Array.from(set)));
  }

  /** 相册取用并清空待清理文件名列表。 */
  static consumeRemoteRemoved(): string[] {
    const names = PhotoBackupSettingsStore.readRemovedNames();
    if (names.length > 0) {
      AppStorage.setOrCreate(PHOTO_BACKUP_REMOVED_NAMES_KEY, '');
    }
    return names;
  }

  private static readRemovedNames(): string[] {
    const raw = AppStorage.get<string>(PHOTO_BACKUP_REMOVED_NAMES_KEY) ?? '';
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as string[];
    } catch (_) {
      return [];
    }
  }
}
