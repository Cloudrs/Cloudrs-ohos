import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import Constant from '../../model/Constant';
import {
  PhotoBackupItem,
  PhotoBackupItemData,
  PhotoBackupPathHistory,
  PhotoBackupSettings,
  PhotoBackupState,
  PhotoBackupStatus
} from '../../model/PhotoBackupModel';
import { CloudApi } from '../../model/net/CloudApi';
import UserPreferences from '../../model/UserPreferences';
import { PathSelectSheet } from '../../components/PathSelectSheet';
import { showToast } from '../../utils/ToastUtil';
import { CloudThemeToken } from '../../model/CloudTheme';
import { SectionHeader } from '../../components/SectionHeader';
import { EmptyState } from '../../components/EmptyState';
import { CloudTopBar } from '../../components/CloudTopBar';
import { CloudScaffold } from '../../components/CloudScaffold';
import { FileSystemUtil } from '../../utils/FileSystemUtil';
import { NetworkStateUtil } from '../../utils/NetworkStateUtil';

const TAG: string = 'TabPictures';

@Component
export struct TabPictures {
  @Link overLap: boolean
  @State settingsEnabled: boolean = false;
  @State settingsRemotePath: string = '/Photos/Camera';
  @State settingsWifiOnly: boolean = true;
  @State settingsAutoBackup: boolean = true;
  @State settingsLastScanAt: number = 0;
  @State backupState: PhotoBackupState = PhotoBackupState.IDLE;
  @State photos: PhotoBackupItem[] = [];
  @State selectedIndexes: number[] = [0];
  @State showSettings: boolean = false;
  @State showPathSelect: boolean = false;
  @State isScanning: boolean = false;
  @State backupQueueDone: number = 0;
  @State backupQueueTotal: number = 0;
  @State shouldPauseBackup: boolean = false;
  @State permissionHint: string = '';
  @State photoGridWidth: number = 0;
  @State settingsRevision: number = 0;
  private doneIds: Set<string> = new Set<string>();

  aboutToAppear(): void {
    this.loadSettings();
    this.loadDoneIds();
    this.loadPhotoRecords();
    if (this.getSettingsEnabled()) {
      this.scanLocalPhotos();
    }
  }

