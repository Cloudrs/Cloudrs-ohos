import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupItem, PhotoBackupStatus } from '../model/PhotoBackupModel';
import { PhotoLocalPreviewParam } from '../model/Params';
import { CommonUtil } from '../utils/CommonUtil';
import { DateFormatUtil } from '../utils/DateFormatUtil';
import LazyDataSource from '../utils/LazyDataSource';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

const TAG: string = 'PhotoLocalPreview'
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
  @State chromeVisible: boolean = true

  aboutToAppear(): void {
    if (this.routeParam) {
      this.items = this.routeParam.items
      this.index = Math.max(0, Math.min(this.routeParam.index, this.routeParam.items.length - 1))
      this.backupEnabled = this.routeParam.backupEnabled
      this.itemSource.replaceAll(this.items)
    }
    console.info(TAG, `preview count=${this.items.length} index=${this.index}`)
  }

  aboutToDisappear(): void {
    // Always restore system bars when leaving the immersive preview.
    this.setSystemBars(true)
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
      LoadingProgress()
        .width(48)
        .height(48)
        .color(Color.White)
      Image(item.uri)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .onError(() => { console.warn(TAG, `image load failed: ${item.name}`) })
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
