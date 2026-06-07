import UserPreferences from './UserPreferences';
import Constant from './Constant';
import { PhotoBackupSettings } from './PhotoBackupModel';

const CONCURRENT_MIN: number = 1;
const CONCURRENT_MAX: number = 10;
const DEFAULT_PATH: string = '/Photos/Camera';

/** AppStorage mirror key, used by album tab and mine tab via @StorageProp to observe changes */
export const PHOTO_BACKUP_ENABLED_KEY: string = 'photoBackupEnabledMirror';
export const PHOTO_BACKUP_PATH_KEY: string = 'photoBackupPathMirror';
export const PHOTO_BACKUP_REVISION_KEY: string = 'photoBackupSettingsRevision';

export class PhotoBackupSettingsStore {
  static normalizeConcurrent(value: number): number {
    if (typeof value !== 'number' || Number.isNaN(value)) {
      return Constant.UPLOAD_CONCURRENT_DEFAULT;
    }
    return Math.min(Math.max(Math.floor(value), CONCURRENT_MIN), CONCURRENT_MAX);
  }

  static normalizeRemotePath(path: string): string {
    let value = (path ?? '').trim();
    if (value.length === 0) {
      return DEFAULT_PATH;
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
    settings.uploadConcurrent = PhotoBackupSettingsStore.normalizeConcurrent(settings.uploadConcurrent);
    settings.remotePath = PhotoBackupSettingsStore.normalizeRemotePath(settings.remotePath);
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS, settings.toJson());
    PhotoBackupSettingsStore.mirror(settings);
  }

  /** Write AppStorage mirrors and increment revision to trigger cross-page refresh */
  static mirror(settings: PhotoBackupSettings): void {
    AppStorage.setOrCreate(PHOTO_BACKUP_ENABLED_KEY, settings.enabled);
    AppStorage.setOrCreate(PHOTO_BACKUP_PATH_KEY, settings.remotePath);
    const rev = (AppStorage.get<number>(PHOTO_BACKUP_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(PHOTO_BACKUP_REVISION_KEY, rev);
  }
}