  loadSettings(): void {
    let json = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS, '') as string;
    this.applySettings(PhotoBackupSettings.fromJson(json ?? ''));
    this.settingsRevision++;
  }

  saveSettings(): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS,
      this.createSettingsSnapshot().toJson());
  }

  loadDoneIds(): void {
    let json = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_DONE_IDS, '[]') as string;
    try {
      this.doneIds = new Set<string>(JSON.parse(json ?? '[]') as string[]);
    } catch (err) {
      console.error(TAG, `load done ids failed: ${(err as Error)?.message ?? err}`);
      this.doneIds = new Set<string>();
    }
  }

  saveDoneIds(): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_DONE_IDS,
      JSON.stringify(Array.from(this.doneIds)));
  }

  loadPhotoRecords(): void {
    let json = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_ITEMS, '[]') as string;
    try {
      let data = JSON.parse(json ?? '[]') as PhotoBackupItemData[];
      this.photos = data.map((item: PhotoBackupItemData) => PhotoBackupItem.fromData(item));
      this.migrateLegacyDoneIds();
      this.refreshDoneStatus();
    } catch (err) {
      console.error(TAG, `load photo records failed: ${(err as Error)?.message ?? err}`);
      this.photos = [];
    }
  }

  savePhotoRecords(): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_ITEMS,
      JSON.stringify(this.getPhotos().map((item: PhotoBackupItem) => item.toData())));
  }

  getPhotos(): PhotoBackupItem[] {
    return this.photos ?? [];
  }

  getWaitingItems(): PhotoBackupItem[] {
    return this.getPhotos().filter((item: PhotoBackupItem) => item.status === PhotoBackupStatus.WAITING);
  }

  getUploadingItems(): PhotoBackupItem[] {
    return this.getPhotos().filter((item: PhotoBackupItem) => item.status === PhotoBackupStatus.UPLOADING);
  }

  getCompletedItems(): PhotoBackupItem[] {
    return this.getPhotos().filter((item: PhotoBackupItem) => item.status === PhotoBackupStatus.COMPLETED);
  }

  getFailedItems(): PhotoBackupItem[] {
    return this.getPhotos().filter((item: PhotoBackupItem) => item.status === PhotoBackupStatus.FAILED);
  }

  getLocalCount(): number {
    return Math.max(this.getPhotos().length, this.getCurrentPathDoneCount());
  }

  getCompletedCount(): number {
    return Math.max(this.getCompletedItems().length, this.getCurrentPathDoneCount());
  }

  getStatusText(): string {
    if (!this.getSettingsEnabled()) {
      return '未开启';
    }
    if (!this.hasBackupPath()) {
      return '请选择备份路径';
    }
    if (this.backupState === PhotoBackupState.SCANNING) {
      return '正在扫描本地相册';
    }
    if (this.backupState === PhotoBackupState.BACKING_UP) {
      return `正在备份 ${this.backupQueueDone}/${this.backupQueueTotal} 张`;
    }
    if (this.backupState === PhotoBackupState.WAITING_NETWORK) {
      return '等待 Wi-Fi';
    }
    if (this.backupState === PhotoBackupState.PAUSED) {
      return `已暂停 ${this.backupQueueDone}/${this.backupQueueTotal} 张`;
    }
    return `${this.getSettingsWifiOnly() ? '仅 Wi-Fi' : '任意网络'} · ${this.getSettingsRemotePath()}`;
  }

  getPrimaryActionText(): string {
    if (!this.getSettingsEnabled()) {
      return '开启备份';
    }
    if (this.backupState === PhotoBackupState.BACKING_UP) {
      return '备份中';
    }
    if (this.backupState === PhotoBackupState.PAUSED) {
      return '继续备份';
    }
    if (this.getFailedItems().length > 0) {
      return '重试失败';
    }
    if (!this.hasBackupPath()) {
      return '选择路径';
    }
    return '立即备份';
  }

  updateSettings(mutator: (settings: PhotoBackupSettings) => void): void {
    let next = this.createSettingsSnapshot();
    mutator(next);
    this.applySettings(next);
    this.saveSettings();
    this.settingsRevision++;
  }

  createSettingsSnapshot(): PhotoBackupSettings {
    let settings = new PhotoBackupSettings();
    settings.enabled = this.settingsEnabled;
    settings.remotePath = this.settingsRemotePath;
    settings.wifiOnly = this.settingsWifiOnly;
    settings.autoBackup = this.settingsAutoBackup;
    settings.lastScanAt = this.settingsLastScanAt;
    return settings;
  }

  applySettings(settings: PhotoBackupSettings): void {
    this.settingsEnabled = settings.enabled;
    this.settingsRemotePath = settings.remotePath;
    this.settingsWifiOnly = settings.wifiOnly;
    this.settingsAutoBackup = settings.autoBackup;
    this.settingsLastScanAt = settings.lastScanAt;
  }

  getSettingsEnabled(): boolean {
    return this.settingsEnabled;
  }

  getSettingsRemotePath(): string {
    return this.settingsRemotePath;
  }

  getBackupPathText(): string {
    return this.hasBackupPath() ? this.getSettingsRemotePath() : '未选择备份路径';
  }

  hasBackupPath(): boolean {
    return this.getSettingsRemotePath().trim().length > 0;
  }

  getSettingsWifiOnly(): boolean {
    return this.settingsWifiOnly;
  }

  getSettingsAutoBackup(): boolean {
    return this.settingsAutoBackup;
  }

  updateRemotePath(path: string): void {
    if (path.length === 0 || path === this.getSettingsRemotePath()) {
      return;
    }
    this.updateSettings((settings: PhotoBackupSettings) => {
      settings.remotePath = path;
    });
    this.refreshDoneStatus();
    this.savePhotoRecords();
    this.backupState = this.getWaitingItems().length > 0 ? PhotoBackupState.IDLE : PhotoBackupState.COMPLETED;
    showToast('已切换备份路径，状态已重新同步');
  }

  async scanLocalPhotos(): Promise<void> {
    if (this.isScanning) {
      return;
    }
    this.isScanning = true;
    this.backupState = PhotoBackupState.SCANNING;
    this.permissionHint = '';
    try {
      let context = this.getAbilityContext();
      if (!context) {
        this.permissionHint = '无法获取应用上下文，请稍后重试或重新打开页面。';
        this.backupState = PhotoBackupState.FAILED;
        return;
      }
      let granted = await this.ensurePhotoPermission(context);
      if (!granted) {
        this.permissionHint = '未获得完整相册读取权限时，系统扫描可能为空。可重新授权，或使用“选择图片加入备份”。';
        showToast('需要允许读取相册后才能扫描图片');
        this.backupState = PhotoBackupState.FAILED;
        return;
      }
      const previousCount = this.getPhotos().length;
      let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      let predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
      let fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [
          photoAccessHelper.PhotoKeys.URI,
          photoAccessHelper.PhotoKeys.PHOTO_TYPE,
          photoAccessHelper.PhotoKeys.DISPLAY_NAME,
          photoAccessHelper.PhotoKeys.SIZE,
          photoAccessHelper.PhotoKeys.DATE_MODIFIED
        ],
        predicates: predicates
      };
      let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> =
        await phAccessHelper.getAssets(fetchOptions);
      let assets: photoAccessHelper.PhotoAsset[] = await fetchResult.getAllObjects();
      let nextPhotos: PhotoBackupItem[] = [];
      assets.forEach((asset: photoAccessHelper.PhotoAsset) => {
        if (asset.photoType !== photoAccessHelper.PhotoType.IMAGE) {
          return;
        }
        nextPhotos.push(this.createBackupItem(asset.uri, asset.displayName,
          (asset.get(photoAccessHelper.PhotoKeys.SIZE) as number) ?? 0,
          (asset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED) as number) ?? 0));
      });
      fetchResult.close();
      if (nextPhotos.length === 0) {
        this.permissionHint = '未扫描到本地图片。如果相册中已有图片，请检查相册读取权限，或手动选择图片加入备份。';
      } else if (previousCount > 0 && nextPhotos.length < previousCount) {
        this.permissionHint = `本次系统扫描到 ${nextPhotos.length} 张，少于当前记录 ${previousCount} 张。如果数量不符合预期，请检查相册权限范围。`;
      }
      this.photos = this.mergePhotoList(nextPhotos, true);
      this.updateSettings((settings: PhotoBackupSettings) => {
        settings.lastScanAt = new Date().getTime();
      });
      this.savePhotoRecords();
      showToast(`已扫描到 ${this.getPhotos().length} 张本地图片`);
      this.backupState = this.getWaitingItems().length > 0 ? PhotoBackupState.IDLE : PhotoBackupState.COMPLETED;
    } catch (err) {
      let error = err as BusinessError;
      console.error(TAG, `scan failed: ${error.code}, ${error.message}`);
      this.permissionHint = '相册扫描失败，请检查系统相册权限。也可以先使用“选择图片加入备份”继续备份指定图片。';
      showToast('扫描本地相册失败，请检查相册读取权限');
      this.backupState = PhotoBackupState.FAILED;
    } finally {
      this.isScanning = false;
    }
  }

  async pickPhotosForBackup(): Promise<void> {
    try {
      let options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 50;
      let picker = new photoAccessHelper.PhotoViewPicker();
      let result = await picker.select(options);
      let uris = result.photoUris ?? [];
      if (uris.length === 0) {
        return;
      }
      let selectedItems: PhotoBackupItem[] = uris.map((uri: string) => {
        let item = this.createBackupItem(uri, this.getNameFromUri(uri), 0, new Date().getTime());
        item.id = uri;
        item.status = this.isPhotoDone(item) ? PhotoBackupStatus.COMPLETED : PhotoBackupStatus.WAITING;
        item.progress = item.status === PhotoBackupStatus.COMPLETED ? 100 : 0;
        return item;
      });
      let before = this.getPhotos().length;
      this.photos = this.mergePhotoList(selectedItems, true);
      let added = this.getPhotos().length - before;
      this.savePhotoRecords();
      showToast(added > 0 ? `已加入 ${added} 张图片` : '选择的图片已在备份列表中');
      if (this.backupState === PhotoBackupState.COMPLETED && this.getWaitingItems().length > 0) {
        this.backupState = PhotoBackupState.IDLE;
      }
    } catch (err) {
      let error = err as BusinessError;
      console.error(TAG, `pick photos failed: ${error.code}, ${error.message}`);
      showToast('选择图片失败');
    }
  }

  createBackupItem(uri: string, name: string, size: number, modifiedAt: number): PhotoBackupItem {
    let item = new PhotoBackupItem(uri, name.length > 0 ? name : this.getNameFromUri(uri), size, modifiedAt);
    item.status = this.isPhotoDone(item) ? PhotoBackupStatus.COMPLETED : PhotoBackupStatus.WAITING;
    item.progress = item.status === PhotoBackupStatus.COMPLETED ? 100 : 0;
    return item;
  }

  mergePhotoList(incoming: PhotoBackupItem[], keepExisting: boolean): PhotoBackupItem[] {
    let merged: PhotoBackupItem[] = keepExisting ? this.getPhotos().slice() : [];
    incoming.forEach((item: PhotoBackupItem) => {
      let exists = merged.some((current: PhotoBackupItem) => current.uri === item.uri);
      if (!exists) {
        merged.push(item);
      }
    });
    merged.forEach((item: PhotoBackupItem) => {
      this.applyDoneStatus(item, true);
    });
    merged.sort((left: PhotoBackupItem, right: PhotoBackupItem) => right.modifiedAt - left.modifiedAt);
    return merged;
  }

  refreshDoneStatus(): void {
    this.photos = this.getPhotos().map((item: PhotoBackupItem) => {
      this.applyDoneStatus(item, true);
      return item;
    });
  }

  applyDoneStatus(item: PhotoBackupItem, resetNotDone: boolean): void {
    if (this.isPhotoDone(item)) {
      item.status = PhotoBackupStatus.COMPLETED;
      item.progress = 100;
      item.error = '';
      return;
    }
    if (resetNotDone && item.status !== PhotoBackupStatus.FAILED) {
      item.status = PhotoBackupStatus.WAITING;
      item.progress = 0;
      item.error = '';
    }
  }

  isPhotoDone(item: PhotoBackupItem): boolean {
    if (this.doneIds.has(this.getDoneKey(item))) {
      return true;
    }
    if (!this.isDefaultBackupPath()) {
      return false;
    }
    return this.hasLegacyDoneId(item);
  }

  hasLegacyDoneId(item: PhotoBackupItem): boolean {
    return this.getLegacyDoneIds(item).length > 0;
  }

  getLegacyDoneIds(item: PhotoBackupItem): string[] {
    let legacyIds: string[] = [];
    if (this.doneIds.has(item.id) || this.doneIds.has(item.uri)) {
      legacyIds.push(this.doneIds.has(item.id) ? item.id : item.uri);
    }
    Array.from(this.doneIds).forEach((id: string) => {
      if (!this.isPathDoneId(id) && id.startsWith(`${item.uri}_`) && legacyIds.indexOf(id) < 0) {
        legacyIds.push(id);
      }
    });
    return legacyIds;
  }

  migrateLegacyDoneIds(): void {
    if (!this.isDefaultBackupPath()) {
      return;
    }
    let changed = false;
    this.getPhotos().forEach((item: PhotoBackupItem) => {
      let scopedKey = this.getDoneKey(item);
      let legacyIds = this.getLegacyDoneIds(item);
      if (legacyIds.length === 0) {
        return;
      }
      this.doneIds.add(scopedKey);
      legacyIds.forEach((id: string) => {
        this.doneIds.delete(id);
      });
      changed = true;
    });
    if (changed) {
      this.saveDoneIds();
    }
  }

  getCurrentPathDoneCount(): number {
    let scopedCount = Array.from(this.doneIds).filter((id: string) => this.isDoneIdForCurrentPath(id)).length;
    if (!this.isDefaultBackupPath()) {
      return scopedCount;
    }
    let legacyCount = Array.from(this.doneIds).filter((id: string) => !this.isPathDoneId(id)).length;
    return Math.max(scopedCount, legacyCount);
  }

  getDoneKey(item: PhotoBackupItem): string {
    return `${this.normalizeRemotePath(this.getSettingsRemotePath())}|${item.id}`;
  }

  isDefaultBackupPath(): boolean {
    return this.normalizeRemotePath(this.getSettingsRemotePath()) === '/Photos/Camera';
  }

  normalizeRemotePath(path: string): string {
    let value = path.length > 0 ? path : '/Photos/Camera';
    if (!value.startsWith('/')) {
      value = `/${value}`;
    }
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  isPathDoneId(id: string): boolean {
    return id.indexOf('|') > 0 && id.startsWith('/');
  }

  isDoneIdForCurrentPath(id: string): boolean {
    return id.startsWith(`${this.normalizeRemotePath(this.getSettingsRemotePath())}|`);
  }

  getBackupPathHistory(): PhotoBackupPathHistory[] {
    let pathCounts: Map<string, number> = new Map<string, number>();
    Array.from(this.doneIds).forEach((id: string) => {
      if (!this.isPathDoneId(id)) {
        return;
      }
      let separatorIndex = id.indexOf('|');
      let path = id.substring(0, separatorIndex);
      pathCounts.set(path, (pathCounts.get(path) ?? 0) + 1);
    });

    let currentPath = this.normalizeRemotePath(this.getSettingsRemotePath());
    if (this.isDefaultBackupPath()) {
      let legacyCount = Array.from(this.doneIds).filter((id: string) => !this.isPathDoneId(id)).length;
      if (legacyCount > 0) {
        pathCounts.set(currentPath, Math.max(pathCounts.get(currentPath) ?? 0, legacyCount));
      }
    }

    let result: PhotoBackupPathHistory[] = [];
    pathCounts.forEach((count: number, path: string) => {
      result.push(new PhotoBackupPathHistory(path, count, path === currentPath));
    });
    result.sort((left: PhotoBackupPathHistory, right: PhotoBackupPathHistory) => {
      if (left.isCurrent !== right.isCurrent) {
        return left.isCurrent ? -1 : 1;
      }
      return right.count - left.count;
    });
    return result;
  }

  getNameFromUri(uri: string): string {
    let path = uri.split('?')[0];
    let segments = path.split('/');
    let name = segments.length > 0 ? segments[segments.length - 1] : '';
    try {
      name = decodeURIComponent(name);
    } catch (_) {
    }
    return name.length > 0 ? name : `photo_${new Date().getTime()}.jpg`;
  }
  async ensurePhotoPermission(context: common.UIAbilityContext): Promise<boolean> {
    const permission: Permissions = 'ohos.permission.READ_IMAGEVIDEO';
    try {
      let atManager = abilityAccessCtrl.createAtManager();
      let result: PermissionRequestResult = await atManager.requestPermissionsFromUser(context, [permission]);
      return (result.authResults ?? []).length > 0 && result.authResults[0] === 0;
    } catch (err) {
      let error = err as BusinessError;
      console.error(TAG, `request photo permission failed: ${error.code}, ${error.message}`);
      return false;
    }
  }

  startBackup(): void {
    if (!this.getSettingsEnabled()) {
      this.updateSettings((settings: PhotoBackupSettings) => {
        settings.enabled = true;
      });
      this.showSettings = true;
      return;
    }
    if (!this.hasBackupPath()) {
      this.showSettings = true;
      showToast('请先选择相册备份路径');
      return;
    }
    if (this.getPhotos().length === 0) {
      this.scanLocalPhotos();
      return;
    }
    let failedItems = this.getFailedItems();
    let waitingItems = this.getWaitingItems();
    let targets = failedItems.length > 0 ? failedItems : waitingItems;
    if (targets.length === 0) {
      showToast('没有需要备份的图片');
      return;
    }
    if (!this.canBackupNow()) {
      this.backupState = PhotoBackupState.WAITING_NETWORK;
      this.showSettings = true;
      showToast('当前不是 Wi-Fi，已暂停相册备份');
      return;
    }
    this.backupQueueDone = 0;
    this.backupQueueTotal = targets.length;
    this.shouldPauseBackup = false;
    this.backupState = PhotoBackupState.BACKING_UP;
    this.runBackup(targets);
  }

  pauseBackup(): void {
    if (this.backupState !== PhotoBackupState.BACKING_UP) {
      return;
    }
    this.shouldPauseBackup = true;
    showToast('当前图片完成后暂停备份');
  }

  canBackupNow(): boolean {
    if (!this.getSettingsWifiOnly()) {
      return true;
    }
    try {
      return NetworkStateUtil.isWifiConnected();
    } catch (err) {
      console.error(TAG, `check wifi failed: ${(err as Error)?.message ?? err}`);
      return false;
    }
  }

  async runBackup(targets: PhotoBackupItem[]): Promise<void> {
    for (let index = 0; index < targets.length; index++) {
      if (this.shouldPauseBackup) {
        this.backupState = PhotoBackupState.PAUSED;
        return;
      }
      await this.backupItem(targets[index], index);
      this.backupQueueDone = index + 1;
      if (this.shouldPauseBackup) {
        this.backupState = PhotoBackupState.PAUSED;
        return;
      }
    }
    if (this.getUploadingItems().length === 0) {
      this.backupState = this.getWaitingItems().length > 0 ? PhotoBackupState.IDLE : PhotoBackupState.COMPLETED;
    }
  }

  async backupItem(item: PhotoBackupItem, index: number): Promise<void> {
    let localPath = '';
    try {
      item.status = PhotoBackupStatus.UPLOADING;
      item.error = '';
      item.progress = 8;
      if (await this.remotePhotoExists(item)) {
        item.progress = 100;
        item.status = PhotoBackupStatus.COMPLETED;
        item.error = '';
        this.doneIds.add(this.getDoneKey(item));
        this.saveDoneIds();
        this.savePhotoRecords();
        return;
      }
      localPath = await this.copyPhotoToCache(item);
      item.progress = 45;
      await this.uploadPhoto(localPath, this.getRemoteFilePath(item), item);
      item.progress = 100;
      item.status = PhotoBackupStatus.COMPLETED;
      this.doneIds.add(this.getDoneKey(item));
      this.saveDoneIds();
      this.savePhotoRecords();
    } catch (err) {
      item.status = PhotoBackupStatus.FAILED;
      item.error = this.getErrorMessage(err);
      item.progress = 0;
      this.savePhotoRecords();
    } finally {
      if (localPath.length > 0) {
        await FileSystemUtil.unlinkIfExists(localPath);
      }
    }
  }

  async copyPhotoToCache(item: PhotoBackupItem): Promise<string> {
    let context = this.getAbilityContext();
    if (!context) {
      throw new Error('应用上下文不可用');
    }
    let fileName = this.sanitizeFileName(item.name.length > 0 ? item.name : 'photo.jpg');
    let localPath = `${context.cacheDir}/photo_backup_${new Date().getTime()}_${fileName}`;
    await FileSystemUtil.copyUriToPath(item.uri, localPath);
    return localPath;
  }

  uploadPhoto(localPath: string, remotePath: string, item: PhotoBackupItem): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Error) => void) => {
      CloudApi.uploadLocalFile(localPath, remotePath, false, {
        onStart: () => {
          item.progress = 55;
        },
        onSuccess: () => {
          resolve();
        },
        onFailure: (message: string) => {
          reject(new Error(message));
        }
      });
    });
  }

  remotePhotoExists(item: PhotoBackupItem): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      CloudApi.getFilesInfo(this.normalizeRemotePath(this.getSettingsRemotePath()), {
        onSuccess: (data) => {
          let exists = (data.objects ?? []).some((object) => object.name === item.name);
          resolve(exists);
        },
        onFailure: (msg: string) => {
          console.info(TAG, `check remote photo exists skipped: ${msg}`);
          resolve(false);
        }
      });
    });
  }

  getRemoteFilePath(item: PhotoBackupItem): string {
    let basePath = this.normalizeRemotePath(this.getSettingsRemotePath());
    if (basePath.endsWith('/')) {
      return `${basePath}${item.name}`;
    }
    return `${basePath}/${item.name}`;
  }

  sanitizeFileName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_');
  }

  getErrorMessage(err: Object): string {
    if (err instanceof Error && err.message.length > 0) {
      return err.message;
    }
    return '备份失败，请稍后重试';
  }

  previewBackupProgress(item: PhotoBackupItem, index: number): void {
    setTimeout(() => {
      if (item.status === PhotoBackupStatus.UPLOADING && item.progress < 65) {
        item.progress = 65;
      }
    }, 400 + index * 120);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      CloudScaffold() {
          this.header();
          if (this.showSettings) {
            this.settingsPanel();
          }
          this.summaryCard();
          this.sectionUploading();
          this.sectionWaiting();
          this.sectionFailed();
          this.sectionCompleted();
          this.sectionBackupHistory();
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showPathSelect, this.pathSelectSheet(), {
      showClose: false,
      backgroundColor: CloudThemeToken.background,
      onDisappear: () => {
        this.showPathSelect = false;
      }
    })
  }

  @Builder header() {
    CloudTopBar({
      title: '相册备份',
      subtitle: this.getStatusText(),
      actionIcon: $r('app.media.ic_gearshape'),
      onAction: () => {
        this.showSettings = !this.showSettings;
      }
    })
  }

  @Builder summaryCard() {
    Column({ space: CloudThemeToken.spacingPage }) {
      Row() {
        Column({ space: CloudThemeToken.spacingXs }) {
        Text(this.getSettingsEnabled() ? '备份已开启' : '备份未开启')
            .fontSize(CloudThemeToken.textSizeTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
          Text(this.getSettingsEnabled() ? `目标路径 ${this.getBackupPathText()}` : '开启后会扫描本地图片并备份到云端')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: CloudThemeToken.spacingXl }) {
          Button(this.getPrimaryActionText())
            .fontSize(CloudThemeToken.textSizeBody)
            .height(CloudThemeToken.rowHeightSm)
            .enabled(this.backupState !== PhotoBackupState.BACKING_UP)
            .onClick(() => {
              this.startBackup();
            })

          if (this.backupState === PhotoBackupState.BACKING_UP) {
            Button('暂停')
              .fontSize(CloudThemeToken.textSizeBody)
              .height(CloudThemeToken.rowHeightSm)
              .backgroundColor(CloudThemeToken.surfaceSubtle)
              .fontColor(CloudThemeToken.textPrimary)
              .onClick(() => {
                this.pauseBackup();
              })
          }
        }
      }

      Row() {
        this.metricItem('本地', this.getLocalCount().toString());
        this.metricItem('已备份', this.getCompletedCount().toString());
        this.metricItem('待备份', this.getWaitingItems().length.toString());
        this.metricItem('失败', this.getFailedItems().length.toString());
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.getSettingsEnabled() && this.getSettingsWifiOnly()) {
        Text('默认仅在 Wi-Fi 下自动备份，可在设置中改为任意网络或手动备份。')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }

      if (this.permissionHint.length > 0) {
        this.permissionHintCard();
      }

      if (this.getSettingsEnabled() && !this.hasBackupPath()) {
        this.emptyPathCard();
      }

      if (this.backupState === PhotoBackupState.BACKING_UP) {
        Text(`本轮将连续备份 ${this.backupQueueTotal} 张，已完成 ${this.backupQueueDone} 张。`)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }

      if (this.backupState === PhotoBackupState.PAUSED) {
        Text('备份已暂停，点击继续备份会处理剩余待备份图片。')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }

      if (this.backupState === PhotoBackupState.WAITING_NETWORK && this.getSettingsWifiOnly()) {
        Button('模拟器测试：改为任意网络')
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .height(CloudThemeToken.iconBoxSm)
          .width('100%')
          .backgroundColor(CloudThemeToken.primarySoft)
          .fontColor(CloudThemeToken.primary)
          .onClick(() => {
            this.updateSettings((settings: PhotoBackupSettings) => {
              settings.wifiOnly = false;
            });
            this.backupState = PhotoBackupState.IDLE;
            showToast('已允许任意网络备份');
          })
      }
    }
    .width('100%')
    .padding(CloudThemeToken.spacingPage)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder permissionHintCard() {
    Column({ space: CloudThemeToken.spacingCard }) {
      Text(this.permissionHint)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
        .width('100%')
      Button('选择图片加入备份')
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .height(CloudThemeToken.iconBoxSm)
        .width('100%')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick(() => {
          this.pickPhotosForBackup();
        })
    }
    .width('100%')
    .padding(CloudThemeToken.spacingSection)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
  }

  @Builder emptyPathCard() {
    Column({ space: CloudThemeToken.spacingCard }) {
      Text('还没有选择云端备份路径，选择路径后才会开始上传图片。')
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
        .width('100%')
      Button('选择备份路径')
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .height(CloudThemeToken.iconBoxSm)
        .width('100%')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick(() => {
          this.openPathSelectSheet();
        })
    }
    .width('100%')
    .padding(CloudThemeToken.spacingSection)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.primarySoft)
  }

  @Builder metricItem(label: string, value: string) {
    Column({ space: CloudThemeToken.spacingXs }) {
      Text(value)
        .fontSize(CloudThemeToken.textSizeHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
      Text(label)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
    }
    .width('23%')
    .height(CloudThemeToken.rowHeight5xl)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
    .borderRadius(CloudThemeToken.cardRadius)
  }

  @Builder sectionUploading() {
    if (this.getUploadingItems().length > 0) {
      SectionHeader({ title: '正在备份', count: this.getUploadingItems().length });
      Column({ space: CloudThemeToken.spacingCard }) {
        ForEach(this.getUploadingItems(), (item: PhotoBackupItem) => {
          this.uploadingItem(item);
        }, (item: PhotoBackupItem) => item.id)
      }
    }
  }

  @Builder uploadingItem(item: PhotoBackupItem) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Image(item.uri)
        .width(CloudThemeToken.iconBox3xl)
        .height(CloudThemeToken.rowHeight4xl)
        .objectFit(ImageFit.Cover)
        .borderRadius(CloudThemeToken.controlRadiusMd)

      Column({ space: CloudThemeToken.spacingXl }) {
        Text(item.name)
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Progress({ value: item.progress, total: 100, type: ProgressType.Linear })
          .height(CloudThemeToken.thinProgressHeight)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(`${item.progress}%`)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
    }
    .width('100%')
    .padding(CloudThemeToken.spacingSection)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder sectionWaiting() {
    if (this.getWaitingItems().length > 0) {
      SectionHeader({ title: '待备份', count: this.getWaitingItems().length });
      this.photoGrid(this.getWaitingItems().slice(0, 24), PhotoBackupStatus.WAITING);
    } else if (this.getPhotos().length === 0) {
      this.emptyState();
    }
  }

  @Builder sectionFailed() {
    if (this.getFailedItems().length > 0) {
      SectionHeader({ title: '失败', count: this.getFailedItems().length });
      this.failedActionCard();
      this.photoGrid(this.getFailedItems().slice(0, 12), PhotoBackupStatus.FAILED);
    }
  }

  @Builder failedActionCard() {
    Column({ space: CloudThemeToken.spacingCard }) {
      Row() {
        Column({ space: CloudThemeToken.spacingXs }) {
          Text('部分图片备份失败')
            .fontSize(CloudThemeToken.textSizeBodyPlus)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
          Text(this.getFirstFailureMessage())
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('重试')
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .height(CloudThemeToken.rowHeightSm)
          .backgroundColor(CloudThemeToken.dangerSoft)
          .fontColor(CloudThemeToken.danger)
          .onClick(() => {
            this.startBackup();
          })
      }
      .width('100%')

      if (this.getSettingsWifiOnly()) {
        Text('如果当前设备没有 Wi-Fi，可在设置中临时改为任意网络后再重试。')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
          .width('100%')
      }
    }
    .width('100%')
    .padding(CloudThemeToken.spacingPanel)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.dangerSoft)
  }

  getFirstFailureMessage(): string {
    let failed = this.getFailedItems();
    if (failed.length === 0) {
      return '请稍后重试备份。';
    }
    let message = failed[0].error;
    return message.length > 0 ? message : '请稍后重试备份。';
  }

  @Builder sectionCompleted() {
    if (this.getCompletedItems().length > 0) {
      SectionHeader({ title: '最近完成', count: this.getCompletedItems().length });
      this.photoGrid(this.getCompletedItems().slice(0, 18), PhotoBackupStatus.COMPLETED);
    }
  }

  @Builder sectionBackupHistory() {
    if (this.getBackupPathHistory().length > 0) {
      SectionHeader({ title: '备份历史', count: this.getBackupPathHistory().length });
      Column({ space: CloudThemeToken.spacingCard }) {
        ForEach(this.getBackupPathHistory(), (history: PhotoBackupPathHistory) => {
          this.backupHistoryRow(history);
        }, (history: PhotoBackupPathHistory) => history.path)
      }
      .width('100%')
    }
  }

  @Builder backupHistoryRow(history: PhotoBackupPathHistory) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Column({ space: CloudThemeToken.spacingXs }) {
        Row({ space: CloudThemeToken.spacingXl }) {
          Text(history.path)
            .fontSize(CloudThemeToken.textSizeBodyPlus)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (history.isCurrent) {
            Text('当前')
              .fontSize(CloudThemeToken.textSizeMicro)
              .fontColor(CloudThemeToken.primary)
              .padding({ left: CloudThemeToken.spacingXl, right: CloudThemeToken.spacingXl, top: CloudThemeToken.spacingTiny, bottom: CloudThemeToken.spacingTiny })
              .borderRadius(CloudThemeToken.controlRadiusMd)
              .backgroundColor(CloudThemeToken.primarySoft)
          }
        }
        .width('100%')

        Text(`${history.count} 张图片已记录为已备份`)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(CloudThemeToken.spacingPanel)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(history.isCurrent ? CloudThemeToken.surface : CloudThemeToken.surfaceSubtle)
    .border({ width: history.isCurrent ? 1 : 0, color: CloudThemeToken.line })
  }

  @Builder photoGrid(items: PhotoBackupItem[], status: PhotoBackupStatus) {
    Grid() {
      ForEach(items, (item: PhotoBackupItem) => {
        GridItem() {
          Stack({ alignContent: Alignment.TopEnd }) {
            Image(item.uri)
              .width('100%')
              .aspectRatio(1)
              .objectFit(ImageFit.Cover)
              .borderRadius(CloudThemeToken.controlRadiusLg)

            Text(this.getBadgeText(status))
              .fontSize(CloudThemeToken.textSizeTiny)
              .fontColor(CloudThemeToken.onPrimary)
              .padding({ left: CloudThemeToken.spacingMd, right: CloudThemeToken.spacingMd, top: CloudThemeToken.spacingTiny, bottom: CloudThemeToken.spacingTiny })
              .backgroundColor(this.getBadgeColor(status))
              .borderRadius(CloudThemeToken.controlRadiusSm)
              .margin(6)
          }
          .width('100%')
          .aspectRatio(1)
        }
      }, (item: PhotoBackupItem) => item.id)
    }
    .columnsTemplate(this.getPhotoGridColumnsTemplate())
    .maxCount(this.getPhotoGridColumns())
    .columnsGap(8)
    .rowsGap(8)
    .width('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      if (!Number.isNaN(width) && Math.abs(width - this.photoGridWidth) >= 1) {
        this.photoGridWidth = width;
      }
    })
  }

  getBadgeText(status: PhotoBackupStatus): string {
    switch (status) {
      case PhotoBackupStatus.COMPLETED:
        return '已备份';
      case PhotoBackupStatus.FAILED:
        return '失败';
      default:
        return '待传';
    }
  }

  getBadgeColor(status: PhotoBackupStatus): ResourceColor {
    switch (status) {
      case PhotoBackupStatus.COMPLETED:
        return CloudThemeToken.success;
      case PhotoBackupStatus.FAILED:
        return CloudThemeToken.danger;
      default:
        return CloudThemeToken.primary;
    }
  }

  getPhotoGridColumns(): number {
    if (this.photoGridWidth >= CloudThemeToken.wideBreakpoint) {
      return 6;
    }
    if (this.photoGridWidth >= CloudThemeToken.tabletBreakpoint) {
      return 5;
    }
    if (this.photoGridWidth >= CloudThemeToken.twoColumnBreakpoint) {
      return 4;
    }
    return 3;
  }

  getPhotoGridColumnsTemplate(): string {
    const columns = this.getPhotoGridColumns();
    let templates: string[] = [];
    for (let index = 0; index < columns; index++) {
      templates.push('1fr');
    }
    return templates.join(' ');
  }

  @Builder emptyState() {
    EmptyState({
      icon: $r('app.media.ic_select_photos'),
      title: this.getSettingsEnabled() ? '还没有扫描到本地图片' : '开启相册备份后开始扫描',
      description: 'Cloudrs 只会上传备份，不会删除你的本地照片。',
      actionText: this.getSettingsEnabled() ? '重新扫描' : '开启备份',
      secondaryActionText: this.getSettingsEnabled() ? '选择图片加入备份' : undefined,
      onAction: () => {
        if (this.getSettingsEnabled()) {
          this.scanLocalPhotos();
        } else {
          this.showSettings = true;
        }
      },
      onSecondaryAction: () => {
        this.pickPhotosForBackup();
      }
    })
  }

  @Builder settingsPanel() {
    Column({ space: CloudThemeToken.spacingPage }) {
      Row() {
        Text('相册备份设置')
          .fontSize(CloudThemeToken.textSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_xmark'))
            .width(CloudThemeToken.iconLg)
            .height(CloudThemeToken.iconLg)
            .fillColor(CloudThemeToken.textSecondary)
        }
          .width(CloudThemeToken.smallIconButtonSize)
          .height(CloudThemeToken.smallIconButtonSize)
          .borderRadius(CloudThemeToken.controlRadius)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .onClick(() => {
            this.showSettings = false;
          })
      }
      .width('100%')

      Row() {
        Text('开启相册备份')
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settingsEnabled })
          .id(`photo-backup-enabled-${this.settingsEnabled}`)
          .onChange((value: boolean) => {
            this.updateSettings((settings: PhotoBackupSettings) => {
              settings.enabled = value;
            });
            if (value) {
              this.scanLocalPhotos();
            }
          })
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight2xl)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.surfaceSubtle)

      this.pathRow();

      Column({ space: CloudThemeToken.spacingXl }) {
        Text('网络条件')
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontWeight(FontWeight.Medium)
          .width('100%')
        Row({ space: CloudThemeToken.spacingXl }) {
          Text('仅 Wi-Fi')
            .fontSize(CloudThemeToken.textSizeBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.settingsWifiOnly ? CloudThemeToken.onPrimary : CloudThemeToken.textPrimary)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(CloudThemeToken.iconBoxMd)
            .borderRadius(CloudThemeToken.controlRadius)
            .backgroundColor(this.settingsWifiOnly ? CloudThemeToken.primary : CloudThemeToken.surfaceSubtle)
            .align(Alignment.Center)
            .id(`photo-backup-wifi-only-${this.settingsWifiOnly}`)
            .onClick(() => {
              this.updateSettings((settings: PhotoBackupSettings) => {
                settings.wifiOnly = true;
              });
            })

          Text('任意网络')
            .fontSize(CloudThemeToken.textSizeBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(!this.settingsWifiOnly ? CloudThemeToken.onPrimary : CloudThemeToken.textPrimary)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(CloudThemeToken.iconBoxMd)
            .borderRadius(CloudThemeToken.controlRadius)
            .backgroundColor(!this.settingsWifiOnly ? CloudThemeToken.primary : CloudThemeToken.surfaceSubtle)
            .align(Alignment.Center)
            .id(`photo-backup-any-network-${this.settingsWifiOnly}`)
            .onClick(() => {
              this.updateSettings((settings: PhotoBackupSettings) => {
                settings.wifiOnly = false;
              });
              if (this.backupState === PhotoBackupState.WAITING_NETWORK) {
                this.backupState = PhotoBackupState.IDLE;
              }
            })
        }
      }

      Row() {
        Text('自动备份')
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settingsAutoBackup })
          .id(`photo-backup-auto-${this.settingsAutoBackup}`)
          .onChange((value: boolean) => {
            this.updateSettings((settings: PhotoBackupSettings) => {
              settings.autoBackup = value;
            });
          })
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight2xl)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.surfaceSubtle)

      Row({ space: CloudThemeToken.spacingCard }) {
        Button('重新扫描本地相册')
          .layoutWeight(1)
          .height(CloudThemeToken.rowHeightXl)
          .onClick(() => {
            this.showSettings = false;
            this.scanLocalPhotos();
          })
        Button('选择图片加入')
          .layoutWeight(1)
          .height(CloudThemeToken.rowHeightXl)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick(() => {
            this.pickPhotosForBackup();
          })
      }
      .width('100%')

      Text('备份只会上传本地图片到远程路径，不会删除本地照片，也不会自动删除云端文件。')
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
        .width('100%')
    }
    .padding(CloudThemeToken.spacingPage)
    .width('100%')
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder pathRow() {
    Row() {
      Column({ space: CloudThemeToken.spacingXs }) {
        Text('备份路径')
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
        Text(this.getBackupPathText())
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Image($r('app.media.ic_chevron_right'))
        .width(CloudThemeToken.iconSm)
        .height(CloudThemeToken.iconSm)
        .fillColor(CloudThemeToken.textSecondary)
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight5xl)
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
    .onClick(() => {
      this.openPathSelectSheet();
    })
  }

  @Builder pathSelectSheet() {
    PathSelectSheet({
      title: $r('app.string.backup_to'),
      filterDirId: '',
      onClose: (isFinished: boolean, path?: string) => {
        this.closePathSelectSheet();
        if (isFinished && path && path.length > 0) {
          this.updateRemotePath(path);
        }
      }
    })
  }

  private openPathSelectSheet(): void {
    this.showPathSelect = true;
  }

  private closePathSelectSheet(): void {
    this.showPathSelect = false;
  }

  getAbilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      return undefined
    }
    return hostContext as common.UIAbilityContext
  }
}
