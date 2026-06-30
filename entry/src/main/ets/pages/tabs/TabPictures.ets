import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connection, http } from '@kit.NetworkKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import Constant from '../../model/Constant';
import {
  PhotoBackupItem,
  PhotoBackupItemData,
  PhotoBackupSettings,
  PhotoBackupState,
  PhotoBackupStatus
} from '../../model/PhotoBackupModel';
import { CloudApi } from '../../model/net/CloudApi';
import UserPreferences from '../../model/UserPreferences';
import AppLogger from '../../utils/AppLogger';
import { showToast } from '../../utils/ToastUtil';
import { CloudBreakpoint, CloudThemeToken } from '../../model/CloudTheme';
import { EmptyState } from '../../components/EmptyState';
import { CloudIconButton } from '../../components/CloudIconButton';
import { FileSystemUtil } from '../../utils/FileSystemUtil';
import { NetworkStateUtil } from '../../utils/NetworkStateUtil';
import { DirectoryInfo, ObjectInfo } from '../../model/net/ApiTypes';
import LazyDataSource from '../../utils/LazyDataSource';
import { PhotoGalleryGrid } from '../../components/PhotoGalleryGrid';
import { GallerySegment, PhotoGroup, groupByDate, groupByAlbum } from '../../model/PhotoGalleryModel';
import { PhotoBackupSettingsStore, PHOTO_BACKUP_REVISION_KEY } from '../../model/PhotoBackupSettingsStore';
import { PhotoLocalPreviewParam, ImagePreview } from '../../model/Params';
import { CloudRouter } from '../../utils/CloudRouter';
import {
  HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, DividerShowType, hdsMaterial
} from '@kit.UIDesignKit';

const TAG: string = 'TabPictures';

// Max number of user albums to enumerate when building the uri -> albumName
// map during a scan. Keeps album mapping bounded on large libraries.
const ALBUM_SCAN_LIMIT: number = 60;

// photoAccessHelper DATE_MODIFIED/DATE_ADDED are in SECONDS. Normalize any
// second-scale timestamp to milliseconds (values below this threshold are
// treated as seconds; year-2001-in-ms is ~1e12).
const SECONDS_TO_MS_THRESHOLD: number = 1e12;

function toMillis(value: number): number {
  return value > 0 && value < SECONDS_TO_MS_THRESHOLD ? value * 1000 : value;
}

