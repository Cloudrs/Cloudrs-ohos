import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupItem, PhotoBackupStatus } from '../model/PhotoBackupModel';
import { PhotoLocalPreviewParam } from '../model/Params';
import { CommonUtil } from '../utils/CommonUtil';
import { DateFormatUtil } from '../utils/DateFormatUtil';
import LazyDataSource from '../utils/LazyDataSource';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import AppLogger from '../utils/AppLogger';
import { CloudRouter } from '../utils/CloudRouter';
import UserPreferences from '../model/UserPreferences';
import { ZoomableImage } from '../components/ZoomableImage';

const TAG: string = 'PhotoLocalPreview'
const CHROME_ANIM_DURATION: number = 220

@Component
export struct PhotoLocalPreviewPage {
  routeParam?: PhotoLocalPreviewParam
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0
  @State items: PhotoBackupItem[] = []
  @State index: number = 0
  @State backupEnabled: boolean = false
  @State itemSource: LazyDataSource<PhotoBackupItem> = new LazyDataSource()
  @State chromeVisible: boolean = true
  @State imageDraggable: boolean = false
  // 系统 AI 识图:用户偏好开启且设备支持主体分割时,预览图长按可抠主体。
  @State aiAnalyzerEnabled: boolean = false
  // 当前图片处于放大状态时禁用 Swiper 翻页,把单指拖动让给图片平移。
  @State zoomDisableSwipe: boolean = false
  private swiperController: SwiperController = new SwiperController()

