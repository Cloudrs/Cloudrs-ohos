import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
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
import { showToast } from '../../utils/ToastUtil';
import { CloudThemeToken } from '../../model/CloudTheme';
import { EmptyState } from '../../components/EmptyState';
import { CloudIconButton } from '../../components/CloudIconButton';
import { FileSystemUtil } from '../../utils/FileSystemUtil';
import { NetworkStateUtil } from '../../utils/NetworkStateUtil';
import { DirectoryInfo, ObjectInfo } from '../../model/net/ApiTypes';
import LazyDataSource from '../../utils/LazyDataSource';
import { PhotoBackupDrawer } from '../../components/PhotoBackupDrawer';
import { PhotoGalleryGrid } from '../../components/PhotoGalleryGrid';
import { PhotoGallerySegment } from '../../components/PhotoGallerySegment';
import { GallerySegment, PhotoGroup, groupByDate, groupByAlbum } from '../../model/PhotoGalleryModel';
import { PhotoBackupSettingsStore, PHOTO_BACKUP_REVISION_KEY } from '../../model/PhotoBackupSettingsStore';
import { PhotoLocalPreviewParam } from '../../model/Params';
import { CloudRouter } from '../../utils/CloudRouter';

const TAG: string = 'TabPictures';

// Max number of user albums to enumerate when building the uri -> albumName
// map during a scan. Keeps album mapping bounded on large libraries.
const ALBUM_SCAN_LIMIT: number = 60;

class PhotoBackupThumbnailCache {
  static data: Map<string, PixelMap> = new Map<string, PixelMap>();

  static snapshot(): Map<string, PixelMap> {
    return new Map<string, PixelMap>(PhotoBackupThumbnailCache.data);
  }

  static set(id: string, pixelMap: PixelMap): void {
    const next = new Map<string, PixelMap>(PhotoBackupThumbnailCache.data);
    next.set(id, pixelMap);
    while (next.size > CloudThemeToken.photoBackupThumbnailCacheLimit) {
      const firstKey = next.keys().next().value as string | undefined;
      if (!firstKey) {
        break;
      }
      next.delete(firstKey);
    }
    PhotoBackupThumbnailCache.data = next;
  }
}

@Component
export struct TabPictures {
  @Link overLap: boolean
  @Watch('onActiveStateChanged')
  @Prop isActive: boolean = false
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0
  @Provide photoBackupThumbs: Map<string, PixelMap> = new Map<string, PixelMap>();
  @State settingsEnabled: boolean = false;
  @State settingsRemotePath: string = '/Photos/Camera';
  @State settingsWifiOnly: boolean = true;
  @State settingsAutoBackup: boolean = true;
  @State settingsUploadConcurrent: number = CloudThemeToken.photoBackupDefaultConcurrent;
  @State settingsLastScanAt: number = 0;
  @State backupState: PhotoBackupState = PhotoBackupState.IDLE;
  @State photos: PhotoBackupItem[] = [];
  @State selectedIndexes: number[] = [CloudThemeToken.primarySegmentIndex];
  @State isScanning: boolean = false;
  @State backupQueueDone: number = 0;
  @State backupQueueTotal: number = 0;
  @State shouldPauseBackup: boolean = false;
  @State permissionHint: string = '';
  @State settingsRevision: number = 0;
  @State localPhotoCount: number = 0;
  @State completedPhotoCount: number = 0;
  @State waitingPhotoCount: number = 0;
  @State failedPhotoCount: number = 0;
  @State uploadingPhotoCount: number = 0;
  @State localPhotoCountText: string = '0';
  @State uploadingPhotoCountText: string = '0';
  @State completedPhotoCountText: string = '0';
  @State waitingPhotoCountText: string = '0';
  @State failedPhotoCountText: string = '0';
  @State backupQueueText: string = '0/0';
  @State uploadingPreviewItems: PhotoBackupItem[] = [];
  @State waitingPreviewItems: PhotoBackupItem[] = [];
  @State failedPreviewItems: PhotoBackupItem[] = [];
  @State completedPreviewItems: PhotoBackupItem[] = [];
  @State uploadingPreviewDataSource: LazyDataSource<PhotoBackupItem> = new LazyDataSource();
  @State waitingPreviewDataSource: LazyDataSource<PhotoBackupItem> = new LazyDataSource();
  @State failedPreviewDataSource: LazyDataSource<PhotoBackupItem> = new LazyDataSource();
  @State completedPreviewDataSource: LazyDataSource<PhotoBackupItem> = new LazyDataSource();
  private doneIds: Set<string> = new Set<string>();
  private photoRecordsSaveTimer: number = -1;
  private doneIdsSaveTimer: number = -1;
  private completedPreviewFlushTimer: number = -1;
  private pendingCompletedPreviewItems: PhotoBackupItem[] = [];
  private remotePhotoNameCache: Set<string> | null = null;
  private photoCopyQueue: Promise<void> = Promise.resolve();
  private photoAssetCache: Map<string, photoAccessHelper.PhotoAsset> = new Map<string, photoAccessHelper.PhotoAsset>();
  private thumbnailLoadingIds: Set<string> = new Set<string>();
  private autoScanTimer: number = -1;
  private stalePhotoRefreshTimer: number = -1;
  @State drawerOpen: boolean = false;
  @State segment: GallerySegment = GallerySegment.TIME;
  @State galleryGroups: PhotoGroup[] = [];
  @StorageProp(PHOTO_BACKUP_REVISION_KEY) @Watch('onSettingsRevisionChanged') settingsMirrorRevision: number = 0;

  aboutToAppear(): void {
    this.photoBackupThumbs = PhotoBackupThumbnailCache.snapshot();
    this.bindPreviewDataSources();
    this.loadSettings();
    this.loadDoneIds();
    this.loadPhotoRecords();
    this.rebuildGroups();
    this.scheduleActiveAutoScan();
  }

  aboutToDisappear(): void {
    this.clearAutoScanTimer();
    this.clearStalePhotoRefreshTimer();
    this.stopCompletedPreviewFlush();
    this.flushDoneIdsSave();
    this.flushPhotoRecordsSave();
  }

  onActiveStateChanged(): void {
    if (!this.isActive) {
      this.clearAutoScanTimer();
      return;
    }
    this.scheduleActiveAutoScan();
  }

  bindPreviewDataSources(): void {
    const onPreviewDataGet = (index: number, item: PhotoBackupItem) => {
      if (item) {
        this.loadPhotoThumbnail(item);
      }
    };
    this.uploadingPreviewDataSource.onDataGet = onPreviewDataGet;
    this.waitingPreviewDataSource.onDataGet = onPreviewDataGet;
    this.failedPreviewDataSource.onDataGet = onPreviewDataGet;
    this.completedPreviewDataSource.onDataGet = onPreviewDataGet;
  }

  loadSettings(): void {
    this.applySettings(PhotoBackupSettingsStore.load());
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
    this.refreshPhotoStats();
  }

  saveDoneIds(refreshStats: boolean = true): void {
    this.persistDoneIds();
    if (refreshStats) {
      this.refreshPhotoStats();
    }
  }

