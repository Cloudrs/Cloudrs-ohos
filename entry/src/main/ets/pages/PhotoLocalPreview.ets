import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupItem, PhotoBackupStatus } from '../model/PhotoBackupModel';
import { PhotoLocalPreviewParam } from '../model/Params';
import { CommonUtil } from '../utils/CommonUtil';
import { DateFormatUtil } from '../utils/DateFormatUtil';
import LazyDataSource from '../utils/LazyDataSource';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { dataSharePredicates } from '@kit.ArkData';
import { window } from '@kit.ArkUI';

const TAG: string = 'PhotoLocalPreview'
const PREVIEW_MAX_SIDE: number = 2560
const PRELOAD_RADIUS: number = 1
const CHROME_ANIM_DURATION: number = 220

@Component
export struct PhotoLocalPreviewPage {
  routeParam?: PhotoLocalPreviewParam
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @State items: PhotoBackupItem[] = []
  @State index: number = 0
  @State backupEnabled: boolean = false
  @State itemSource: LazyDataSource<PhotoBackupItem> = new LazyDataSource()
  @State previews: Map<string, PixelMap> = new Map<string, PixelMap>()
  @State chromeVisible: boolean = true
  private loadingIds: Set<string> = new Set<string>()

  aboutToAppear(): void {
    if (this.routeParam) {
      this.items = this.routeParam.items
      this.index = Math.max(0, Math.min(this.routeParam.index, this.routeParam.items.length - 1))
      this.backupEnabled = this.routeParam.backupEnabled
      this.itemSource.replaceAll(this.items)
    }
    console.info(TAG, `preview local photos count=${this.items.length} index=${this.index}`)
    this.loadAround(this.index)
  }

  aboutToDisappear(): void {
    // Always restore system bars when leaving the immersive preview.
    this.setSystemBars(true)
  }

  /** Load the current photo plus its immediate neighbors as PixelMaps. */
  private loadAround(center: number): void {
    for (let offset = -PRELOAD_RADIUS; offset <= PRELOAD_RADIUS; offset++) {
      const i = center + offset
      if (i >= 0 && i < this.items.length) {
        this.loadPreview(this.items[i])
      }
    }
  }

  private async loadPreview(item: PhotoBackupItem): Promise<void> {
    if (this.previews.has(item.id) || this.loadingIds.has(item.id)) {
      return
    }
    this.loadingIds.add(item.id)
    let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
      if (!context) {
        return
      }
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      const predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates()
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, item.uri)
      const fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [
          photoAccessHelper.PhotoKeys.URI,
          photoAccessHelper.PhotoKeys.WIDTH,
          photoAccessHelper.PhotoKeys.HEIGHT
        ],
        predicates: predicates
      }
      fetchResult = await helper.getAssets(fetchOptions)
      const assets: photoAccessHelper.PhotoAsset[] = await fetchResult.getAllObjects()
      if (assets.length === 0) {
        console.warn(TAG, `preview asset not found: ${item.name}`)
        return
      }
      const asset = assets[Constant.FIRST_ARRAY_INDEX]
      const size: image.Size = this.computeThumbnailSize(asset)
      const pixelMap: PixelMap = await asset.getThumbnail(size)
      const next = new Map<string, PixelMap>(this.previews)
      next.set(item.id, pixelMap)
      this.previews = next
    } catch (err) {
      console.warn(TAG, `load preview failed: ${(err as Error)?.message ?? err}`)
    } finally {
      if (fetchResult) {
        fetchResult.close()
      }
      this.loadingIds.delete(item.id)
    }
  }

  /** Target size that preserves the asset aspect ratio (so tall screenshots aren't cropped). */
  private computeThumbnailSize(asset: photoAccessHelper.PhotoAsset): image.Size {
    let width = 0
    let height = 0
    try {
      width = (asset.get(photoAccessHelper.PhotoKeys.WIDTH) as number) ?? 0
      height = (asset.get(photoAccessHelper.PhotoKeys.HEIGHT) as number) ?? 0
    } catch (err) {
      width = 0
      height = 0
    }
    if (width <= 0 || height <= 0) {
      return { width: PREVIEW_MAX_SIDE, height: PREVIEW_MAX_SIDE }
    }
    const maxSide = Math.max(width, height)
    const scale = maxSide > PREVIEW_MAX_SIDE ? PREVIEW_MAX_SIDE / maxSide : 1
    return { width: Math.round(width * scale), height: Math.round(height * scale) }
  }

  private toggleChrome(): void {
    const next = !this.chromeVisible
    this.getUIContext().animateTo({ duration: CHROME_ANIM_DURATION, curve: Curve.EaseInOut }, () => {
      this.chromeVisible = next
    })
    this.setSystemBars(next)
  }

  /** Hide/show the system status & navigation bars for immersive full-screen. */
  private async setSystemBars(visible: boolean): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
      if (!context) {
        return
      }
      const win: window.Window = await window.getLastWindow(context)
      await win.setWindowSystemBarEnable(visible ? ['status', 'navigation'] : [])
    } catch (err) {
      console.warn(TAG, `set system bars failed: ${(err as Error)?.message ?? err}`)
    }
  }

  private statusLine(item: PhotoBackupItem): string {
    if (item.status === PhotoBackupStatus.COMPLETED) {
      return '已备份'
    }
    if (!this.backupEnabled) {
      return '未备份'
    }
    if (item.status === PhotoBackupStatus.UPLOADING) {
      return '上传中'
    }
    if (item.status === PhotoBackupStatus.FAILED) {
      return '备份失败'
    }
    return '待备份'
  }

  @Builder slide(item: PhotoBackupItem) {
    Stack() {
      if (this.previews.has(item.id)) {
        Image(this.previews.get(item.id))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(Color.White)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder infoBar(item: PhotoBackupItem) {
    Column({ space: CloudThemeToken.spacingXs }) {
      Text(item.name)
        .fontSize(CloudThemeToken.textSizeBodyPlus)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(`${DateFormatUtil.format(new Date(item.modifiedAt), 'yyyy/MM/dd HH:mm')} · ${CommonUtil.formatBytes(item.size)}`)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor('rgba(255, 255, 255, 0.75)')
        .width('100%')

      Text(this.statusLine(item))
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.primary)
        .width('100%')
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingPage,
      right: CloudThemeToken.spacingPage,
      top: CloudThemeToken.spacingPanel,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingPanel
    })
    .backgroundColor('rgba(0, 0, 0, 0.32)')
    .backdropBlur(18)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper() {
        LazyForEach(this.itemSource, (item: PhotoBackupItem) => {
          this.slide(item)
        }, (item: PhotoBackupItem) => item.id)
      }
      .index(this.index)
      .loop(false)
      .indicator(false)
      .cachedCount(1)
      .onChange((i: number) => {
        this.index = i
        this.loadAround(i)
      })
      .width('100%')
      .height('100%')

      if (this.items.length > 0 && this.index < this.items.length) {
        Column() {
          this.infoBar(this.items[this.index])
        }
        .width('100%')
        .opacity(this.chromeVisible ? 1 : 0)
        .translate({ y: this.chromeVisible ? 0 : 40 })
        .hitTestBehavior(this.chromeVisible ? HitTestMode.Default : HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onClick(() => {
      this.toggleChrome()
    })
  }
}