  aboutToAppear(): void {
    if (this.routeParam) {
      this.items = this.routeParam.items
      this.index = Math.max(0, Math.min(this.routeParam.index, this.routeParam.items.length - 1))
      this.backupEnabled = this.routeParam.backupEnabled
      this.itemSource.replaceAll(this.items)
    }
    this.imageDraggable = UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.IMAGE_DRAGGABLE_ENABLED, false) as boolean
    this.aiAnalyzerEnabled = CommonUtil.isImageAiAnalyzerEnabled()
    console.info(TAG, `preview count=${this.items.length} index=${this.index}`)
    harmonyShare.on('knockShare', this.knockShareCallback)
  }

  aboutToDisappear(): void {
    harmonyShare.off('knockShare', this.knockShareCallback)
    // Always restore system bars when leaving the immersive preview.
    this.setSystemBars(true)
  }

  private knockShareCallback = (sharableTarget: harmonyShare.SharableTarget): void => {
    this.handleKnockShare(sharableTarget)
  }

  private async handleKnockShare(sharableTarget: harmonyShare.SharableTarget): Promise<void> {
    const item = this.items[this.index]
    try {
      if (!item || item.uri.length === 0 || !item.localExists) {
        await sharableTarget.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR)
        return
      }
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.IMAGE,
        title: item.name,
        uri: item.uri
      })
      await sharableTarget.share(shareData)
    } catch (err) {
      AppLogger.error(TAG, `knock share failed: ${(err as Error)?.message ?? err}`)
    }
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
      AppLogger.warn(TAG, `set system bars failed: ${(err as Error)?.message ?? err}`)
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

  @Builder slide(item: PhotoBackupItem, index: number) {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack() {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(Color.White)
        ZoomableImage({
          imageSource: item.uri,
          imageDraggable: this.imageDraggable,
          enableAiAnalyzer: this.aiAnalyzerEnabled,
          isActive: index === this.index,
          onZoomChange: (zoomed: boolean) => {
            if (index === this.index) {
              this.zoomDisableSwipe = zoomed
            }
          },
          // 单击切换沉浸式 chrome;放进手势组与双击缩放互斥,避免双击被误判成两次单击。
          onSingleTap: () => { this.toggleChrome() },
          onImageError: () => { AppLogger.warn(TAG, `image load failed: ${item.name}`) }
        })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height('100%')

      // Per-slide info bar so the status always matches the visible photo.
      Column() {
        this.infoBar(item)
      }
      .width('100%')
      .opacity(this.chromeVisible ? 1 : 0)
      .translate({ y: this.chromeVisible ? 0 : 40 })
      .hitTestBehavior(this.chromeVisible ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => { this.toggleChrome() })
    }
    .width('100%')
    .height('100%')
  }

  @Builder infoBar(item: PhotoBackupItem) {
    // 文件名已移到顶栏,剩余信息合并为单行,降低底栏高度
    Row() {
      Text(`${DateFormatUtil.format(new Date(item.modifiedAt), 'yyyy/MM/dd HH:mm')} · ${CommonUtil.formatBytes(item.size)}`)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor('rgba(255, 255, 255, 0.75)')

      Blank()

      Text(this.statusLine(item))
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.primary)
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

  @Builder topChrome() {
    Row({ space: CloudThemeToken.spacingCard }) {
      this.backButton()
      Text(this.items[this.index]?.name ?? '')
        .fontSize(CloudThemeToken.textSizeBodyPlus)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 文件名多为无空格长串,按词边界截断会过早出省略号,改为任意字符处截断
        .wordBreak(WordBreak.BREAK_ALL)
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({
      top: this.sysTopRectHeight + CloudThemeToken.spacingPanel,
      bottom: CloudThemeToken.spacingPanel,
      left: CloudThemeToken.spacingPage,
      right: CloudThemeToken.spacingPage
    })
    .backgroundColor('rgba(0, 0, 0, 0.32)')
    .backdropBlur(18)
    .position({ x: 0, y: 0 })
    .opacity(this.chromeVisible ? 1 : 0)
  }

  @Builder backButton() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(CloudThemeToken.photoLocalPreviewBackIconSize)
        .fontColor([Color.White])
        .fontWeight(FontWeight.Medium)
    }
    .width(CloudThemeToken.videoPreviewControlSize)
    .height(CloudThemeToken.videoPreviewControlSize)
    .backgroundColor(CloudThemeToken.videoPreviewControlBackground)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .enabled(this.chromeVisible)
    .onClick(() => {
      CloudRouter.pop()
    })
  }

  @Builder navArrows() {
    if (CloudThemeToken.isWideWidth(this.windowWidthVp) && this.items.length > 1) {
      Row() {
        this.navArrowButton(false)
        this.navArrowButton(true)
      }
      .width('100%')
      .height('100%')
      .padding({ left: CloudThemeToken.spacingPage, right: CloudThemeToken.spacingPage })
      .justifyContent(FlexAlign.SpaceBetween)
      .hitTestBehavior(HitTestMode.None)
      .opacity(this.chromeVisible ? 1 : 0)
    }
  }

  @Builder navArrowButton(isNext: boolean) {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph(isNext ? $r('sys.symbol.chevron_right') : $r('sys.symbol.chevron_left'))
        .fontSize(CloudThemeToken.imagePreviewArrowIconSize)
        .fontColor([Color.White])
        .fontWeight(FontWeight.Medium)
    }
    .width(CloudThemeToken.imagePreviewArrowButtonSize)
    .height(CloudThemeToken.imagePreviewArrowButtonSize)
    .backgroundColor(CloudThemeToken.videoPreviewControlBackground)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .enabled(this.chromeVisible && this.canNavigate(isNext))
    .opacity(this.canNavigate(isNext) ? 1 : 0.35)
    .onClick(() => {
      if (isNext) {
        this.swiperController.showNext()
      } else {
        this.swiperController.showPrevious()
      }
    })
  }

  private canNavigate(isNext: boolean): boolean {
    return isNext ? this.index < this.items.length - 1 : this.index > 0
  }

  build() {
    Stack() {
      Swiper(this.swiperController) {
        LazyForEach(this.itemSource, (item: PhotoBackupItem, index: number) => {
          this.slide(item, index)
        }, (item: PhotoBackupItem) => item.id)
      }
      .index(this.index)
      .loop(false)
      .indicator(false)
      .disableSwipe(this.zoomDisableSwipe)
      .cachedCount(1)
      .onChange((i: number) => {
        this.index = i
        // 新页总是未缩放状态;旧页重置的回调因索引已切换不会触达这里,须显式复位。
        this.zoomDisableSwipe = false
      })
      .width('100%')
      .height('100%')

      this.navArrows()
      this.topChrome()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