  persistDoneIds(): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_DONE_IDS,
      JSON.stringify(Array.from(this.doneIds)));
  }

  scheduleDoneIdsSave(): void {
    if (this.doneIdsSaveTimer >= CloudThemeToken.zero) {
      clearTimeout(this.doneIdsSaveTimer);
    }
    this.doneIdsSaveTimer = setTimeout(() => {
      this.doneIdsSaveTimer = -1;
      this.persistDoneIds();
    }, CloudThemeToken.photoBackupSaveDebounceMs);
  }

  flushDoneIdsSave(): void {
    if (this.doneIdsSaveTimer >= CloudThemeToken.zero) {
      clearTimeout(this.doneIdsSaveTimer);
      this.doneIdsSaveTimer = -1;
    }
    this.persistDoneIds();
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
      this.refreshPhotoStats();
    }
  }

  savePhotoRecords(): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_ITEMS,
      JSON.stringify(this.getPhotos().map((item: PhotoBackupItem) => item.toData())));
    this.refreshPhotoStats();
  }

  persistPhotoRecords(): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_ITEMS,
      JSON.stringify(this.getPhotos().map((item: PhotoBackupItem) => item.toData())));
  }

  schedulePhotoRecordsSave(): void {
    if (this.photoRecordsSaveTimer >= CloudThemeToken.zero) {
      clearTimeout(this.photoRecordsSaveTimer);
    }
    this.photoRecordsSaveTimer = setTimeout(() => {
      this.photoRecordsSaveTimer = -1;
      this.persistPhotoRecords();
    }, CloudThemeToken.photoBackupSaveDebounceMs);
  }

  flushPhotoRecordsSave(): void {
    if (this.photoRecordsSaveTimer >= CloudThemeToken.zero) {
      clearTimeout(this.photoRecordsSaveTimer);
      this.photoRecordsSaveTimer = -1;
    }
    this.persistPhotoRecords();
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
    return this.localPhotoCount;
  }

  getCompletedCount(): number {
    return this.completedPhotoCount;
  }

  hasPhotoThumbnail(item: PhotoBackupItem): boolean {
    return this.photoBackupThumbs.has(item.id);
  }

  setPhotoThumbnail(item: PhotoBackupItem, pixelMap: PixelMap): void {
    PhotoBackupThumbnailCache.set(item.id, pixelMap);
    this.photoBackupThumbs = PhotoBackupThumbnailCache.snapshot();
  }

  async loadPhotoThumbnail(item: PhotoBackupItem): Promise<void> {
    const loadingId = item.id;
    if (this.hasPhotoThumbnail(item) || this.thumbnailLoadingIds.has(loadingId)) {
      return;
    }
    this.thumbnailLoadingIds.add(loadingId);
    try {
      const size: image.Size = {
        width: CloudThemeToken.photoBackupThumbnailSize,
        height: CloudThemeToken.photoBackupThumbnailSize
      };
      const asset = await this.getPhotoAssetForThumbnail(item);
      if (!asset) {
        console.warn(TAG, `photo thumbnail asset not found: name=${item.name}, uri=${item.uri}`);
        this.scheduleStalePhotoRefresh();
        return;
      }
      let loadedPixelMap: PixelMap;
      try {
        loadedPixelMap = await asset.getThumbnail(size);
      } catch (err) {
        console.warn(TAG, `load photo asset thumbnail failed: name=${item.name}, uri=${item.uri}, error=${(err as Error)?.message ?? err}`);
        return;
      }
      this.runInUiScope(() => {
        this.setPhotoThumbnail(item, loadedPixelMap);
      });
    } catch (err) {
      console.warn(TAG, `load photo thumbnail failed: ${(err as Error)?.message ?? err}`);
    } finally {
      this.thumbnailLoadingIds.delete(loadingId);
      this.thumbnailLoadingIds.delete(item.id);
    }
  }

  private async getPhotoAssetForThumbnail(item: PhotoBackupItem): Promise<photoAccessHelper.PhotoAsset | undefined> {
    const cachedAsset = this.photoAssetCache.get(item.id);
    if (cachedAsset) {
      this.updatePhotoItemFromAsset(item, cachedAsset);
      this.photoAssetCache.set(item.id, cachedAsset);
      return cachedAsset;
    }
    let asset = await this.findPhotoAssetByUri(item.uri);
    if (!asset) {
      asset = await this.findPhotoAssetBySignature(item);
    }
    if (asset) {
      this.updatePhotoItemFromAsset(item, asset);
      this.photoAssetCache.set(item.id, asset);
    }
    return asset;
  }

  private async findPhotoAssetByUri(uri: string): Promise<photoAccessHelper.PhotoAsset | undefined> {
    if (!uri || uri.length === 0) {
      return undefined;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (!context) {
      return undefined;
    }
    let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
    try {
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
      const fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [
          photoAccessHelper.PhotoKeys.URI,
          photoAccessHelper.PhotoKeys.PHOTO_TYPE,
          photoAccessHelper.PhotoKeys.DISPLAY_NAME,
          photoAccessHelper.PhotoKeys.SIZE,
          photoAccessHelper.PhotoKeys.DATE_MODIFIED
        ],
        predicates: predicates
      };
      fetchResult = await phAccessHelper.getAssets(fetchOptions);
      const assets: photoAccessHelper.PhotoAsset[] = await fetchResult.getAllObjects();
      if (assets.length === 0) {
        return undefined;
      }
      return assets[Constant.FIRST_ARRAY_INDEX];
    } catch (err) {
      console.warn(TAG, `find photo asset by uri failed: ${(err as Error)?.message ?? err}`);
      return undefined;
    } finally {
      if (fetchResult) {
        fetchResult.close();
      }
    }
  }

  private async findPhotoAssetBySignature(item: PhotoBackupItem): Promise<photoAccessHelper.PhotoAsset | undefined> {
    if (!item.name || item.name.length === 0) {
      return undefined;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (!context) {
      return undefined;
    }
    let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
    try {
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.IMAGE);
      predicates.equalTo(photoAccessHelper.PhotoKeys.DISPLAY_NAME, item.name);
      predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_MODIFIED);
      const fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [
          photoAccessHelper.PhotoKeys.URI,
          photoAccessHelper.PhotoKeys.PHOTO_TYPE,
          photoAccessHelper.PhotoKeys.DISPLAY_NAME,
          photoAccessHelper.PhotoKeys.SIZE,
          photoAccessHelper.PhotoKeys.DATE_MODIFIED
        ],
        predicates: predicates
      };
      fetchResult = await phAccessHelper.getAssets(fetchOptions);
      const assets: photoAccessHelper.PhotoAsset[] = await fetchResult.getAllObjects();
      if (assets.length === 0) {
        return undefined;
      }
      return this.pickBestPhotoAssetMatch(item, assets);
    } catch (err) {
      console.warn(TAG, `find photo asset by signature failed: ${(err as Error)?.message ?? err}`);
      return undefined;
    } finally {
      if (fetchResult) {
        fetchResult.close();
      }
    }
  }

  private pickBestPhotoAssetMatch(item: PhotoBackupItem,
    assets: photoAccessHelper.PhotoAsset[]): photoAccessHelper.PhotoAsset | undefined {
    let bestAsset: photoAccessHelper.PhotoAsset | undefined = undefined;
    let bestScore = -1;
    assets.forEach((asset: photoAccessHelper.PhotoAsset) => {
      const score = this.getPhotoAssetMatchScore(item, asset);
      if (score > bestScore) {
        bestScore = score;
        bestAsset = asset;
      }
    });
    return bestAsset;
  }

  private getPhotoAssetMatchScore(item: PhotoBackupItem, asset: photoAccessHelper.PhotoAsset): number {
    let score = 0;
    if (asset.displayName === item.name) {
      score += 4;
    }
    const assetSize = this.getPhotoAssetSize(asset);
    if (item.size > 0 && assetSize === item.size) {
      score += 5;
    }
    const assetModifiedAt = this.getPhotoAssetModifiedAt(asset);
    if (item.modifiedAt > 0 && Math.abs(assetModifiedAt - item.modifiedAt) <= CloudThemeToken.photoBackupDateMatchToleranceMs) {
      score += 3;
    }
    return score;
  }

  private updatePhotoItemFromAsset(item: PhotoBackupItem, asset: photoAccessHelper.PhotoAsset): void {
    const resolved = this.createBackupItem(asset.uri, asset.displayName,
      this.getPhotoAssetSize(asset), this.getPhotoAssetModifiedAt(asset),
      this.getPhotoAssetDimension(asset, photoAccessHelper.PhotoKeys.WIDTH),
      this.getPhotoAssetDimension(asset, photoAccessHelper.PhotoKeys.HEIGHT));
    this.updatePhotoItemFromResolved(item, resolved);
  }

  private getPhotoAssetSize(asset: photoAccessHelper.PhotoAsset): number {
    return (asset.get(photoAccessHelper.PhotoKeys.SIZE) as number) ?? 0;
  }

  private getPhotoAssetModifiedAt(asset: photoAccessHelper.PhotoAsset): number {
    return (asset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED) as number) ?? 0;
  }

  private getPhotoAssetDimension(asset: photoAccessHelper.PhotoAsset, key: photoAccessHelper.PhotoKeys): number {
    try {
      return (asset.get(key) as number) ?? 0;
    } catch (err) {
      return 0;
    }
  }

  refreshPhotoStats(): void {
    let waitingCount = 0;
    let uploadingCount = 0;
    let completedCount = 0;
    let failedCount = 0;
    let uploadingPreview: PhotoBackupItem[] = [];
    let waitingPreview: PhotoBackupItem[] = [];
    let failedPreview: PhotoBackupItem[] = [];
    let completedPreview: PhotoBackupItem[] = [];
    this.getPhotos().forEach((item: PhotoBackupItem) => {
      if (item.status === PhotoBackupStatus.WAITING) {
        waitingCount++;
        if (waitingPreview.length < CloudThemeToken.photoBackupWaitingPreviewLimit) {
          waitingPreview.push(item);
        }
      } else if (item.status === PhotoBackupStatus.UPLOADING) {
        uploadingCount++;
        uploadingPreview.push(item);
      } else if (item.status === PhotoBackupStatus.COMPLETED) {
        completedCount++;
        const completedPreviewLimit = this.isBackupRunning() ? CloudThemeToken.photoBackupActiveCompletedPreviewLimit :
          CloudThemeToken.photoBackupCompletedPreviewLimit;
        if (completedPreview.length < completedPreviewLimit) {
          completedPreview.push(item);
        }
      } else if (item.status === PhotoBackupStatus.FAILED) {
        failedCount++;
        if (failedPreview.length < CloudThemeToken.photoBackupFailedPreviewLimit) {
          failedPreview.push(item);
        }
      }
    });
    let currentPathDoneCount = this.getCurrentPathDoneCount();
    this.runInUiScope(() => {
      this.localPhotoCount = Math.max(this.getPhotos().length, currentPathDoneCount);
      this.completedPhotoCount = Math.max(completedCount, currentPathDoneCount);
      this.waitingPhotoCount = waitingCount;
      this.uploadingPhotoCount = uploadingCount;
      this.failedPhotoCount = failedCount;
      this.uploadingPreviewItems = uploadingPreview;
      this.waitingPreviewItems = waitingPreview;
      this.failedPreviewItems = failedPreview;
      this.completedPreviewItems = completedPreview;
      this.syncAllPreviewDataSources();
      this.refreshPhotoCountText();
      this.rebuildGroups();
    });
    this.preloadPreviewThumbnails(uploadingPreview);
    this.preloadPreviewThumbnails(waitingPreview);
    this.preloadPreviewThumbnails(failedPreview);
    this.preloadPreviewThumbnails(completedPreview);
  }

  preloadPreviewThumbnails(items: PhotoBackupItem[]): void {
    items.forEach((item: PhotoBackupItem) => {
      this.loadPhotoThumbnail(item);
    });
  }

  syncAllPreviewDataSources(): void {
    this.uploadingPreviewDataSource.replaceAll(this.uploadingPreviewItems);
    this.waitingPreviewDataSource.replaceAll(this.waitingPreviewItems);
    this.failedPreviewDataSource.replaceAll(this.failedPreviewItems);
    this.completedPreviewDataSource.replaceAll(this.completedPreviewItems);
  }

  syncPreviewDataSource(status: PhotoBackupStatus): void {
    if (status === PhotoBackupStatus.UPLOADING) {
      this.uploadingPreviewDataSource.replaceAll(this.uploadingPreviewItems);
    } else if (status === PhotoBackupStatus.WAITING) {
      this.waitingPreviewDataSource.replaceAll(this.waitingPreviewItems);
    } else if (status === PhotoBackupStatus.FAILED) {
      this.failedPreviewDataSource.replaceAll(this.failedPreviewItems);
    } else if (status === PhotoBackupStatus.COMPLETED) {
      this.completedPreviewDataSource.replaceAll(this.completedPreviewItems);
    }
  }

  refreshPhotoCountText(): void {
    const localText = this.localPhotoCount.toString();
    const uploadingText = this.uploadingPhotoCount.toString();
    const completedText = this.completedPhotoCount.toString();
    const waitingText = this.waitingPhotoCount.toString();
    const failedText = this.failedPhotoCount.toString();
    if (this.localPhotoCountText === localText &&
      this.uploadingPhotoCountText === uploadingText &&
      this.completedPhotoCountText === completedText &&
      this.waitingPhotoCountText === waitingText &&
      this.failedPhotoCountText === failedText) {
      return;
    }
    this.localPhotoCountText = localText;
    this.uploadingPhotoCountText = uploadingText;
    this.completedPhotoCountText = completedText;
    this.waitingPhotoCountText = waitingText;
    this.failedPhotoCountText = failedText;
  }

  runInUiScope(task: () => void): void {
    try {
      this.getUIContext().runScopedTask(task);
    } catch (err) {
      console.warn(TAG, `run ui scoped task failed: ${(err as Error)?.message ?? err}`);
      task();
    }
  }

  refreshBackupQueueText(): void {
    const nextText = `${this.backupQueueDone}/${this.backupQueueTotal}`;
    if (this.backupQueueText === nextText) {
      return;
    }
    this.backupQueueText = nextText;
  }

  resetBackupQueue(total: number): void {
    this.runInUiScope(() => {
      this.backupQueueDone = 0;
      this.backupQueueTotal = total;
      this.refreshBackupQueueText();
    });
  }

  markBackupQueueItemDone(): void {
    this.runInUiScope(() => {
      this.backupQueueDone++;
      this.refreshBackupQueueText();
    });
  }

  scheduleCompletedPreviewFlush(item: PhotoBackupItem): void {
    this.pendingCompletedPreviewItems.push(item);
    if (this.completedPreviewFlushTimer >= CloudThemeToken.zero) {
      return;
    }
    this.completedPreviewFlushTimer = setTimeout(() => {
      this.flushCompletedPreviewUpdates();
    }, CloudThemeToken.photoBackupPreviewFlushMs);
  }

  stopCompletedPreviewFlush(): void {
    if (this.completedPreviewFlushTimer >= CloudThemeToken.zero) {
      clearTimeout(this.completedPreviewFlushTimer);
      this.completedPreviewFlushTimer = -1;
    }
  }

  flushCompletedPreviewUpdates(): void {
    this.stopCompletedPreviewFlush();
    if (this.pendingCompletedPreviewItems.length === 0) {
      return;
    }
    const pendingItems = this.pendingCompletedPreviewItems.slice();
    this.pendingCompletedPreviewItems = [];
    this.runInUiScope(() => {
      let next = this.completedPreviewItems.slice();
      pendingItems.forEach((item: PhotoBackupItem) => {
        next = this.removePreviewItem(next, item);
        next.push(item);
      });
      const limit = this.isBackupRunning() ? CloudThemeToken.photoBackupActiveCompletedPreviewLimit :
        CloudThemeToken.photoBackupCompletedPreviewLimit;
      this.completedPreviewItems = next.slice(Math.max(next.length - limit, CloudThemeToken.zero));
      this.syncPreviewDataSource(PhotoBackupStatus.COMPLETED);
    });
  }

  movePhotoStats(previousStatus: PhotoBackupStatus, nextStatus: PhotoBackupStatus): void {
    if (previousStatus === nextStatus) {
      return;
    }
    if (previousStatus === PhotoBackupStatus.WAITING) {
      this.waitingPhotoCount = Math.max(this.waitingPhotoCount - 1, CloudThemeToken.zero);
    } else if (previousStatus === PhotoBackupStatus.UPLOADING) {
      this.uploadingPhotoCount = Math.max(this.uploadingPhotoCount - 1, CloudThemeToken.zero);
    } else if (previousStatus === PhotoBackupStatus.COMPLETED) {
      this.completedPhotoCount = Math.max(this.completedPhotoCount - 1, CloudThemeToken.zero);
    } else if (previousStatus === PhotoBackupStatus.FAILED) {
      this.failedPhotoCount = Math.max(this.failedPhotoCount - 1, CloudThemeToken.zero);
    }

    if (nextStatus === PhotoBackupStatus.WAITING) {
      this.waitingPhotoCount++;
    } else if (nextStatus === PhotoBackupStatus.UPLOADING) {
      this.uploadingPhotoCount++;
    } else if (nextStatus === PhotoBackupStatus.COMPLETED) {
      this.completedPhotoCount++;
    } else if (nextStatus === PhotoBackupStatus.FAILED) {
      this.failedPhotoCount++;
    }
  }

  removePreviewItem(items: PhotoBackupItem[], item: PhotoBackupItem): PhotoBackupItem[] {
    return items.filter((current: PhotoBackupItem) => current.id !== item.id);
  }

  addPreviewItem(items: PhotoBackupItem[], item: PhotoBackupItem, limit: number): PhotoBackupItem[] {
    let next = this.removePreviewItem(items, item);
    next.unshift(item);
    return next.slice(CloudThemeToken.zero, limit);
  }

  updatePhotoPreviewStatus(item: PhotoBackupItem, previousStatus: PhotoBackupStatus, nextStatus: PhotoBackupStatus): void {
    let previousPreviewChanged = false;
    let nextPreviewChanged = false;
    if (previousStatus === PhotoBackupStatus.UPLOADING) {
      this.uploadingPreviewItems = this.removePreviewItem(this.uploadingPreviewItems, item);
      previousPreviewChanged = true;
    } else if (previousStatus === PhotoBackupStatus.WAITING) {
      if (!this.isBackupRunning()) {
        this.waitingPreviewItems = this.removePreviewItem(this.waitingPreviewItems, item);
        previousPreviewChanged = true;
      }
    } else if (previousStatus === PhotoBackupStatus.FAILED) {
      this.failedPreviewItems = this.removePreviewItem(this.failedPreviewItems, item);
      previousPreviewChanged = true;
    } else if (previousStatus === PhotoBackupStatus.COMPLETED) {
      this.completedPreviewItems = this.removePreviewItem(this.completedPreviewItems, item);
      previousPreviewChanged = true;
    }

    if (nextStatus === PhotoBackupStatus.UPLOADING) {
      this.uploadingPreviewItems = this.addPreviewItem(this.uploadingPreviewItems, item, this.getSettingsUploadConcurrent());
      nextPreviewChanged = true;
    } else if (nextStatus === PhotoBackupStatus.WAITING) {
      this.waitingPreviewItems = this.addPreviewItem(this.waitingPreviewItems, item,
        CloudThemeToken.photoBackupWaitingPreviewLimit);
      nextPreviewChanged = true;
    } else if (nextStatus === PhotoBackupStatus.FAILED) {
      this.failedPreviewItems = this.addPreviewItem(this.failedPreviewItems, item,
        CloudThemeToken.photoBackupFailedPreviewLimit);
      nextPreviewChanged = true;
    } else if (nextStatus === PhotoBackupStatus.COMPLETED) {
      if (this.isBackupRunning()) {
        this.scheduleCompletedPreviewFlush(item);
      } else {
        this.completedPreviewItems = this.addPreviewItem(this.completedPreviewItems, item,
          CloudThemeToken.photoBackupCompletedPreviewLimit);
        nextPreviewChanged = true;
      }
    }

    if (previousPreviewChanged) {
      this.syncPreviewDataSource(previousStatus);
    }
    if (nextPreviewChanged) {
      this.syncPreviewDataSource(nextStatus);
    }
  }

  setPhotoStatus(item: PhotoBackupItem, status: PhotoBackupStatus, progress: number, error: string = ''): void {
    this.runInUiScope(() => {
      const previousStatus = item.status;
      item.status = status;
      item.progress = progress;
      item.error = error;
      this.movePhotoStats(previousStatus, status);
      this.updatePhotoPreviewStatus(item, previousStatus, status);
      this.refreshPhotoCountText();
    });
  }

  updatePhotoProgress(item: PhotoBackupItem, progress: number): void {
    this.runInUiScope(() => {
      item.progress = progress;
    });
  }

  isBackupRunning(): boolean {
    return this.backupState === PhotoBackupState.BACKING_UP;
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
      return `正在备份 ${this.backupQueueText} 张`;
    }
    if (this.backupState === PhotoBackupState.WAITING_NETWORK) {
      return '等待 Wi-Fi';
    }
    if (this.backupState === PhotoBackupState.PAUSED) {
      return `已暂停 ${this.backupQueueText} 张`;
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
    if (!this.hasBackupPath()) {
      return '选择路径';
    }
    if (this.waitingPhotoCount > 0) {
      return '立即备份';
    }
    if (this.failedPhotoCount > 0) {
      return '重试失败';
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
    settings.uploadConcurrent = this.settingsUploadConcurrent;
    settings.lastScanAt = this.settingsLastScanAt;
    return settings;
  }

  applySettings(settings: PhotoBackupSettings): void {
    this.settingsEnabled = settings.enabled;
    this.settingsRemotePath = settings.remotePath;
    this.settingsWifiOnly = settings.wifiOnly;
    this.settingsAutoBackup = settings.autoBackup;
    this.settingsUploadConcurrent = this.normalizeUploadConcurrent(settings.uploadConcurrent);
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

  getSettingsUploadConcurrent(): number {
    return this.settingsUploadConcurrent;
  }

  normalizeUploadConcurrent(value: number): number {
    return Math.min(Math.max(value, CloudThemeToken.photoBackupMinConcurrent), CloudThemeToken.photoBackupMaxConcurrent);
  }

  updateUploadConcurrent(delta: number): void {
    let nextValue = this.normalizeUploadConcurrent(this.getSettingsUploadConcurrent() + delta);
    if (nextValue === this.getSettingsUploadConcurrent()) {
      return;
    }
    this.updateSettings((settings: PhotoBackupSettings) => {
      settings.uploadConcurrent = nextValue;
    });
  }

  allowAnyNetworkBackup(): void {
    this.updateSettings((settings: PhotoBackupSettings) => {
      settings.wifiOnly = false;
    });
    if (this.backupState === PhotoBackupState.WAITING_NETWORK) {
      this.backupState = PhotoBackupState.IDLE;
    }
    showToast('已允许任意网络备份');
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
    this.backupState = this.waitingPhotoCount > 0 ? PhotoBackupState.IDLE : PhotoBackupState.COMPLETED;
    showToast('已切换备份路径，状态已重新同步');
  }

  scheduleActiveAutoScan(): void {
    if (!this.shouldRunActiveAutoScan() || this.autoScanTimer >= CloudThemeToken.zero) {
      return;
    }
    this.autoScanTimer = setTimeout(() => {
      this.autoScanTimer = -1;
      if (this.shouldRunActiveAutoScan()) {
        this.scanLocalPhotos(false, true);
      }
    }, CloudThemeToken.photoBackupAutoScanDelayMs);
  }

  clearAutoScanTimer(): void {
    if (this.autoScanTimer >= CloudThemeToken.zero) {
      clearTimeout(this.autoScanTimer);
      this.autoScanTimer = -1;
    }
  }

  scheduleStalePhotoRefresh(): void {
    if (!this.isActive || !this.getSettingsEnabled() || this.stalePhotoRefreshTimer >= CloudThemeToken.zero) {
      return;
    }
    this.stalePhotoRefreshTimer = setTimeout(() => {
      this.stalePhotoRefreshTimer = -1;
      if (this.isActive && this.getSettingsEnabled() && !this.isScanning) {
        this.scanLocalPhotos(true, true);
      }
    }, CloudThemeToken.photoBackupStaleRefreshDelayMs);
  }

  clearStalePhotoRefreshTimer(): void {
    if (this.stalePhotoRefreshTimer >= CloudThemeToken.zero) {
      clearTimeout(this.stalePhotoRefreshTimer);
      this.stalePhotoRefreshTimer = -1;
    }
  }

  shouldRunActiveAutoScan(): boolean {
    if (!this.isActive || !this.getSettingsEnabled() || this.isScanning || this.isBackupRunning()) {
      return false;
    }
    if (this.getPhotos().length === 0 || this.settingsLastScanAt <= CloudThemeToken.zero) {
      return true;
    }
    return new Date().getTime() - this.settingsLastScanAt >= CloudThemeToken.photoBackupAutoScanMinIntervalMs;
  }

  async scanLocalPhotos(forceFull: boolean = true, silent: boolean = false): Promise<void> {
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
      const modifiedFloor = forceFull ? CloudThemeToken.zero : this.getIncrementalModifiedFloor();
      if (modifiedFloor > CloudThemeToken.zero) {
        predicates.greaterThan(photoAccessHelper.PhotoKeys.DATE_MODIFIED, modifiedFloor);
      }
      predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.IMAGE);
      predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_MODIFIED);
      let fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [
          photoAccessHelper.PhotoKeys.URI,
          photoAccessHelper.PhotoKeys.PHOTO_TYPE,
          photoAccessHelper.PhotoKeys.DISPLAY_NAME,
          photoAccessHelper.PhotoKeys.SIZE,
          photoAccessHelper.PhotoKeys.DATE_MODIFIED,
          photoAccessHelper.PhotoKeys.WIDTH,
          photoAccessHelper.PhotoKeys.HEIGHT
        ],
        predicates: predicates
      };
      const albumNameByUri = await this.buildAlbumNameMap(phAccessHelper);
      let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> =
        await phAccessHelper.getAssets(fetchOptions);
      let nextPhotos: PhotoBackupItem[] = await this.readPhotoFetchResult(fetchResult, albumNameByUri);
      if (nextPhotos.length === 0 && forceFull) {
        this.permissionHint = '未扫描到本地图片。如果相册中已有图片，请检查相册读取权限，或手动选择图片加入备份。';
      } else if (forceFull && previousCount > 0 && nextPhotos.length < previousCount) {
        this.permissionHint = `本次系统扫描到 ${nextPhotos.length} 张，少于当前记录 ${previousCount} 张。如果数量不符合预期，请检查相册权限范围。`;
      }
      this.photos = this.mergePhotoList(nextPhotos, !forceFull);
      this.refreshPhotoStats();
      this.updateSettings((settings: PhotoBackupSettings) => {
        settings.lastScanAt = new Date().getTime();
      });
      if (nextPhotos.length > 0) {
        this.savePhotoRecords();
      }
      if (!silent) {
        const addedCount = Math.max(this.getPhotos().length - previousCount, CloudThemeToken.zero);
        showToast(forceFull ? `已扫描到 ${this.localPhotoCount} 张本地图片` :
          (addedCount > 0 ? `已发现 ${addedCount} 张新图片` : '没有发现新图片'));
      }
      this.backupState = this.waitingPhotoCount > 0 ? PhotoBackupState.IDLE : PhotoBackupState.COMPLETED;
    } catch (err) {
      let error = err as BusinessError;
      console.error(TAG, `scan failed: ${error.code}, ${error.message}`);
      if (!silent) {
        this.permissionHint = '相册扫描失败，请检查系统相册权限。也可以先使用“选择图片加入备份”继续备份指定图片。';
        showToast('扫描本地相册失败，请检查相册读取权限');
      }
      this.backupState = PhotoBackupState.FAILED;
    } finally {
      this.isScanning = false;
    }
  }

  async readPhotoFetchResult(fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset>,
    albumNameByUri?: Map<string, string>):
    Promise<PhotoBackupItem[]> {
    try {
      let assets: photoAccessHelper.PhotoAsset[] = await fetchResult.getAllObjects();
      let nextPhotos: PhotoBackupItem[] = [];
      assets.forEach((asset: photoAccessHelper.PhotoAsset) => {
        if (asset.photoType !== photoAccessHelper.PhotoType.IMAGE) {
          return;
        }
        const albumName = albumNameByUri?.get(asset.uri) ?? '';
        const item = this.createBackupItem(asset.uri, asset.displayName,
          this.getPhotoAssetSize(asset), this.getPhotoAssetModifiedAt(asset),
          this.getPhotoAssetDimension(asset, photoAccessHelper.PhotoKeys.WIDTH),
          this.getPhotoAssetDimension(asset, photoAccessHelper.PhotoKeys.HEIGHT),
          albumName);
        this.photoAssetCache.set(item.id, asset);
        nextPhotos.push(item);
      });
      return nextPhotos;
    } finally {
      fetchResult.close();
    }
  }

  /**
   * Enumerate user albums once and build a uri -> albumName map. Bounded to a
   * reasonable number of albums/assets to keep scanning fast on large libraries.
   * Returns an empty map on any failure (album names then fall back to '其他').
   */
  async buildAlbumNameMap(phAccessHelper: photoAccessHelper.PhotoAccessHelper): Promise<Map<string, string>> {
    const map: Map<string, string> = new Map<string, string>();
    let albumFetch: photoAccessHelper.FetchResult<photoAccessHelper.Album> | undefined = undefined;
    try {
      albumFetch = await phAccessHelper.getAlbums(photoAccessHelper.AlbumType.USER,
        photoAccessHelper.AlbumSubtype.USER_GENERIC);
      const albums: photoAccessHelper.Album[] = await albumFetch.getAllObjects();
      const albumLimit = Math.min(albums.length, ALBUM_SCAN_LIMIT);
      for (let i = 0; i < albumLimit; i++) {
        const album = albums[i];
        const albumName = album.albumName ?? '';
        if (albumName.length === 0) {
          continue;
        }
        let assetFetch: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
        try {
          const predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
          predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.IMAGE);
          const options: photoAccessHelper.FetchOptions = {
            fetchColumns: [photoAccessHelper.PhotoKeys.URI],
            predicates: predicates
          };
          assetFetch = await album.getAssets(options);
          const assets: photoAccessHelper.PhotoAsset[] = await assetFetch.getAllObjects();
          assets.forEach((asset: photoAccessHelper.PhotoAsset) => {
            if (!map.has(asset.uri)) {
              map.set(asset.uri, albumName);
            }
          });
        } catch (err) {
          console.warn(TAG, `read album assets failed: ${(err as Error)?.message ?? err}`);
        } finally {
          if (assetFetch) {
            assetFetch.close();
          }
        }
      }
    } catch (err) {
      console.warn(TAG, `build album name map failed: ${(err as Error)?.message ?? err}`);
    } finally {
      if (albumFetch) {
        albumFetch.close();
      }
    }
    return map;
  }

  getIncrementalModifiedFloor(): number {
    let modifiedAt = CloudThemeToken.zero;
    this.getPhotos().forEach((item: PhotoBackupItem) => {
      modifiedAt = Math.max(modifiedAt, item.modifiedAt);
    });
    return modifiedAt;
  }

  async pickPhotosForBackup(): Promise<void> {
    try {
      let options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = CloudThemeToken.photoBackupPickerMaxSelect;
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
        item.progress = item.status === PhotoBackupStatus.COMPLETED ? CloudThemeToken.percentageFull : CloudThemeToken.zero;
        return item;
      });
      let before = this.getPhotos().length;
      this.photos = this.mergePhotoList(selectedItems, true);
      this.refreshPhotoStats();
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

  createBackupItem(uri: string, name: string, size: number, modifiedAt: number,
    width: number = 0, height: number = 0, albumName: string = ''): PhotoBackupItem {
    let item = new PhotoBackupItem(uri, name.length > 0 ? name : this.getNameFromUri(uri), size, modifiedAt);
    item.status = this.isPhotoDone(item) ? PhotoBackupStatus.COMPLETED : PhotoBackupStatus.WAITING;
    item.progress = item.status === PhotoBackupStatus.COMPLETED ? CloudThemeToken.percentageFull : CloudThemeToken.zero;
    item.width = width > 0 ? width : 0;
    item.height = height > 0 ? height : 0;
    item.albumName = albumName;
    return item;
  }

  mergePhotoList(incoming: PhotoBackupItem[], keepExisting: boolean): PhotoBackupItem[] {
    const previousItems = this.getPhotos().slice();
    const usedPreviousIds: Set<string> = new Set<string>();
    let merged: PhotoBackupItem[] = keepExisting ? previousItems.slice() : [];
    incoming.forEach((item: PhotoBackupItem) => {
      const existingIndex = this.findExistingPhotoIndex(merged, item);
      if (existingIndex >= 0) {
        this.updatePhotoItemFromResolved(merged[existingIndex], item);
        return;
      }
      if (!keepExisting) {
        const previousIndex = this.findExistingPhotoIndex(previousItems, item);
        if (previousIndex >= 0 && !usedPreviousIds.has(previousItems[previousIndex].id)) {
          usedPreviousIds.add(previousItems[previousIndex].id);
          const previousItem = previousItems[previousIndex];
          this.updatePhotoItemFromResolved(previousItem, item);
          merged.push(previousItem);
          return;
        }
      }
      merged.push(item);
    });
    merged.forEach((item: PhotoBackupItem) => {
      this.applyDoneStatus(item, true);
    });
    merged.sort((left: PhotoBackupItem, right: PhotoBackupItem) => right.modifiedAt - left.modifiedAt);
    return merged;
  }

  private findExistingPhotoIndex(items: PhotoBackupItem[], incoming: PhotoBackupItem): number {
    let index = items.findIndex((current: PhotoBackupItem) => current.uri === incoming.uri || current.id === incoming.id);
    if (index >= 0) {
      return index;
    }
    return items.findIndex((current: PhotoBackupItem) => this.isSamePhotoBySignature(current, incoming));
  }

  private isSamePhotoBySignature(left: PhotoBackupItem, right: PhotoBackupItem): boolean {
    if (!left.name || !right.name || left.name !== right.name) {
      return false;
    }
    if (left.size > 0 && right.size > 0 && left.size !== right.size) {
      return false;
    }
    if (left.modifiedAt > 0 && right.modifiedAt > 0 &&
      Math.abs(left.modifiedAt - right.modifiedAt) > CloudThemeToken.photoBackupDateMatchToleranceMs) {
      return false;
    }
    return (left.size > 0 && right.size > 0) || (left.modifiedAt > 0 && right.modifiedAt > 0);
  }

  private updatePhotoItemFromResolved(target: PhotoBackupItem, resolved: PhotoBackupItem): void {
    const oldId = target.id;
    const oldDoneKey = this.getDoneKey(target);
    const wasDone = target.status === PhotoBackupStatus.COMPLETED || this.doneIds.has(oldDoneKey);
    const previousStatus = target.status;
    const previousProgress = target.progress;
    const previousError = target.error;
    target.uri = resolved.uri;
    target.name = resolved.name;
    target.size = resolved.size;
    target.modifiedAt = resolved.modifiedAt;
    target.id = resolved.id;
    if (resolved.width > 0 && resolved.height > 0) {
      target.width = resolved.width;
      target.height = resolved.height;
    }
    if (resolved.albumName.length > 0) {
      target.albumName = resolved.albumName;
    }
    if (wasDone || resolved.status === PhotoBackupStatus.COMPLETED) {
      target.status = PhotoBackupStatus.COMPLETED;
      target.progress = CloudThemeToken.percentageFull;
      target.error = '';
      this.doneIds.add(this.getDoneKey(target));
    } else {
      target.status = previousStatus;
      target.progress = previousProgress;
      target.error = previousError;
    }
    if (oldId !== target.id) {
      this.photoAssetCache.delete(oldId);
      this.scheduleDoneIdsSave();
      this.schedulePhotoRecordsSave();
    }
  }

  refreshDoneStatus(): void {
    this.photos = this.getPhotos().map((item: PhotoBackupItem) => {
      this.applyDoneStatus(item, true);
      return item;
    });
    this.refreshPhotoStats();
  }

  applyDoneStatus(item: PhotoBackupItem, resetNotDone: boolean): void {
    if (this.isPhotoDone(item)) {
      item.status = PhotoBackupStatus.COMPLETED;
      item.progress = CloudThemeToken.percentageFull;
      item.error = '';
      return;
    }
    if (resetNotDone && item.status !== PhotoBackupStatus.FAILED) {
      item.status = PhotoBackupStatus.WAITING;
      item.progress = CloudThemeToken.zero;
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

  getVisibleBackupPathHistory(): PhotoBackupPathHistory[] {
    return this.getBackupPathHistory().slice(CloudThemeToken.zero, CloudThemeToken.photoBackupHistoryPreviewLimit);
  }

  getHiddenBackupPathHistoryCount(): number {
    let hiddenCount = this.getBackupPathHistory().length - CloudThemeToken.photoBackupHistoryPreviewLimit;
    return Math.max(hiddenCount, CloudThemeToken.zero);
  }

  getNameFromUri(uri: string): string {
    let path = uri.split('?')[Constant.FIRST_ARRAY_INDEX];
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
      return (result.authResults ?? []).length > 0 &&
        result.authResults[Constant.FIRST_ARRAY_INDEX] === Constant.PERMISSION_AUTH_GRANTED;
    } catch (err) {
      let error = err as BusinessError;
      console.error(TAG, `request photo permission failed: ${error.code}, ${error.message}`);
      return false;
    }
  }

  startBackup(retryFailedOnly: boolean = false): void {
    if (!this.getSettingsEnabled()) {
      showToast('请在「我的 - 相册备份」中开启备份或选择路径');
      return;
    }
    if (!this.hasBackupPath()) {
      showToast('请在「我的 - 相册备份」中开启备份或选择路径');
      return;
    }
    if (this.getPhotos().length === 0) {
      this.scanLocalPhotos();
      return;
    }
    let failedItems = this.getFailedItems();
    let waitingItems = this.getWaitingItems();
    let targets = retryFailedOnly ? failedItems : (waitingItems.length > 0 ? waitingItems : failedItems);
    if (targets.length === 0) {
      showToast('没有需要备份的图片');
      return;
    }
    if (!this.canBackupNow()) {
      this.backupState = PhotoBackupState.WAITING_NETWORK;
      showToast('当前不是 Wi-Fi，已暂停相册备份');
      return;
    }
    this.resetBackupQueue(targets.length);
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
    let nextIndex = 0;
    const workerCount = Math.min(this.getSettingsUploadConcurrent(), targets.length);
    const runWorker = async (): Promise<void> => {
      while (nextIndex < targets.length && !this.shouldPauseBackup) {
        const currentIndex = nextIndex;
        nextIndex++;
        await this.backupItem(targets[currentIndex], currentIndex);
        this.markBackupQueueItemDone();
      }
    };
    try {
      this.remotePhotoNameCache = await this.loadRemotePhotoNameCache();
      let workers: Promise<void>[] = [];
      for (let index = CloudThemeToken.zero; index < workerCount; index++) {
        workers.push(runWorker());
      }
      await Promise.all(workers);
      if (this.shouldPauseBackup) {
        this.flushCompletedPreviewUpdates();
        this.runInUiScope(() => {
          this.backupState = PhotoBackupState.PAUSED;
        });
        this.flushDoneIdsSave();
        this.flushPhotoRecordsSave();
        this.refreshPhotoStats();
        return;
      }
      this.flushCompletedPreviewUpdates();
      this.flushDoneIdsSave();
      this.flushPhotoRecordsSave();
      this.refreshPhotoStats();
      if (this.uploadingPhotoCount === 0) {
        this.runInUiScope(() => {
          this.backupState = this.waitingPhotoCount > 0 ? PhotoBackupState.IDLE : PhotoBackupState.COMPLETED;
        });
      }
    } finally {
      this.remotePhotoNameCache = null;
    }
  }

  async backupItem(item: PhotoBackupItem, index: number): Promise<void> {
    let localPath = '';
    try {
      this.setPhotoStatus(item, PhotoBackupStatus.UPLOADING, CloudThemeToken.photoBackupStartProgress);
      if (await this.remotePhotoExists(item)) {
        this.setPhotoStatus(item, PhotoBackupStatus.COMPLETED, CloudThemeToken.percentageFull);
        this.markRemotePhotoKnown(item);
        this.doneIds.add(this.getDoneKey(item));
        this.scheduleDoneIdsSave();
        this.schedulePhotoRecordsSave();
        return;
      }
      localPath = await this.copyPhotoToCache(item);
      this.updatePhotoProgress(item, CloudThemeToken.photoBackupCopyProgress);
      await this.uploadPhoto(localPath, this.getRemoteFilePath(item), item);
      this.setPhotoStatus(item, PhotoBackupStatus.COMPLETED, CloudThemeToken.percentageFull);
      this.markRemotePhotoKnown(item);
      this.doneIds.add(this.getDoneKey(item));
      this.scheduleDoneIdsSave();
      this.schedulePhotoRecordsSave();
    } catch (err) {
      this.setPhotoStatus(item, PhotoBackupStatus.FAILED, CloudThemeToken.zero, this.getErrorMessage(err));
      this.schedulePhotoRecordsSave();
    } finally {
      if (localPath.length > 0) {
        await FileSystemUtil.unlinkIfExists(localPath);
      }
    }
  }

  async copyPhotoToCache(item: PhotoBackupItem): Promise<string> {
    return this.withPhotoCopySlot(async (): Promise<string> => {
      let context = this.getAbilityContext();
      if (!context) {
        throw new Error('应用上下文不可用');
      }
      let fileName = this.sanitizeFileName(item.name.length > 0 ? item.name : 'photo.jpg');
      let localPath = `${context.cacheDir}/photo_backup_${new Date().getTime()}_${fileName}`;
      await FileSystemUtil.copyUriToPathInBackground(item.uri, localPath);
      return localPath;
    });
  }

  async withPhotoCopySlot(task: () => Promise<string>): Promise<string> {
    let releaseCopySlot: () => void = () => {};
    const previousCopy = this.photoCopyQueue;
    this.photoCopyQueue = new Promise<void>((resolve: () => void) => {
      releaseCopySlot = resolve;
    });
    await previousCopy;
    try {
      return await task();
    } finally {
      releaseCopySlot();
    }
  }

  uploadPhoto(localPath: string, remotePath: string, item: PhotoBackupItem): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Error) => void) => {
      CloudApi.uploadLocalFile(localPath, remotePath, false, {
        onStart: () => {
          this.updatePhotoProgress(item, CloudThemeToken.photoBackupUploadStartProgress);
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

  loadRemotePhotoNameCache(): Promise<Set<string>> {
    return new Promise<Set<string>>((resolve: (value: Set<string>) => void) => {
      CloudApi.getFilesInfo(this.normalizeRemotePath(this.getSettingsRemotePath()), {
        onSuccess: (data: DirectoryInfo) => {
          let names = new Set<string>();
          (data.objects ?? []).forEach((object: ObjectInfo) => {
            names.add(object.name);
          });
          resolve(names);
        },
        onFailure: (msg: string) => {
          console.info(TAG, `load remote photo names skipped: ${msg}`);
          resolve(new Set<string>());
        }
      });
    });
  }

  markRemotePhotoKnown(item: PhotoBackupItem): void {
    this.remotePhotoNameCache?.add(item.name);
  }

  remotePhotoExists(item: PhotoBackupItem): Promise<boolean> {
    if (this.remotePhotoNameCache) {
      return Promise.resolve(this.remotePhotoNameCache.has(item.name));
    }
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      CloudApi.getFilesInfo(this.normalizeRemotePath(this.getSettingsRemotePath()), {
        onSuccess: (data: DirectoryInfo) => {
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

  getTopInset(): number {
    return CloudThemeToken.getSafeTopInset(this.topRectHeight);
  }

  rebuildGroups(): void {
    const list = this.getPhotos();
    this.galleryGroups = this.segment === GallerySegment.TIME
      ? groupByDate(list, new Date()) : groupByAlbum(list);
  }

  onSettingsRevisionChanged(): void {
    this.loadSettings();
    this.rebuildGroups();
  }

  openLocalPreview(item: PhotoBackupItem): void {
    const flat = this.getPhotos();
    const idx = flat.findIndex((it: PhotoBackupItem) => it.id === item.id);
    CloudRouter.push(Constant.PHOTO_LOCAL_PREVIEW_PAGE,
      new PhotoLocalPreviewParam(flat, Math.max(idx, 0), this.getSettingsEnabled()));
  }

  retryFailedPhotos(): void {
    this.getFailedItems().forEach((it: PhotoBackupItem) =>
      this.setPhotoStatus(it, PhotoBackupStatus.WAITING, 0, ''));
    this.startBackup();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: CloudThemeToken.sectionGap }) {
        Row() {
          Text('相册')
            .fontSize(CloudThemeToken.textSizeTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
            .layoutWeight(1)
          CloudIconButton({
            icon: $r('app.media.ic_chevron_down'),
            iconColor: CloudThemeToken.textPrimary,
            onAction: () => {
              this.getUIContext().animateTo({
                duration: CloudThemeToken.defaultAnimationDuration,
                curve: Curve.EaseOut
              }, () => {
                this.drawerOpen = !this.drawerOpen;
              });
            }
          })
            .rotate({ angle: this.drawerOpen ? 180 : 0 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.drawerOpen) {
          PhotoBackupDrawer({
            backupEnabled: this.getSettingsEnabled(),
            running: this.isBackupRunning(),
            paused: this.backupState === PhotoBackupState.PAUSED,
            completedCount: this.completedPhotoCount,
            localCount: this.localPhotoCount,
            uploadingCount: this.uploadingPhotoCount,
            waitingCount: this.waitingPhotoCount,
            failedCount: this.failedPhotoCount,
            statusText: this.getStatusText(),
            onPrimary: () => { this.startBackup(); },
            onPauseResume: () => { this.isBackupRunning() ? this.pauseBackup() : this.startBackup(); },
            onRetryFailed: () => { this.retryFailedPhotos(); },
            onGoEnable: () => { showToast('请在「我的 - 相册备份」中开启备份'); }
          })
        }

        if (this.getPhotos().length > 0) {
          PhotoGallerySegment({
            current: this.segment,
            onSelect: (seg: GallerySegment) => {
              this.segment = seg;
              this.rebuildGroups();
            }
          })
        }

        if (this.getPhotos().length === 0 && this.permissionHint.length > 0) {
          Column() {
            EmptyState({
              icon: $r('app.media.ic_lock_fill'),
              title: '无法读取相册',
              description: this.permissionHint,
              actionText: '授权读取相册',
              onAction: () => { this.scanLocalPhotos(true, false); }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.getPhotos().length === 0) {
          Column() {
            EmptyState({
              icon: $r('app.media.ic_select_photos'),
              title: '还没有本地照片',
              description: '扫描本地相册后，照片会显示在这里。',
              actionText: '扫描相册',
              onAction: () => {
                this.scanLocalPhotos(true, false);
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          PhotoGalleryGrid({
            groups: this.galleryGroups,
            backupEnabled: this.getSettingsEnabled(),
            onRequestThumb: (item: PhotoBackupItem) => { this.loadPhotoThumbnail(item); },
            onTapPhoto: (item: PhotoBackupItem) => { this.openLocalPreview(item); }
          })
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: CloudThemeToken.pagePadding,
        right: CloudThemeToken.pagePadding,
        top: this.getTopInset() + CloudThemeToken.scaffoldTopPadding,
        bottom: this.tabBarHeight + CloudThemeToken.scaffoldBottomPadding
      })
      .backgroundColor(CloudThemeToken.background)
    }
    .width('100%')
    .height('100%')
  }


  getAbilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      return undefined
    }
    return hostContext as common.UIAbilityContext
  }
}
