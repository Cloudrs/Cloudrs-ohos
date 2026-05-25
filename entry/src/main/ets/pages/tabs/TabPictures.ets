import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { FileUtil, NetworkUtil } from '@pura/harmony-utils';
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
import { PathSelectSheet } from '../../components/PathSelectSheet';
import { showToast } from '../../utils/ToastUtil';

const TAG: string = 'TabPictures';

@Component
export struct TabPictures {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @State settings: PhotoBackupSettings = new PhotoBackupSettings();
  @State backupState: PhotoBackupState = PhotoBackupState.IDLE;
  @State photos: PhotoBackupItem[] = [];
  @State selectedIndexes: number[] = [0];
  @State showSettings: boolean = false;
  @State showPathSelect: boolean = false;
  @State isScanning: boolean = false;
  private doneIds: Set<string> = new Set<string>();

  aboutToAppear(): void {
    this.loadSettings();
    this.loadDoneIds();
    this.loadPhotoRecords();
    if (this.settings.enabled) {
      this.scanLocalPhotos();
    }
  }

  loadSettings(): void {
    let json = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS, '') as string;
    this.settings = PhotoBackupSettings.fromJson(json ?? '');
  }

  saveSettings(): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS, this.settings.toJson());
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
    if (!this.settings.enabled) {
      return '未开启';
    }
    if (this.backupState === PhotoBackupState.SCANNING) {
      return '正在扫描本地相册';
    }
    if (this.backupState === PhotoBackupState.BACKING_UP) {
      return `正在备份 ${this.getUploadingItems().length} 张`;
    }
    if (this.backupState === PhotoBackupState.WAITING_NETWORK) {
      return '等待 Wi-Fi';
    }
    return `${this.settings.wifiOnly ? '仅 Wi-Fi' : '任意网络'} · ${this.settings.remotePath}`;
  }

  getPrimaryActionText(): string {
    if (!this.settings.enabled) {
      return '开启备份';
    }
    if (this.backupState === PhotoBackupState.BACKING_UP) {
      return '备份中';
    }
    if (this.getFailedItems().length > 0) {
      return '重试失败';
    }
    return '立即备份';
  }

  updateSettings(mutator: (settings: PhotoBackupSettings) => void): void {
    let next = new PhotoBackupSettings();
    next.enabled = this.settings.enabled;
    next.remotePath = this.settings.remotePath;
    next.wifiOnly = this.settings.wifiOnly;
    next.autoBackup = this.settings.autoBackup;
    next.lastScanAt = this.settings.lastScanAt;
    mutator(next);
    this.settings = next;
    this.saveSettings();
  }

  updateRemotePath(path: string): void {
    if (path.length === 0 || path === this.settings.remotePath) {
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
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let granted = await this.ensurePhotoPermission(context);
      if (!granted) {
        showToast('需要允许读取相册后才能扫描图片');
        this.backupState = PhotoBackupState.FAILED;
        return;
      }
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
    if (this.doneIds.has(item.id) || this.doneIds.has(item.uri)) {
      return true;
    }
    return Array.from(this.doneIds).some((id: string) => id.startsWith(`${item.uri}_`));
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
    return `${this.normalizeRemotePath(this.settings.remotePath)}|${item.id}`;
  }

  isDefaultBackupPath(): boolean {
    return this.normalizeRemotePath(this.settings.remotePath) === '/Photos/Camera';
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
    return id.startsWith(`${this.normalizeRemotePath(this.settings.remotePath)}|`);
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
    if (!this.settings.enabled) {
      this.updateSettings((settings: PhotoBackupSettings) => {
        settings.enabled = true;
      });
      this.showSettings = true;
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
    this.backupState = PhotoBackupState.BACKING_UP;
    this.runBackup(targets.slice(0, 5));
  }

  canBackupNow(): boolean {
    if (!this.settings.wifiOnly) {
      return true;
    }
    try {
      return NetworkUtil.hasDefaultNetSync() && NetworkUtil.hasNetWiFi();
    } catch (err) {
      console.error(TAG, `check wifi failed: ${(err as Error)?.message ?? err}`);
      return false;
    }
  }

  async runBackup(targets: PhotoBackupItem[]): Promise<void> {
    for (let index = 0; index < targets.length; index++) {
      await this.backupItem(targets[index], index);
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
        try {
          await FileUtil.unlink(localPath);
        } catch (_) {
        }
      }
    }
  }

  async copyPhotoToCache(item: PhotoBackupItem): Promise<string> {
    let context = getContext(this) as common.UIAbilityContext;
    let fileName = this.sanitizeFileName(item.name.length > 0 ? item.name : 'photo.jpg');
    let localPath = `${context.cacheDir}/photo_backup_${new Date().getTime()}_${fileName}`;
    let source = await FileUtil.open(item.uri, fs.OpenMode.READ_ONLY);
    try {
      await FileUtil.copyFile(source.fd, localPath);
    } finally {
      await FileUtil.close(source.fd);
    }
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

  getRemoteFilePath(item: PhotoBackupItem): string {
    let basePath = this.normalizeRemotePath(this.settings.remotePath);
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
      Scroll() {
        Column({ space: 16 }) {
          this.header();
          if (this.showSettings) {
            this.settingsPanel();
          }
          this.summaryCard();
          this.sectionUploading();
          this.sectionWaiting();
          this.sectionFailed();
          this.sectionCompleted();
        }
        .padding({ left: 16, right: 16, top: this.topRectHeight + 12, bottom: this.tabBarHeight + 24 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.nav_background'))
    .bindSheet($$this.showPathSelect, this.pathSelectSheet(), {
      showClose: false
    })
  }

  @Builder header() {
    Row() {
      Column({ space: 4 }) {
        Text('相册备份')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
        Text(this.getStatusText())
          .fontSize(13)
          .fontColor($r('app.color.common_font_gray'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        Image($r('app.media.ic_gearshape'))
          .width(22)
          .height(22)
          .fillColor(Color.Black)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.White)
      .onClick(() => {
        this.showSettings = !this.showSettings;
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder summaryCard() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.settings.enabled ? '备份已开启' : '备份未开启')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
          Text(this.settings.enabled ? `目标路径 ${this.settings.remotePath}` : '开启后会扫描本地图片并备份到云端')
            .fontSize(12)
            .fontColor($r('app.color.common_font_gray'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(this.getPrimaryActionText())
          .fontSize(14)
          .height(34)
          .enabled(this.backupState !== PhotoBackupState.BACKING_UP)
          .onClick(() => {
            this.startBackup();
          })
      }

      Row() {
        this.metricItem('本地', this.getLocalCount().toString());
        this.metricItem('已备份', this.getCompletedCount().toString());
        this.metricItem('待备份', this.getWaitingItems().length.toString());
        this.metricItem('失败', this.getFailedItems().length.toString());
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.settings.enabled && this.settings.wifiOnly) {
        Text('默认仅在 Wi-Fi 下自动备份，可在设置中改为任意网络或手动备份。')
          .fontSize(12)
          .fontColor($r('app.color.common_font_gray'))
      }

      if (this.backupState === PhotoBackupState.WAITING_NETWORK && this.settings.wifiOnly) {
        Button('模拟器测试：改为任意网络')
          .fontSize(13)
          .height(36)
          .width('100%')
          .backgroundColor($r('app.color.select_primary'))
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
    .padding(16)
    .borderRadius(18)
    .backgroundColor(Color.White)
  }

  @Builder metricItem(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.common_font_gray'))
    }
    .width('23%')
    .height(58)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.common_background'))
    .borderRadius(12)
  }

  @Builder sectionUploading() {
    if (this.getUploadingItems().length > 0) {
      this.sectionTitle('正在备份', this.getUploadingItems().length);
      Column({ space: 10 }) {
        ForEach(this.getUploadingItems(), (item: PhotoBackupItem) => {
          this.uploadingItem(item);
        }, (item: PhotoBackupItem) => item.id)
      }
    }
  }

  @Builder uploadingItem(item: PhotoBackupItem) {
    Row({ space: 12 }) {
      Image(item.uri)
        .width(52)
        .height(52)
        .objectFit(ImageFit.Cover)
        .borderRadius(10)

      Column({ space: 8 }) {
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Progress({ value: item.progress, total: 100, type: ProgressType.Linear })
          .height(6)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(`${item.progress}%`)
        .fontSize(12)
        .fontColor($r('app.color.common_font_gray'))
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor(Color.White)
  }

  @Builder sectionWaiting() {
    if (this.getWaitingItems().length > 0) {
      this.sectionTitle('待备份', this.getWaitingItems().length);
      this.photoGrid(this.getWaitingItems().slice(0, 24), PhotoBackupStatus.WAITING);
    } else if (this.getPhotos().length === 0) {
      this.emptyState();
    }
  }

  @Builder sectionFailed() {
    if (this.getFailedItems().length > 0) {
      this.sectionTitle('失败', this.getFailedItems().length);
      this.photoGrid(this.getFailedItems().slice(0, 12), PhotoBackupStatus.FAILED);
    }
  }

  @Builder sectionCompleted() {
    if (this.getCompletedItems().length > 0) {
      this.sectionTitle('最近完成', this.getCompletedItems().length);
      this.photoGrid(this.getCompletedItems().slice(0, 18), PhotoBackupStatus.COMPLETED);
    }
  }

  @Builder sectionTitle(title: string, count: number) {
    Row() {
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
      Text(count.toString())
        .fontSize(13)
        .fontColor($r('app.color.common_font_gray'))
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .margin({ top: 4 })
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
              .borderRadius(12)

            Text(this.getBadgeText(status))
              .fontSize(10)
              .fontColor(Color.White)
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .backgroundColor(this.getBadgeColor(status))
              .borderRadius(8)
              .margin(6)
          }
          .width('100%')
          .aspectRatio(1)
        }
      }, (item: PhotoBackupItem) => item.id)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .width('100%')
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
        return '#2EAD5B';
      case PhotoBackupStatus.FAILED:
        return '#E5484D';
      default:
        return '#0A59F7';
    }
  }

  @Builder emptyState() {
    Column({ space: 12 }) {
      Image($r('app.media.ic_select_photos'))
        .width(56)
        .height(56)
      Text(this.settings.enabled ? '还没有扫描到本地图片' : '开启相册备份后开始扫描')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
      Text('Cloudrs 只会上传备份，不会删除你的本地照片。')
        .fontSize(13)
        .fontColor($r('app.color.common_font_gray'))
        .textAlign(TextAlign.Center)
      Button(this.settings.enabled ? '重新扫描' : '开启备份')
        .onClick(() => {
          if (this.settings.enabled) {
            this.scanLocalPhotos();
          } else {
            this.showSettings = true;
          }
        })
      if (this.settings.enabled) {
        Button('选择图片加入备份')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(14)
          .onClick(() => {
            this.pickPhotosForBackup();
          })
      }
    }
    .width('100%')
    .padding(24)
    .borderRadius(18)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder settingsPanel() {
    Column({ space: 16 }) {
      Row() {
        Text('相册备份设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button('收起')
          .fontSize(13)
          .height(32)
          .onClick(() => {
            this.showSettings = false;
          })
      }
      .width('100%')

      this.switchRow('开启相册备份', this.settings.enabled, (value: boolean) => {
        this.updateSettings((settings: PhotoBackupSettings) => {
          settings.enabled = value;
        });
        if (value) {
          this.scanLocalPhotos();
        }
      });

      this.pathRow();

      Column({ space: 8 }) {
        Text('网络条件')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .width('100%')
        Row({ space: 8 }) {
          this.optionButton('仅 Wi-Fi', this.settings.wifiOnly, () => {
            this.updateSettings((settings: PhotoBackupSettings) => {
              settings.wifiOnly = true;
            });
          });
          this.optionButton('任意网络', !this.settings.wifiOnly, () => {
            this.updateSettings((settings: PhotoBackupSettings) => {
              settings.wifiOnly = false;
            });
            if (this.backupState === PhotoBackupState.WAITING_NETWORK) {
              this.backupState = PhotoBackupState.IDLE;
            }
          });
        }
      }

      this.switchRow('自动备份', this.settings.autoBackup, (value: boolean) => {
        this.updateSettings((settings: PhotoBackupSettings) => {
          settings.autoBackup = value;
        });
      });

      Row({ space: 10 }) {
        Button('重新扫描本地相册')
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.showSettings = false;
            this.scanLocalPhotos();
          })
        Button('选择图片加入')
          .layoutWeight(1)
          .height(44)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick(() => {
            this.pickPhotosForBackup();
          })
      }
      .width('100%')

      Text('备份只会上传本地图片到远程路径，不会删除本地照片，也不会自动删除云端文件。')
        .fontSize(12)
        .fontColor($r('app.color.common_font_gray'))
        .width('100%')
    }
    .padding(16)
    .width('100%')
    .borderRadius(18)
    .backgroundColor(Color.White)
  }

  @Builder switchRow(title: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .borderRadius(14)
    .backgroundColor($r('app.color.nav_background'))
  }

  @Builder pathRow() {
    Row() {
      Column({ space: 4 }) {
        Text('备份路径')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        Text(this.settings.remotePath)
          .fontSize(12)
          .fontColor($r('app.color.common_font_gray'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.common_right'))
    }
    .width('100%')
    .height(58)
    .padding({ left: 14, right: 14 })
    .borderRadius(14)
    .backgroundColor($r('app.color.nav_background'))
    .onClick(() => {
      this.showPathSelect = true;
    })
  }

  @Builder optionButton(title: string, selected: boolean, onClick: () => void) {
    Button(title)
      .fontSize(14)
      .fontColor(selected ? Color.White : Color.Black)
      .layoutWeight(1)
      .height(38)
      .backgroundColor(selected ? $r('app.color.select_primary') : $r('app.color.nav_background'))
      .onClick(onClick)
  }

  @Builder pathSelectSheet() {
    PathSelectSheet({
      title: $r('app.string.backup_to'),
      filterDirId: '',
      onClose: (isFinished: boolean, path?: string) => {
        this.showPathSelect = false;
        if (isFinished && path && path.length > 0) {
          this.updateRemotePath(path);
        }
      }
    })
  }
}