// Left-center frosted capsule for switching the 时间 / 相册 grouping.
const SWITCHER_ITEM_SIZE: number = 44;
const SWITCHER_PADDING: number = 4;
const SWITCHER_GAP: number = 4;
// 网络/设置/扫描事件后，自动备份评估的防抖间隔（合并短时间内的多次网络事件）。
const AUTO_BACKUP_DEBOUNCE_MS: number = 1500;
const BACKUP_GRID_REFRESH_MS: number = 1500;
const GRID_SCROLL_QUIET_MS: number = 400;

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
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0
  @StorageProp(Constant.SIDEBAR_VISIBLE) sidebarVisible: boolean = true
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
  private mediaChangeRegistered: boolean = false;
  private mediaChangeDebounceTimer: number = -1;
  private mediaChangeHelper: photoAccessHelper.PhotoAccessHelper | undefined = undefined;
  private cachedAlbumNameMap: Map<string, string> | undefined = undefined;
  private netConnection: connection.NetConnection | undefined = undefined;
  private netRegistered: boolean = false;
  private autoBackupDebounceTimer: number = -1;
  private deferredLoadTimer: number = -1;
  // 启动延后加载是否已完成。未完成前 applyPendingRemoteRemovals 不消费待移除名单，
  // 避免 onActiveStateChanged 抢在 photos 加载前清空名单、丢失标记撤销。
  private photosLoaded: boolean = false;
  private lastRemotePath: string = '';
  @State drawerOpen: boolean = false;
  @State segment: GallerySegment = GallerySegment.TIME;
  @State galleryGroups: PhotoGroup[] = [];
  @State isRefreshing: boolean = false;
  @State refreshPullOffset: number = 0;
  private gridScroller: Scroller = new Scroller();
  @StorageProp(PHOTO_BACKUP_REVISION_KEY) @Watch('onSettingsRevisionChanged') settingsMirrorRevision: number = 0;

  aboutToAppear(): void {
    this.photoBackupThumbs = PhotoBackupThumbnailCache.snapshot();
    this.bindPreviewDataSources();
    this.loadSettings();
    this.lastRemotePath = this.normalizeRemotePath(this.getSettingsRemotePath());
    this.loadDoneIds();
    this.scheduleActiveAutoScan();
    this.syncMediaChangeRegistration();
    this.registerNetworkListener();
    // 解析数千条记录 + 建组较重，推到下一拍执行，避免阻塞 app 启动帧、导致刚进应用切页卡顿。
    // 相册非默认 Tab，启动时不可见；setTimeout(0) 在用户手动点击切页前即完成加载，无感知。
    this.deferredLoadTimer = setTimeout(() => {
      this.deferredLoadTimer = -1;
      this.loadPhotoRecords();
      this.applyPendingRemoteRemovals();
      this.rebuildGroups();
      this.scheduleAutoBackup();
    }, 0);
  }

  aboutToDisappear(): void {
    if (this.deferredLoadTimer >= 0) {
      clearTimeout(this.deferredLoadTimer);
      this.deferredLoadTimer = -1;
    }
    this.clearAutoScanTimer();
    this.clearStalePhotoRefreshTimer();
    this.unregisterMediaChange();
    this.unregisterNetworkListener();
    this.clearAutoBackupTimer();
    this.stopCompletedPreviewFlush();
    this.flushDoneIdsSave();
    this.flushPhotoRecordsSave();
  }

  onActiveStateChanged(): void {
    if (!this.isActive) {
      this.clearAutoScanTimer();
      this.clearBackupGridRefresh();
      this.unregisterMediaChange();
      return;
    }
    this.applyPendingRemoteRemovals();
    this.scheduleActiveAutoScan();
    this.syncMediaChangeRegistration();
  }

  // 文件管理里从备份目录删/移出的文件：相册变为活动时按文件名精确撤销这些图的已备份标记。
  // 不查云端、不全量扫描，与相册规模无关：本地仍在的图转“待备份”（可重新备份）；仅云端的图（唯一副本在云端）整条移除。
  private applyPendingRemoteRemovals(): void {
    // 启动延后加载未完成时不消费：consumeRemoteRemoved 会清空名单，若此刻 photos 为空将丢失撤销。
    // loadPhotoRecords 完成后会在延后块里主动再调一次，那时 photos 已就绪。
    if (!this.photosLoaded) {
      return;
    }
    const names = PhotoBackupSettingsStore.consumeRemoteRemoved();
    if (names.length > 0) {
      this.dropBackupMarksByNames(new Set<string>(names));
    }
  }

  // 撤销「这些文件名」对应图的已备份标记：本地仍在 → 转“待备份”（可重新备份）；仅云端图（唯一副本在云端）→ 整条移除。
  private dropBackupMarksByNames(removedNames: Set<string>): void {
    let changed = false;
    const next: PhotoBackupItem[] = [];
    this.getPhotos().forEach((item: PhotoBackupItem) => {
      const marked = item.status === PhotoBackupStatus.COMPLETED || this.isPhotoDone(item);
      if (!removedNames.has(item.name) || !marked) {
        next.push(item);
        return;
      }
      this.clearDoneMark(item);
      changed = true;
      if (!item.localExists) {
        return; // 仅云端图（唯一副本在云端）→ 整条移除（不 push）
      }
      item.status = PhotoBackupStatus.WAITING;
      item.progress = CloudThemeToken.zero;
      item.error = '';
      next.push(item);
    });
    if (!changed) {
      return;
    }
    // 重建分组刷新网格（行 key 含 status，COMPLETED→WAITING 让 key 变化、强制重建对应行刷新角标）。
    // 触发自动补传后，补传完成会再走 markBackupItemDone → rebuildGroups 把角标刷回“已备份”。
    this.photos = next;
    this.saveDoneIds();
    this.refreshPhotoStats();
    this.rebuildGroups();
    this.savePhotoRecords();
  }

  // 兜底：点开已备份的图时异步点查云端单文件是否还在；确认“不存在”才撤销标记。
  // 仅在线时查；失败信息不明确（可能只是网络问题）时保守不动，避免误清触发重复上传。
  private verifyBackupStillExists(item: PhotoBackupItem): void {
    const marked = item.status === PhotoBackupStatus.COMPLETED || this.isPhotoDone(item);
    if (!marked || !NetworkStateUtil.hasNetwork()) {
      return;
    }
    const name = item.name;
    const remotePath = item.remoteFileId.length > 0 ? item.remoteFileId : this.getRemoteFilePath(item);
    CloudApi.getObjectDetail(remotePath, false, {
      onSuccess: () => {},
      onFailure: (msg: string) => {
        AppLogger.info(TAG, `[verify] cloud check failed for ${name}: ${msg}`);
        if (this.isNotFoundError(msg)) {
          this.dropBackupMarksByNames(new Set<string>([name]));
        }
      }
    });
  }

  private isNotFoundError(msg: string): boolean {
    const m = msg.toLowerCase();
    return m.includes('not found') || m.includes('notfound') || m.includes('not exist')
      || m.includes('no such') || m.includes('404') || m.includes('不存在') || m.includes('找不到');
  }

  // 仅云端图预览前先点查云端：存在→打开网盘预览；已删→移除条目 + 提示（不开黑屏预览）；
  // 离线 / 无云端 ID / 模糊失败→照常尝试打开（避免误删，由 ImagePreview 自行显示失败态）。
  private openCloudOnlyPreview(item: PhotoBackupItem): void {
    const name = item.name;
    const fileId = item.remoteFileId;
    const openPreview = (): void => {
      CloudRouter.push(Constant.IAMGE_PREVIEW_PAGE, new ImagePreview(name, fileId, ''));
    };
    if (fileId.length === 0 || !NetworkStateUtil.hasNetwork()) {
      openPreview();
      return;
    }
    CloudApi.getObjectDetail(fileId, false, {
      onSuccess: () => { openPreview(); },
      onFailure: (msg: string) => {
        if (this.isNotFoundError(msg)) {
          AppLogger.info(TAG, `[verify] cloud-only gone, remove ${name}: ${msg}`);
          this.dropBackupMarksByNames(new Set<string>([name]));
          showToast('该图片已从云端删除');
        } else {
          openPreview();
        }
      }
    });
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
      AppLogger.error(TAG, `load done ids failed: ${(err as Error)?.message ?? err}`);
      this.doneIds = new Set<string>();
    }
    this.invalidateLegacyDoneIdPool();
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
      // Migrate older records whose modifiedAt was stored in seconds (showed as 1970).
      let migrated = false;
      this.photos.forEach((item: PhotoBackupItem) => {
        const normalized = toMillis(item.modifiedAt);
        if (normalized !== item.modifiedAt) {
          item.modifiedAt = normalized;
          migrated = true;
        }
      });
      if (migrated) {
        this.savePhotoRecords();
      }
      this.migrateLegacyDoneIds();
      this.refreshDoneStatus();
    } catch (err) {
      AppLogger.error(TAG, `load photo records failed: ${(err as Error)?.message ?? err}`);
      this.photos = [];
      this.refreshPhotoStats();
    }
    this.photosLoaded = true;
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
      if (!item.localExists) {
        await this.loadCloudThumbnail(item);
        return;
      }
      const size: image.Size = {
        width: CloudThemeToken.photoBackupThumbnailSize,
        height: CloudThemeToken.photoBackupThumbnailSize
      };
      const asset = await this.getPhotoAssetForThumbnail(item);
      if (!asset) {
        AppLogger.warn(TAG, `photo thumbnail asset not found: name=${item.name}, uri=${item.uri}`);
        this.scheduleStalePhotoRefresh();
        return;
      }
      let loadedPixelMap: PixelMap;
      try {
        loadedPixelMap = await asset.getThumbnail(size);
      } catch (err) {
        AppLogger.warn(TAG, `load photo asset thumbnail failed: name=${item.name}, uri=${item.uri}, error=${(err as Error)?.message ?? err}`);
        return;
      }
      this.runInUiScope(() => {
        this.setPhotoThumbnail(item, loadedPixelMap);
      });
    } catch (err) {
      AppLogger.warn(TAG, `load photo thumbnail failed: ${(err as Error)?.message ?? err}`);
    } finally {
      this.thumbnailLoadingIds.delete(loadingId);
      this.thumbnailLoadingIds.delete(item.id);
    }
  }

  // 仅云端图：用云端缩略图 url 下载成 PixelMap，复用本地缩略图的展示通道（photoBackupThumbs）。
  private async loadCloudThumbnail(item: PhotoBackupItem): Promise<void> {
    if (!item.remoteFileId) {
      return;
    }
    const url = await this.getCloudThumbUrl(item.remoteFileId);
    const fullUrl = (url.startsWith(Constant.PROTOCOL_HTTP_SCHEME) || url.startsWith(Constant.PROTOCOL_HTTPS_SCHEME))
      ? url : CloudApi.getBaseURL() + url;
    const req = http.createHttp();
    try {
      const resp = await req.request(fullUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (resp.responseCode === Constant.HTTP_STATUS_OK) {
        const source = image.createImageSource(resp.result as ArrayBuffer);
        const pixelMap = await source.createPixelMap();
        source.release();
        this.runInUiScope(() => {
          this.setPhotoThumbnail(item, pixelMap);
        });
      }
    } finally {
      req.destroy();
    }
  }

  private getCloudThumbUrl(fileId: string): Promise<string> {
    return new Promise<string>((resolve: (url: string) => void, reject: (err: Error) => void) => {
      CloudApi.getThumb(fileId, {
        onSuccess: (url: string) => resolve(url),
        onFailure: (msg: string) => reject(new Error(msg))
      });
    });
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
      AppLogger.warn(TAG, `find photo asset by uri failed: ${(err as Error)?.message ?? err}`);
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
      AppLogger.warn(TAG, `find photo asset by signature failed: ${(err as Error)?.message ?? err}`);
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
    return toMillis((asset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED) as number) ?? 0);
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
      this.rebuildGroupsIfPhotoSetChanged();
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
      AppLogger.warn(TAG, `run ui scoped task failed: ${(err as Error)?.message ?? err}`);
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

  // 媒体库变化监听：仅在「相册页可见 + 开启备份」时注册（符合隐私声明：读相册用于备份），
  // 收到本地新增/变化通知后防抖触发一次增量扫描，让新图实时出现，无需切 tab 或等定时器。
  private syncMediaChangeRegistration(): void {
    const shouldListen = this.isActive && this.getSettingsEnabled();
    if (shouldListen && !this.mediaChangeRegistered) {
      this.registerMediaChange();
    } else if (!shouldListen && this.mediaChangeRegistered) {
      this.unregisterMediaChange();
    }
  }

  private registerMediaChange(): void {
    const context = this.getAbilityContext();
    if (!context) {
      return;
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      helper.registerChange(photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI, true, this.onMediaLibraryChange);
      this.mediaChangeHelper = helper;
      this.mediaChangeRegistered = true;
      AppLogger.info(TAG, 'media change listener registered');
    } catch (err) {
      AppLogger.error(TAG, `registerChange failed: ${(err as Error)?.message ?? err}`);
    }
  }

  private unregisterMediaChange(): void {
    if (this.mediaChangeDebounceTimer >= CloudThemeToken.zero) {
      clearTimeout(this.mediaChangeDebounceTimer);
      this.mediaChangeDebounceTimer = -1;
    }
    if (!this.mediaChangeRegistered) {
      return;
    }
    try {
      this.mediaChangeHelper?.unRegisterChange(photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI);
    } catch (err) {
      AppLogger.error(TAG, `unRegisterChange failed: ${(err as Error)?.message ?? err}`);
    }
    this.mediaChangeRegistered = false;
  }

  private onMediaLibraryChange = (changeData: photoAccessHelper.ChangeData): void => {
    if (!this.getSettingsEnabled()) {
      return;
    }
    if (changeData.type === photoAccessHelper.NotifyType.NOTIFY_REMOVE) {
      // 删除即时处理（不受是否在相册页限制——删除事件常在切到系统相册时触发）：
      // 已备份的转“仅云端”保留，未备份的移除。
      this.handleRemovedUris(changeData.uris ?? []);
      return;
    }
    if (!this.isActive) {
      return;
    }
    // 新增/变更：防抖做一次增量扫描，扫出新增图。
    if (this.mediaChangeDebounceTimer >= CloudThemeToken.zero) {
      clearTimeout(this.mediaChangeDebounceTimer);
    }
    this.mediaChangeDebounceTimer = setTimeout(() => {
      this.mediaChangeDebounceTimer = -1;
      if (this.isActive && this.getSettingsEnabled() && !this.isScanning && !this.isBackupRunning()) {
        this.scanLocalPhotos(false, true);
      }
    }, CloudThemeToken.photoBackupAutoScanDelayMs);
  }

  // 收到本地删除事件：已备份的转“仅云端”保留（缩略图/小云朵/预览走云端），未备份的从列表移除。
  private async handleRemovedUris(uris: string[]): Promise<void> {
    if (uris.length === 0) {
      return;
    }
    const uriSet: Set<string> = new Set<string>(uris);
    if (!this.getPhotos().some((it: PhotoBackupItem) => uriSet.has(it.uri))) {
      return;
    }
    const remoteMap = await this.loadRemotePhotoMap();
    const next: PhotoBackupItem[] = [];
    this.getPhotos().forEach((it: PhotoBackupItem) => {
      if (!uriSet.has(it.uri)) {
        next.push(it);
        return;
      }
      const backedUp = it.status === PhotoBackupStatus.COMPLETED || this.isPhotoDone(it);
      if (backedUp) {
        it.localExists = false;
        const remote = remoteMap.get(it.name);
        if (remote) {
          it.remoteFileId = remote.id;
        }
        next.push(it);
      }
    });
    this.photos = next;
    this.refreshPhotoStats();
    this.rebuildGroups();
    this.savePhotoRecords();
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
    // 备份进行中绝不扫描：避免重建图片列表、与正在上传的任务抢改状态导致待备份/上传中计数错乱。
    if (this.isScanning || this.isBackupRunning()) {
      return;
    }
    this.isScanning = true;
    if (!silent) {
      this.backupState = PhotoBackupState.SCANNING;
      this.permissionHint = '';
    }
    AppLogger.info(TAG, `scan start, forceFull=${forceFull}, silent=${silent}`);
    try {
      let context = this.getAbilityContext();
      if (!context) {
        if (!silent) {
          this.permissionHint = '无法获取应用上下文，请稍后重试或重新打开页面。';
          this.backupState = PhotoBackupState.FAILED;
        }
        return;
      }
      let granted = await this.ensurePhotoPermission(context);
      if (!granted) {
        if (!silent) {
          this.permissionHint = '未获得完整相册读取权限时，系统扫描可能为空。可重新授权，或使用“选择图片加入备份”。';
          showToast('需要允许读取相册后才能扫描图片');
          this.backupState = PhotoBackupState.FAILED;
        }
        return;
      }
      const previousCount = this.getPhotos().length;
      let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      let predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
      const modifiedFloor = forceFull ? CloudThemeToken.zero : this.getIncrementalModifiedFloor();
      if (modifiedFloor > CloudThemeToken.zero) {
        // DATE_MODIFIED 在媒体库中以“秒”为单位，而 modifiedFloor 已归一为毫秒；
        // 必须转回秒再比较，否则“秒 > 毫秒”恒为 false、增量扫描永远扫不到新图。
        predicates.greaterThan(photoAccessHelper.PhotoKeys.DATE_MODIFIED, Math.floor(modifiedFloor / 1000));
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
      // 全量扫描才重建相册名映射（遍历所有相册、重操作）；增量扫描复用缓存，避免每次卡顿。
      const albumNameByUri = forceFull
        ? await this.buildAlbumNameMap(phAccessHelper)
        : (this.cachedAlbumNameMap ?? new Map<string, string>());
      if (forceFull) {
        this.cachedAlbumNameMap = albumNameByUri;
      }
      let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> =
        await phAccessHelper.getAssets(fetchOptions);
      let nextPhotos: PhotoBackupItem[] = await this.readPhotoFetchResult(fetchResult, albumNameByUri);
      if (!silent) {
        if (nextPhotos.length === 0 && forceFull) {
          this.permissionHint = '未扫描到本地图片。如果相册中已有图片，请检查相册读取权限，或手动选择图片加入备份。';
        } else if (forceFull && previousCount > 0 && nextPhotos.length < previousCount) {
          this.permissionHint = `本次系统扫描到 ${nextPhotos.length} 张，少于当前记录 ${previousCount} 张。如果数量不符合预期，请检查相册权限范围。`;
        }
      }
      const remotePhotoMap = forceFull ? await this.loadRemotePhotoMap() : undefined;
      this.photos = this.mergePhotoList(nextPhotos, !forceFull, remotePhotoMap);
      if (albumNameByUri.size > 0) {
        this.applyAlbumNames(albumNameByUri);
      }
      this.refreshPhotoStats();
      this.updateSettings((settings: PhotoBackupSettings) => {
        settings.lastScanAt = new Date().getTime();
      });
      if (nextPhotos.length > 0) {
        this.savePhotoRecords();
      }
      this.scheduleAutoBackup();
      const addedCount = Math.max(this.getPhotos().length - previousCount, CloudThemeToken.zero);
      AppLogger.info(TAG, `scan ok, scanned=${nextPhotos.length}, added=${addedCount}, total=${this.getPhotos().length}`);
      if (!silent) {
        showToast(forceFull ? `已扫描到 ${this.localPhotoCount} 张本地图片` :
          (addedCount > 0 ? `已发现 ${addedCount} 张新图片` : '没有发现新图片'));
      }
      if (!silent) {
        this.backupState = this.waitingPhotoCount > 0 ? PhotoBackupState.IDLE : PhotoBackupState.COMPLETED;
      }
    } catch (err) {
      let error = err as BusinessError;
      AppLogger.error(TAG, `scan failed: ${error.code}, ${error.message}`);
      if (!silent) {
        this.permissionHint = '相册扫描失败，请检查系统相册权限。也可以先使用“选择图片加入备份”继续备份指定图片。';
        showToast('扫描本地相册失败，请检查相册读取权限');
        this.backupState = PhotoBackupState.FAILED;
      }
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
   * Build a uri -> album-name map. Primary source is physical "source" albums
   * (相机 / 截图 / 微信 / 下载 …) available since API 23; user-created albums fill
   * any gaps and cover older devices where SOURCE albums are unavailable.
   * Resilient: unmatched photos fall back to '其他' in groupByAlbum.
   */
  async buildAlbumNameMap(phAccessHelper: photoAccessHelper.PhotoAccessHelper): Promise<Map<string, string>> {
    const map: Map<string, string> = new Map<string, string>();
    // Physical source buckets — the natural "相册" grouping (since API 23).
    await this.mapAlbumsOfType(phAccessHelper, photoAccessHelper.AlbumType.SOURCE,
      photoAccessHelper.AlbumSubtype.SOURCE_GENERIC, map);
    // User-created albums fill gaps (and are the fallback on devices < API 23).
    await this.mapAlbumsOfType(phAccessHelper, photoAccessHelper.AlbumType.USER,
      photoAccessHelper.AlbumSubtype.USER_GENERIC, map);
    return map;
  }

  private async mapAlbumsOfType(phAccessHelper: photoAccessHelper.PhotoAccessHelper,
    albumType: photoAccessHelper.AlbumType, subtype: photoAccessHelper.AlbumSubtype,
    map: Map<string, string>): Promise<void> {
    let albumFetch: photoAccessHelper.FetchResult<photoAccessHelper.Album> | undefined = undefined;
    try {
      albumFetch = await phAccessHelper.getAlbums(albumType, subtype);
      const albums: photoAccessHelper.Album[] = await albumFetch.getAllObjects();
      const albumLimit = Math.min(albums.length, ALBUM_SCAN_LIMIT);
      for (let i = 0; i < albumLimit; i++) {
        const album = albums[i];
        const albumName = album.albumName ?? '';
        if (albumName.length === 0) {
          continue;
        }
        await this.mapAlbumImages(album, albumName, map);
      }
    } catch (err) {
      AppLogger.warn(TAG, `map albums (type=${albumType}, subtype=${subtype}) failed: ${(err as Error)?.message ?? err}`);
    } finally {
      if (albumFetch) {
        albumFetch.close();
      }
    }
  }

  private async mapAlbumImages(album: photoAccessHelper.Album, label: string,
    map: Map<string, string>): Promise<void> {
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
          map.set(asset.uri, label);
        }
      });
    } catch (err) {
      AppLogger.warn(TAG, `read album assets failed: ${(err as Error)?.message ?? err}`);
    } finally {
      if (assetFetch) {
        assetFetch.close();
      }
    }
  }

  /** Apply album names to existing photo records; returns true if anything changed. */
  private applyAlbumNames(map: Map<string, string>): boolean {
    const photos = this.getPhotos();
    let changed = false;
    photos.forEach((item: PhotoBackupItem) => {
      const name = map.get(item.uri);
      if (name && name.length > 0 && item.albumName !== name) {
        item.albumName = name;
        changed = true;
      }
    });
    return changed;
  }

  /**
   * On-demand album-name population (when the user opens the 相册 segment) so the
   * grouping is meaningful without waiting for a full re-scan. Runs once.
   */
  async ensureAlbumNames(): Promise<void> {
    if (this.albumNamesEnsured) {
      return;
    }
    this.albumNamesEnsured = true;
    try {
      const context = this.getAbilityContext();
      if (!context) {
        this.albumNamesEnsured = false;
        return;
      }
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const map = await this.buildAlbumNameMap(phAccessHelper);
      if (map.size === 0) {
        this.albumNamesEnsured = false;
        return;
      }
      if (this.applyAlbumNames(map)) {
        this.savePhotoRecords();
        this.rebuildGroups();
      }
    } catch (err) {
      this.albumNamesEnsured = false;
      AppLogger.warn(TAG, `ensure album names failed: ${(err as Error)?.message ?? err}`);
    }
  }

  getIncrementalModifiedFloor(): number {
    let modifiedAt = CloudThemeToken.zero;
    this.getPhotos().forEach((item: PhotoBackupItem) => {
      modifiedAt = Math.max(modifiedAt, item.modifiedAt);
    });
    return modifiedAt;
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

  mergePhotoList(incoming: PhotoBackupItem[], keepExisting: boolean,
    remoteMap?: Map<string, ObjectInfo>): PhotoBackupItem[] {
    const previousItems = this.getPhotos().slice();
    const usedPreviousIds: Set<string> = new Set<string>();
    const merged: PhotoBackupItem[] = keepExisting ? previousItems.slice() : [];

    // O(1) 命中索引：旧实现对每张 incoming 都 findIndex 线性扫一遍 merged/previousItems，
    // 大相册（数千张）下是 O(N²)，全量扫描会卡死主线程触发系统 appfreeze 杀进程。
    // 改为按 uri/id/name 预建索引，命中是 O(1)，仅签名兜底在同名候选里小范围比对。
    const mergedByUri: Map<string, number> = new Map<string, number>();
    const mergedById: Map<string, number> = new Map<string, number>();
    const mergedByName: Map<string, number[]> = new Map<string, number[]>();
    const prevByUri: Map<string, number> = new Map<string, number>();
    const prevById: Map<string, number> = new Map<string, number>();
    const prevByName: Map<string, number[]> = new Map<string, number[]>();
    const indexPhoto = (byUri: Map<string, number>, byId: Map<string, number>,
      byName: Map<string, number[]>, it: PhotoBackupItem, i: number): void => {
      if (it.uri.length > 0) {
        byUri.set(it.uri, i);
      }
      if (it.id.length > 0) {
        byId.set(it.id, i);
      }
      if (it.name.length > 0) {
        const arr = byName.get(it.name);
        if (arr) {
          arr.push(i);
        } else {
          byName.set(it.name, [i]);
        }
      }
    };
    const findFast = (byUri: Map<string, number>, byId: Map<string, number>,
      byName: Map<string, number[]>, pool: PhotoBackupItem[], item: PhotoBackupItem): number => {
      const uriHit = byUri.get(item.uri);
      if (uriHit !== undefined) {
        return uriHit;
      }
      const idHit = byId.get(item.id);
      if (idHit !== undefined) {
        return idHit;
      }
      const candidates = byName.get(item.name);
      if (candidates) {
        for (const idx of candidates) {
          if (this.isSamePhotoBySignature(pool[idx], item)) {
            return idx;
          }
        }
      }
      return -1;
    };
    merged.forEach((it: PhotoBackupItem, i: number) => indexPhoto(mergedByUri, mergedById, mergedByName, it, i));
    previousItems.forEach((it: PhotoBackupItem, i: number) => indexPhoto(prevByUri, prevById, prevByName, it, i));

    incoming.forEach((item: PhotoBackupItem) => {
      item.localExists = true;
      const existingIndex = findFast(mergedByUri, mergedById, mergedByName, merged, item);
      if (existingIndex >= 0) {
        this.updatePhotoItemFromResolved(merged[existingIndex], item);
        merged[existingIndex].localExists = true;
        return;
      }
      if (!keepExisting) {
        const previousIndex = findFast(prevByUri, prevById, prevByName, previousItems, item);
        if (previousIndex >= 0 && !usedPreviousIds.has(previousItems[previousIndex].id)) {
          usedPreviousIds.add(previousItems[previousIndex].id);
          const previousItem = previousItems[previousIndex];
          this.updatePhotoItemFromResolved(previousItem, item);
          previousItem.localExists = true;
          merged.push(previousItem);
          indexPhoto(mergedByUri, mergedById, mergedByName, previousItem, merged.length - 1);
          return;
        }
      }
      merged.push(item);
      indexPhoto(mergedByUri, mergedById, mergedByName, item, merged.length - 1);
    });
    // 全量扫描：本地已删但云端仍有（且已备份）的图 → 转“仅云端”保留；其余已删图移除。
    if (!keepExisting && remoteMap) {
      previousItems.forEach((prev: PhotoBackupItem) => {
        if (usedPreviousIds.has(prev.id)) {
          return;
        }
        const remote = remoteMap.get(prev.name);
        if (remote && (prev.status === PhotoBackupStatus.COMPLETED || this.isPhotoDone(prev))) {
          prev.localExists = false;
          prev.remoteFileId = remote.id;
          merged.push(prev);
        }
      });
    }
    // 本地还在、但已标记备份的图：若云端目录已无该名 → 远端那份被删，撤销已备份标记（小云朵消失、可重备份）。
    // 仅在「云端目录被完整列出」时核对：getFilesInfo 单页上限 100，返回数 >= 100 说明被分页截断，
    // 无法判断第一页之外的图是否还在云端，必须跳过——否则会把第一页之外的全部标记误清（大相册灾难）。
    if (remoteMap && remoteMap.size > 0 && remoteMap.size < 100) {
      let cleared = false;
      merged.forEach((item: PhotoBackupItem) => {
        if (!item.localExists) {
          return;
        }
        const markedDone = item.status === PhotoBackupStatus.COMPLETED || this.isPhotoDone(item);
        if (markedDone && !remoteMap.has(item.name)) {
          this.clearDoneMark(item);
          item.status = PhotoBackupStatus.WAITING;
          item.progress = CloudThemeToken.zero;
          item.error = '';
          cleared = true;
        }
      });
      if (cleared) {
        this.scheduleDoneIdsSave();
      }
    }
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
    // applyDoneStatus 原地改 item.status，无需重建并重新赋值整个 photos 数组（4803 张时白白多花数十 ms）。
    this.getPhotos().forEach((item: PhotoBackupItem) => {
      this.applyDoneStatus(item, true);
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

  // 撤销某张图的"已备份"标记：清当前路径 done-key 与历史遗留 id（远端那份被删时调用）。
  // legacy id 仅默认路径才有意义；非默认路径跳过全量扫描，避免每次 O(doneIds) 开销。
  clearDoneMark(item: PhotoBackupItem): void {
    this.doneIds.delete(this.getDoneKey(item));
    if (this.isDefaultBackupPath()) {
      this.getLegacyDoneIds(item).forEach((id: string) => {
        this.doneIds.delete(id);
      });
      this.invalidateLegacyDoneIdPool();
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
    // 只遍历缓存的「非 scoped」legacy 池，而非每张照片都 Array.from 全部 doneIds。
    // 否则 N 张 × M 个 doneId = O(N×M)（数千张时启动卡数秒）；scoped 到任意路径的 id 都不在池里。
    this.getLegacyDoneIdPool().forEach((id: string) => {
      if (id.startsWith(`${item.uri}_`) && legacyIds.indexOf(id) < 0) {
        legacyIds.push(id);
      }
    });
    return legacyIds;
  }

  private legacyDoneIdPool: string[] | null = null;
  private getLegacyDoneIdPool(): string[] {
    if (this.legacyDoneIdPool === null) {
      this.legacyDoneIdPool = Array.from(this.doneIds).filter((id: string) => !this.isPathDoneId(id));
    }
    return this.legacyDoneIdPool;
  }
  private invalidateLegacyDoneIdPool(): void {
    this.legacyDoneIdPool = null;
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
      this.invalidateLegacyDoneIdPool();
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
      AppLogger.error(TAG, `request photo permission failed: ${error.code}, ${error.message}`);
      return false;
    }
  }

  private registerNetworkListener(): void {
    if (this.netRegistered) {
      return;
    }
    try {
      const netCon = connection.createNetConnection();
      netCon.on('netAvailable', () => {
        this.scheduleAutoBackup();
      });
      netCon.on('netCapabilitiesChange', () => {
        this.scheduleAutoBackup();
      });
      netCon.register((err: BusinessError) => {
        if (err) {
          AppLogger.error(TAG, `net register failed: ${err.message}`);
        }
      });
      this.netConnection = netCon;
      this.netRegistered = true;
    } catch (err) {
      AppLogger.error(TAG, `register network listener failed: ${(err as Error)?.message ?? err}`);
    }
  }

  private unregisterNetworkListener(): void {
    if (!this.netRegistered) {
      return;
    }
    try {
      this.netConnection?.unregister((err: BusinessError) => {
        if (err) {
          AppLogger.error(TAG, `net unregister failed: ${err.message}`);
        }
      });
    } catch (err) {
      AppLogger.error(TAG, `unregister network listener failed: ${(err as Error)?.message ?? err}`);
    }
    this.netConnection = undefined;
    this.netRegistered = false;
  }

  private clearAutoBackupTimer(): void {
    if (this.autoBackupDebounceTimer >= CloudThemeToken.zero) {
      clearTimeout(this.autoBackupDebounceTimer);
      this.autoBackupDebounceTimer = -1;
    }
  }

  // 备份进行中节流刷新网格：让逐张完成的图近实时显示小云朵（@Trace 经 @Prop 深拷贝不可靠，靠重建生效）。
  // 仅相册页可见时刷新、至多约 1.5 秒一次，避免每张完成都重建造成卡顿。只重新分组、不重扫媒体、不动备份状态。
  private backupGridRefreshTimer: number = -1;
  private backupGridDirty: boolean = false;
  private lastGridScrollAt: number = 0;
  private scheduleBackupGridRefresh(): void {
    if (!this.isActive) {
      return;
    }
    this.backupGridDirty = true;
    if (this.backupGridRefreshTimer < CloudThemeToken.zero) {
      this.backupGridRefreshTimer = setTimeout(() => {
        this.backupGridRefreshTimer = -1;
        this.flushBackupGridRefresh();
      }, BACKUP_GRID_REFRESH_MS);
    }
  }

  // 正在滑动时不重建（重建的 @Prop 深拷贝会卡住滚动），推迟到滑动静默后再刷。
  private flushBackupGridRefresh(): void {
    if (!this.backupGridDirty) {
      return;
    }
    if (this.isActive && new Date().getTime() - this.lastGridScrollAt < GRID_SCROLL_QUIET_MS) {
      this.backupGridRefreshTimer = setTimeout(() => {
        this.backupGridRefreshTimer = -1;
        this.flushBackupGridRefresh();
      }, GRID_SCROLL_QUIET_MS);
      return;
    }
    this.backupGridDirty = false;
    this.runInUiScope(() => {
      this.rebuildGroups();
    });
  }

  private clearBackupGridRefresh(): void {
    this.backupGridDirty = false;
    if (this.backupGridRefreshTimer >= CloudThemeToken.zero) {
      clearTimeout(this.backupGridRefreshTimer);
      this.backupGridRefreshTimer = -1;
    }
  }

  // 网络可用/能力变化、设置变化、扫描到新图等事件后，防抖评估一次是否应自动开始备份。
  private scheduleAutoBackup(): void {
    this.clearAutoBackupTimer();
    this.autoBackupDebounceTimer = setTimeout(() => {
      this.autoBackupDebounceTimer = -1;
      this.maybeAutoBackup();
    }, AUTO_BACKUP_DEBOUNCE_MS);
  }

  // 满足 [开启备份 && 开启自动备份 && 满足网络 && 有待备份图 && 不在备份中 && 非用户手动暂停] 时自动开始备份。
  // PAUSED 是用户主动暂停，网络恢复也不自动续；WAITING_NETWORK 是因网络暂停，满足网络时会在此自动续上。
  private maybeAutoBackup(): void {
    if (!this.getSettingsEnabled() || !this.getSettingsAutoBackup()) {
      return;
    }
    if (this.backupState === PhotoBackupState.BACKING_UP || this.backupState === PhotoBackupState.PAUSED) {
      return;
    }
    if (this.isScanning) {
      return;
    }
    if (!this.canBackupNow()) {
      return;
    }
    if (this.getWaitingItems().length === 0) {
      return;
    }
    AppLogger.info(TAG, 'auto backup triggered');
    this.startBackup();
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
    AppLogger.info(TAG, `backup start, targets=${targets.length}, retryFailedOnly=${retryFailedOnly}`);
    this.runBackup(targets);
  }

  pauseBackup(): void {
    if (this.backupState !== PhotoBackupState.BACKING_UP) {
      return;
    }
    this.shouldPauseBackup = true;
    AppLogger.info(TAG, 'backup pause requested');
    showToast('当前图片完成后暂停备份');
  }

  canBackupNow(): boolean {
    if (!this.getSettingsWifiOnly()) {
      return true;
    }
    try {
      return NetworkStateUtil.isWifiConnected();
    } catch (err) {
      AppLogger.error(TAG, `check wifi failed: ${(err as Error)?.message ?? err}`);
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
        this.scheduleBackupGridRefresh();
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
        this.clearBackupGridRefresh();
        this.flushCompletedPreviewUpdates();
        this.runInUiScope(() => {
          this.backupState = PhotoBackupState.PAUSED;
        });
        this.flushDoneIdsSave();
        this.flushPhotoRecordsSave();
        this.refreshPhotoStats();
        this.rebuildGroups();
        AppLogger.info(TAG, `backup paused, waiting=${this.waitingPhotoCount}, failed=${this.failedPhotoCount}`);
        return;
      }
      this.flushCompletedPreviewUpdates();
      this.flushDoneIdsSave();
      this.flushPhotoRecordsSave();
      this.refreshPhotoStats();
      // 批次完成重建一次网格：补传/备份完成的图状态变 COMPLETED 但数量未变，refreshPhotoStats 不会重建；
      // 行 key 含 status，重建后角标即刷回“已备份”（避免“删远端→待备份→补传完成仍显待备份”）。
      this.clearBackupGridRefresh();
      this.rebuildGroups();
      AppLogger.info(TAG, `backup batch done, waiting=${this.waitingPhotoCount}, failed=${this.failedPhotoCount}`);
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
      // 拷贝出的新文件 mtime 是当下时刻；对齐回原图修改时间，让任何按 mtime 读元数据的旁路也拿到正确时间
      FileSystemUtil.setModifiedTime(localPath, item.modifiedAt);
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
      // 把原图修改时间作为 LastModified 透传给 Cloudreve，让云端入库时间对齐原图而不是上传时刻
      const lastModifiedMs = item.modifiedAt > 0 ? item.modifiedAt : 0;
      CloudApi.uploadLocalFile(localPath, remotePath, false, lastModifiedMs, {
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

  // 列出备份目录的云端文件（name → ObjectInfo，含云端 fileId），供仅云端图定位/预览/缩略图使用。
  loadRemotePhotoMap(): Promise<Map<string, ObjectInfo>> {
    return new Promise<Map<string, ObjectInfo>>((resolve: (value: Map<string, ObjectInfo>) => void) => {
      CloudApi.getFilesInfo(this.normalizeRemotePath(this.getSettingsRemotePath()), {
        onSuccess: (data: DirectoryInfo) => {
          const map = new Map<string, ObjectInfo>();
          (data.objects ?? []).forEach((object: ObjectInfo) => {
            map.set(object.name, object);
          });
          resolve(map);
        },
        onFailure: (msg: string) => {
          console.info(TAG, `load remote photo map skipped: ${msg}`);
          resolve(new Map<string, ObjectInfo>());
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

  private lastGroupedCount: number = -1;
  private albumNamesEnsured: boolean = false;

  rebuildGroups(): void {
    const list = this.getPhotos();
    this.lastGroupedCount = list.length;
    this.galleryGroups = this.segment === GallerySegment.TIME
      ? groupByDate(list, new Date()) : groupByAlbum(list);
  }

  /**
   * Rebuild groups only when the photo set size changed. Per-item status updates
   * (badges) propagate reactively via @Trace on PhotoBackupItem, so they don't
   * need a full regroup — this keeps refreshPhotoStats cheap during backups.
   */
  rebuildGroupsIfPhotoSetChanged(): void {
    if (this.getPhotos().length !== this.lastGroupedCount) {
      this.rebuildGroups();
    }
  }

  onSettingsRevisionChanged(): void {
    const prevRemotePath = this.lastRemotePath;
    this.loadSettings();
    this.rebuildGroups();
    this.syncMediaChangeRegistration();
    this.scheduleAutoBackup();
    const newRemotePath = this.normalizeRemotePath(this.getSettingsRemotePath());
    this.lastRemotePath = newRemotePath;
    if (prevRemotePath.length > 0 && prevRemotePath !== newRemotePath) {
      // 切换备份路径：旧“已备份”标记按新路径失效，重判标记 + 全量刷新重新关联云端。
      this.refreshDoneStatus();
      if (this.isActive && this.getSettingsEnabled() && !this.isScanning && !this.isBackupRunning()) {
        this.scanLocalPhotos(true, true);
      }
    }
  }

  openLocalPreview(item: PhotoBackupItem): void {
    if (!item.localExists) {
      // 仅云端图：预览必须依赖云端。先点查云端是否还在——已删则移除条目 + 提示，避免点开是黑屏。
      this.openCloudOnlyPreview(item);
      return;
    }
    // 本地图 → 本地预览即时打开（不依赖云端）；顺带异步核对云端（外部删除→清标记，本地图随后自动补传）。
    this.verifyBackupStillExists(item);
    // 仅在本地存在的图集内浏览。
    const localItems = this.getPhotos().filter((it: PhotoBackupItem) => it.localExists);
    let idx = localItems.findIndex((it: PhotoBackupItem) => it.uri === item.uri);
    if (idx < 0) {
      idx = localItems.findIndex((it: PhotoBackupItem) => it.id === item.id);
    }
    CloudRouter.push(Constant.PHOTO_LOCAL_PREVIEW_PAGE,
      new PhotoLocalPreviewParam(localItems, Math.max(idx, 0), this.getSettingsEnabled()));
  }

  retryFailedPhotos(): void {
    this.getFailedItems().forEach((it: PhotoBackupItem) =>
      this.setPhotoStatus(it, PhotoBackupStatus.WAITING, 0, ''));
    this.startBackup();
  }

  getHdsTitleBarBaseHeight(): number {
    return CloudThemeToken.getSafeTopInset(this.topRectHeight) + CloudThemeToken.rowHeight5xl;
  }

  private toggleDrawer(): void {
    this.getUIContext().animateTo({
      duration: CloudThemeToken.defaultAnimationDuration,
      curve: Curve.EaseOut
    }, () => {
      this.drawerOpen = !this.drawerOpen;
    });
  }

  @Builder picturesTitleStack() {
    Row() {
      Text('相册')
        .fontSize(CloudThemeToken.textSizeHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .maxLines(1)
      Blank().layoutWeight(1)
      CloudIconButton({
        icon: $r('app.media.ic_chevron_down'),
        iconColor: CloudThemeToken.textPrimary,
        onAction: () => { this.toggleDrawer(); }
      })
        .rotate({ angle: this.drawerOpen ? 180 : 0 })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.getPicturesTitleLeftPadding(),
      right: CloudThemeToken.filesTitleHorizontalPadding
    })
    .alignItems(VerticalAlign.Center)
  }

  private getPicturesTitleLeftPadding(): number {
    let pad = CloudThemeToken.filesTitleHorizontalPadding
    const bp = CloudThemeToken.getBreakpoint(this.sheetLayoutWidth)
    if (CloudThemeToken.isWideBreakpoint(bp) && !this.sidebarVisible) {
      pad += CloudThemeToken.sideBarToggleSize + CloudThemeToken.spacingCard
    }
    return pad
  }

  /** Top spacer the grid reserves so photos start below the immersive title bar. */
  getGridTopInset(): number {
    return this.getHdsTitleBarBaseHeight();
  }

  /** Any scroll auto-collapses the backup drawer (it only shows while stationary). */
  private onGridScroll(_yOffset: number): void {
    this.lastGridScrollAt = new Date().getTime();
    if (this.drawerOpen) {
      this.getUIContext().animateTo({
        duration: CloudThemeToken.defaultAnimationDuration,
        curve: Curve.EaseOut
      }, () => {
        this.drawerOpen = false;
      });
    }
  }


  /**
   * Backup-status drawer inlined here (not a child component) so the live counts
   * read directly from @State — child @Prop bindings were not refreshing mid-backup.
   */
  @Builder drawerCard() {
    Column({ space: CloudThemeToken.spacingSection }) {
      if (!this.getSettingsEnabled()) {
        Row() {
          Text('备份已关闭')
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
            .layoutWeight(1)
          Button('去开启')
            .fontSize(CloudThemeToken.textSizeSmallPlus)
            .height(CloudThemeToken.rowHeightSm)
            .onClick(() => { showToast('请在「我的 - 相册备份」中开启备份'); })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Row() {
          Column({ space: CloudThemeToken.spacingXs }) {
            Text(this.getStatusText())
              .fontSize(CloudThemeToken.textSizeBody)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary)
            Text(`已备份 ${this.completedPhotoCount} / ${this.localPhotoCount}`)
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.isBackupRunning() || this.backupState === PhotoBackupState.PAUSED) {
            Button(this.backupState === PhotoBackupState.PAUSED ? '继续' : '暂停')
              .fontSize(CloudThemeToken.textSizeSmallPlus)
              .height(CloudThemeToken.rowHeightSm)
              .backgroundColor(CloudThemeToken.surface)
              .fontColor(CloudThemeToken.primary)
              .onClick(() => { this.isBackupRunning() ? this.pauseBackup() : this.startBackup(); })
          } else {
            Button('立即备份')
              .fontSize(CloudThemeToken.textSizeSmallPlus)
              .height(CloudThemeToken.rowHeightSm)
              .onClick(() => { this.startBackup(); })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Progress({ value: this.completedPhotoCount, total: Math.max(this.localPhotoCount, 1), type: ProgressType.Capsule })
          .width('100%')
          .height(CloudThemeToken.storageProgressHeight)
          .color(CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({ space: CloudThemeToken.spacingPage }) {
          // Read @State directly in each Text (not via a @Builder value param) so the
          // counts refresh live during backup.
          Column({ space: CloudThemeToken.spacingXs }) {
            Text(this.uploadingPhotoCount.toString())
              .fontSize(CloudThemeToken.textSizeTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.primary)
            Text('上传中')
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
          }

          Column({ space: CloudThemeToken.spacingXs }) {
            Text(this.waitingPhotoCount.toString())
              .fontSize(CloudThemeToken.textSizeTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary)
            Text('待备份')
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
          }

          Column({ space: CloudThemeToken.spacingXs }) {
            Text(this.failedPhotoCount.toString())
              .fontSize(CloudThemeToken.textSizeTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.danger)
            Text('失败 · 重试')
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
          }
          .onClick(() => {
            if (this.failedPhotoCount > 0) { this.retryFailedPhotos(); }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
    }
    .width('100%')
    .padding(CloudThemeToken.spacingPage)
    .borderRadius({
      bottomLeft: CloudThemeToken.surfaceRadius,
      bottomRight: CloudThemeToken.surfaceRadius
    })
    .backgroundColor(CloudThemeToken.surfaceTranslucent)
    .backdropBlur(18)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
  }

  /** Backup drawer as a fixed overlay under the title; auto-collapses on scroll. */
  @Builder drawerOverlay() {
    if (this.drawerOpen) {
      Column() {
        this.drawerCard()
      }
      .width('100%')
      .padding({ top: this.getHdsTitleBarBaseHeight() })
      .transition(TransitionEffect.OPACITY.animation({ duration: CloudThemeToken.defaultAnimationDuration }))
    }
  }

  private selectSegment(value: GallerySegment): void {
    if (this.segment === value) {
      return;
    }
    this.segment = value;
    this.rebuildGroups();
    if (value === GallerySegment.ALBUM) {
      this.ensureAlbumNames();
    }
  }

  @Builder switcherItem(title: string, value: GallerySegment) {
    Text(title)
      .width(SWITCHER_ITEM_SIZE)
      .height(SWITCHER_ITEM_SIZE)
      .textAlign(TextAlign.Center)
      .fontSize(CloudThemeToken.textSizeSmall)
      .fontWeight(this.segment === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.segment === value ? CloudThemeToken.onPrimary : CloudThemeToken.textPrimary)
      .backgroundColor(this.segment === value ? CloudThemeToken.primary : Color.Transparent)
      .borderRadius(SWITCHER_ITEM_SIZE / 2)
      .onClick(() => { this.selectSegment(value); })
  }

  /** Frosted vertical capsule pinned at the left-center to switch 时间 / 相册. */
  @Builder floatingSwitcher() {
    Column({ space: SWITCHER_GAP }) {
      this.switcherItem('时间', GallerySegment.TIME)
      this.switcherItem('相册', GallerySegment.ALBUM)
    }
    .padding(SWITCHER_PADDING)
    .backgroundColor('rgba(120, 120, 128, 0.22)')
    .backdropBlur(18)
    .borderRadius(SWITCHER_ITEM_SIZE / 2 + SWITCHER_PADDING)
    .position({ x: CloudThemeToken.spacingSm, y: '50%' })
    .markAnchor({ x: 0, y: '50%' })
  }

  @Builder emptyStateBody(icon: ResourceStr, title: string, description: string, actionText: string) {
    Column() {
      EmptyState({
        icon: icon,
        title: title,
        description: description,
        actionText: actionText,
        onAction: () => { this.scanLocalPhotos(true, false); }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getHdsTitleBarBaseHeight() })
    .justifyContent(FlexAlign.Center)
  }

  // Refresh 自带的下拉提示留空（隐藏），刷新提示改用下方的浮层精确定位到标题栏下、图片上。
  @Builder photoRefreshHint() {
    Column()
      .width(CloudThemeToken.zero)
      .height(CloudThemeToken.zero)
      .opacity(CloudThemeToken.zero)
  }

  @Builder refreshingHintOverlay() {
    Column() {
      Row({ space: CloudThemeToken.spacingXl }) {
        LoadingProgress()
          .width(CloudThemeToken.iconLg)
          .height(CloudThemeToken.iconLg)
          .color(CloudThemeToken.primary)
        Text('正在刷新')
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textPrimary)
      }
      .height(CloudThemeToken.iconBoxSm)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPage })
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .backgroundColor(CloudThemeToken.surface)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: this.getGridTopInset() + CloudThemeToken.spacingPage })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .opacity(this.isRefreshing ? CloudThemeToken.fullOpacity :
      Math.min(CloudThemeToken.fullOpacity, this.refreshPullOffset / CloudThemeToken.refreshOffset))
    .hitTestBehavior(HitTestMode.None)
  }

  private async pullToRefreshScan(): Promise<void> {
    this.isRefreshing = true;
    try {
      // 下拉刷新做全量扫描：重建列表、反映本地新增/删除；silent 不弹 toast、不改备份状态。
      await this.scanLocalPhotos(true, true);
    } finally {
      this.isRefreshing = false;
    }
  }

  shouldShowPhotoRefreshHint(): boolean {
    return this.isRefreshing || this.refreshPullOffset > CloudThemeToken.spacingSm;
  }

  build() {
    HdsNavigation() {
      if (this.getPhotos().length === 0 && this.permissionHint.length > 0) {
        this.emptyStateBody($r('app.media.ic_lock_fill'), '无法读取相册', this.permissionHint, '授权读取相册')
      } else if (this.getPhotos().length === 0) {
        this.emptyStateBody($r('app.media.ic_select_photos'), '还没有本地照片',
          '扫描本地相册后，照片会显示在这里。', '扫描相册')
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Refresh({ refreshing: $$this.isRefreshing, builder: this.photoRefreshHint }) {
            PhotoGalleryGrid({
              groups: this.galleryGroups,
              backupEnabled: this.getSettingsEnabled(),
              topInset: this.getGridTopInset(),
              bottomInset: this.tabBarHeight,
              scroller: this.gridScroller,
              onScroll: (yOffset: number) => { this.onGridScroll(yOffset); },
              onRequestThumb: (item: PhotoBackupItem) => { this.loadPhotoThumbnail(item); },
              onTapPhoto: (item: PhotoBackupItem) => { this.openLocalPreview(item); }
            })
              .width('100%')
              .height('100%')
          }
          .width('100%')
          .height('100%')
          .pullToRefresh(true)
          .refreshOffset(CloudThemeToken.refreshOffset)
          .onOffsetChange((offset: number) => { this.refreshPullOffset = Math.max(CloudThemeToken.zero, offset); })
          .onRefreshing(() => { this.pullToRefreshScan(); })

          if (this.shouldShowPhotoRefreshHint()) {
            this.refreshingHintOverlay()
          }

          this.floatingSwitcher()
          this.drawerOverlay()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: ' '
        },
        stackBuilder: () => {
          this.picturesTitleStack()
        },
        divider: {
          showType: DividerShowType.OFF
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary,
              subTitleColor: CloudThemeToken.textSecondary
            },
            menuStyle: {
              backgroundColor: CloudThemeToken.surfaceSubtle,
              iconColor: CloudThemeToken.textPrimary,
              textColor: CloudThemeToken.textPrimary
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary,
              subTitleColor: CloudThemeToken.textSecondary
            },
            menuStyle: {
              backgroundColor: CloudThemeToken.surfaceSubtle,
              iconColor: CloudThemeToken.textPrimary,
              textColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.gridScroller])
    .backgroundColor(CloudThemeToken.background)
  }


  getAbilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      return undefined
    }
    return hostContext as common.UIAbilityContext
  }
}
