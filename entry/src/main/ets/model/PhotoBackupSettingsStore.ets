import UserPreferences from './UserPreferences';
import Constant from './Constant';
import { PhotoBackupSettings } from './PhotoBackupModel';

/** AppStorage mirror key, used by album tab and mine tab via @StorageProp to observe changes */
export const PHOTO_BACKUP_ENABLED_KEY: string = 'photoBackupEnabledMirror';
export const PHOTO_BACKUP_PATH_KEY: string = 'photoBackupPathMirror';
export const PHOTO_BACKUP_REVISION_KEY: string = 'photoBackupSettingsRevision';

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
}
