import Constant from "../model/Constant";
import { image } from "@kit.ImageKit";
import { CloudApi } from "../model/net/CloudApi";
import { ImagePreview, PreviewFile } from "../model/Params";
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from "@kit.MediaLibraryKit";
import { showToast } from "../utils/ToastUtil";
import { systemShare } from "@kit.ShareKit";
import { uniformTypeDescriptor } from "@kit.ArkData";
import { common } from "@kit.AbilityKit";
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial } from "@kit.UIDesignKit";
import { CloudThemeToken } from "../model/CloudTheme";
import { FileSystemUtil } from "../utils/FileSystemUtil";
import { CloudRouter } from "../utils/CloudRouter";
import AppLogger from "../utils/AppLogger";
import UserPreferences from "../model/UserPreferences";
import { CommonUtil } from "../utils/CommonUtil";

const TAG: string = 'ImagePreview'

@Component
export struct ImagePreviewPage {
  routeParam?: ImagePreview
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0;
  @State isLoading: boolean = true;
  @State currentIndex: number = 0
  @State previewFiles: PreviewFile[] = []
  @State previewRevision: number = 0
  @State loadingIds: string[] = []
  @State failedIds: string[] = []
  @State imageDraggable: boolean = false
  private fileParam: ImagePreview|null = null;
  private swiperController: SwiperController = new SwiperController();
  private imagePixelMaps: Map<string, PixelMap> = new Map<string, PixelMap>();
  private imageDataMap: Map<string, ArrayBuffer> = new Map<string, ArrayBuffer>();
  // GIF 等动图：PixelMap 仅单帧会定格，改用临时文件的 file:// URI 交给 Image 播放动画。
  private imageFileUris: Map<string, string> = new Map<string, string>();
  private tempImageFiles: string[] = [];

  @State saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.SAVE_IMAGE,
    buttonType: ButtonType.Capsule
  } // 设置安全控件按钮属性

  async loadImageAt(index: number) {
    const previewItem = this.getPreviewItem(index)
    if (!previewItem) {
      AppLogger.error(TAG, 'Missing image preview route param');
      this.isLoading = false;
      return;
    }

    if (this.hasImage(previewItem.fileId) || this.loadingIds.includes(previewItem.fileId)) {
      this.isLoading = this.isCurrentIndex(index) && !this.hasImage(previewItem.fileId)
      return
    }

    this.markLoading(previewItem.fileId, true)
    if (this.isCurrentIndex(index)) {
      this.isLoading = true
    }

    CloudApi.getDownloadUri(previewItem.fileId, {
      onSuccess: async (url: string) => {
        const resolvedUrl = (url.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
          url.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) ? url : CloudApi.getBaseURL() + url
        const req = http.createHttp();
        try {
          const resp = await req.request(resolvedUrl, {
            method: http.RequestMethod.GET,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            maxLimit: Constant.IMAGE_PREVIEW_MAX_DOWNLOAD_BYTES,
          });
          if (resp.responseCode === Constant.HTTP_STATUS_OK) {
            const imageData = resp.result as ArrayBuffer;
            this.imageDataMap.set(previewItem.fileId, imageData)
            const animatedUri = await this.materializeAnimatedImage(previewItem, imageData)
            if (animatedUri.length > 0) {
              this.imageFileUris.set(previewItem.fileId, animatedUri)
            } else {
              const imageSource = image.createImageSource(imageData);
              const pixMap = await imageSource.createPixelMap();
              imageSource.release();
              this.imagePixelMaps.set(previewItem.fileId, pixMap)
            }
            this.markFailed(previewItem.fileId, false)
            this.previewRevision++
          } else {
            this.markFailed(previewItem.fileId, true)
          }
        } catch (err) {
          AppLogger.error(TAG, `Load preview failed: ${(err as Error)?.message ?? err}`);
          this.markFailed(previewItem.fileId, true)
        } finally {
          req.destroy();
          this.markLoading(previewItem.fileId, false)
          if (this.getCurrentPreviewItem()?.fileId === previewItem.fileId) {
            this.isLoading = false;
          }
        }
      },
      onFailure: (msg) => {
        AppLogger.error(TAG, `Get download URI failed: ${msg}`);
        this.markFailed(previewItem.fileId, true)
        this.markLoading(previewItem.fileId, false)
        if (this.getCurrentPreviewItem()?.fileId === previewItem.fileId) {
          this.isLoading = false;
        }
      }
    });
  }

  aboutToAppear(): void {
    if (this.routeParam) {
      this.fileParam = this.routeParam
    }
    AppLogger.info(TAG, `open image preview, gallery=${this.fileParam?.previewFiles?.length ?? 1}`)
    this.previewFiles = this.fileParam?.previewFiles?.length ? this.fileParam.previewFiles :
      [new PreviewFile(this.fileParam?.fileName ?? '', this.fileParam?.fileId ?? '', this.fileParam?.fileExtension ?? '')]
    this.currentIndex = this.normalizeIndex(this.fileParam?.currentIndex ?? 0)
    this.imageDraggable = UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.IMAGE_DRAGGABLE_ENABLED, false) as boolean
    this.loadImageAt(this.currentIndex)
    this.prefetchAround(this.currentIndex)
  }

  aboutToDisappear(): void {
    this.tempImageFiles.forEach((path: string) => {
      FileSystemUtil.unlinkIfExists(path)
    })
    this.tempImageFiles = []
  }

  build() {
    HdsNavigation() {
      Stack() {
        Swiper(this.swiperController) {
          ForEach(this.previewFiles, (item: PreviewFile, index: number) => {
            this.previewItem(item, index)
          }, (item: PreviewFile, index: number) => item.fileId + index)
        }
        .index(this.currentIndex)
        .loop(false)
        .indicator(false)
        .onChange((index: number) => {
          this.currentIndex = this.normalizeIndex(index)
          const previewItem = this.getCurrentPreviewItem()
          this.isLoading = previewItem ? !this.imagePixelMaps.has(previewItem.fileId) && !this.isImageFailed(previewItem.fileId) : false
          this.loadImageAt(this.currentIndex)
          this.prefetchAround(this.currentIndex)
        })
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.previewBackground)

        this.navArrows()
      }
      .width('100%')
      .backgroundColor(CloudThemeToken.previewBackground)
      .layoutWeight(1)

      this.previewCounter()

      Column() {
        SaveButton(this.saveButtonOptions)
          .onClick(() => {
            this.saveImage()
          })
      }
      .width('100%')
      .backgroundColor(CloudThemeToken.previewBackground)
      .alignItems(HorizontalAlign.Center)
      .padding({
        top: CloudThemeToken.imagePreviewSaveTopPadding,
        bottom: this.bottomRectHeight + CloudThemeToken.imagePreviewSaveBottomPadding +
        CloudThemeToken.imagePreviewSaveBottomLift
      })
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideBackButton(false)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: this.getHeaderTitle()
        },
        backIcon: {
          icon: $r('app.media.ic_xmark_bold'),
          action: () => {
            CloudRouter.pop()
          }
        },
        menu: {
          value: [{
            content: {
              icon: $r('app.media.ic_share'),
              action: () => {
                this.shareImage()
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: CloudThemeToken.previewTitleBarBackground
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.onPrimary
            },
            backIconStyle: {
              backgroundColor: CloudThemeToken.videoPreviewControlBackground,
              iconColor: CloudThemeToken.onPrimary
            },
            menuStyle: {
              backgroundColor: CloudThemeToken.videoPreviewControlBackground,
              iconColor: CloudThemeToken.onPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .backgroundColor(CloudThemeToken.previewBackground)
  }

  @Builder previewCounter() {
    if (this.previewFiles.length > 1) {
      Row() {
        Text(this.getPreviewCounterText())
          .fontSize(CloudThemeToken.imagePreviewCounterTextSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.onPrimary)
          .height(CloudThemeToken.imagePreviewCounterHeight)
          .padding({
            left: CloudThemeToken.spacingPanel,
            right: CloudThemeToken.spacingPanel
          })
          .borderRadius(CloudThemeToken.controlRadiusRoundMd)
          .backgroundColor(CloudThemeToken.imagePreviewCounterBackground)
      }
      .width('100%')
      .height(CloudThemeToken.imagePreviewCounterAreaHeight)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(CloudThemeToken.previewBackground)
    }
  }

  @Builder navArrows() {
    if (CloudThemeToken.isWideWidth(this.windowWidthVp) && this.previewFiles.length > 1) {
      Row() {
        this.navArrowButton(false)
        this.navArrowButton(true)
      }
      .width('100%')
      .height('100%')
      .padding({ left: CloudThemeToken.spacingPage, right: CloudThemeToken.spacingPage })
      .justifyContent(FlexAlign.SpaceBetween)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder navArrowButton(isNext: boolean) {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph(isNext ? $r('sys.symbol.chevron_right') : $r('sys.symbol.chevron_left'))
        .fontSize(CloudThemeToken.imagePreviewArrowIconSize)
        .fontColor([CloudThemeToken.onPrimary])
        .fontWeight(FontWeight.Medium)
    }
    .width(CloudThemeToken.imagePreviewArrowButtonSize)
    .height(CloudThemeToken.imagePreviewArrowButtonSize)
    .backgroundColor(CloudThemeToken.videoPreviewControlBackground)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .enabled(this.canNavigate(isNext))
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
    return isNext ? this.currentIndex < this.previewFiles.length - 1 : this.currentIndex > 0
  }

  private getPreviewContentTopPadding(): number {
    return CloudThemeToken.getSafeTopInset(this.sysTopRectHeight) +
      CloudThemeToken.titleBarHeight +
      CloudThemeToken.spacingSm
  }

  @Builder previewItem(item: PreviewFile, index: number) {
    Column() {
      if (this.hasImage(item.fileId)) {
        Image(this.getImageSource(item.fileId))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .draggable(this.imageDraggable)
      } else if (this.isImageFailed(item.fileId)) {
        Image($r('app.media.ic_picture_damage'))
          .width(CloudThemeToken.imagePreviewErrorImageSize)
          .height(CloudThemeToken.imagePreviewErrorImageSize)
          .objectFit(ImageFit.Contain)
      } else {
        LoadingProgress()
          .width(CloudThemeToken.iconButtonSize)
          .height(CloudThemeToken.iconButtonSize)
          .visibility(this.isCurrentIndex(index) || this.isImageLoading(item.fileId) ? Visibility.Visible : Visibility.Hidden)
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.getPreviewContentTopPadding(),
      bottom: CloudThemeToken.spacingPage
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(CloudThemeToken.previewBackground)
  }

  async saveImage() {
    const previewItem = this.getCurrentPreviewItem()
    const imageData = this.getCurrentImageData()
    if (previewItem && imageData) {
      try {
        const context = this.getAbilityContext();
        if (!context) {
          showToast('保存至相册失败')
          return
        }
        let photoType: photoAccessHelper.PhotoType = photoAccessHelper.PhotoType.IMAGE;
        let extension: string = previewItem.fileExtension;
        let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
        let createOption: photoAccessHelper.CreateOptions = {
          title: CommonUtil.sanitizeAlbumTitle(previewItem.fileName)
        };
        let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
          photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(context, photoType, extension, createOption);
        assetChangeRequest.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, imageData);
        await phAccessHelper.applyChanges(assetChangeRequest);
        showToast('已保存至相册')
      } catch(err) {
        AppLogger.error(TAG, `addResourceByArrayBufferDemo failed with error: ${err.code}, ${err.message}`);
        showToast('保存至相册失败')
      }
    }
  }

  async shareImage() {
    const previewItem = this.getCurrentPreviewItem()
    const imageData = this.getCurrentImageData()
    if (previewItem && imageData) {
      let tempPath: string = ''
      try {
        const context = this.getAbilityContext();
        if (!context) {
          showToast('分享失败')
          return
        }
        tempPath = context.tempDir + '/' + previewItem.fileName
        let uri = FileSystemUtil.getUriFromPath(tempPath)
        console.debug(TAG, 'uri: ' + uri)
        await FileSystemUtil.writeArrayBuffer(tempPath, imageData)
        let data: systemShare.SharedData = new systemShare.SharedData({
          utd: uniformTypeDescriptor.UniformDataType.IMAGE,
          title: previewItem.fileName,
          uri: uri
        })
        let controller: systemShare.ShareController = new systemShare.ShareController(data)
        controller.show(context, {
          previewMode: systemShare.SharePreviewMode.DEFAULT,
          selectionMode: systemShare.SelectionMode.SINGLE
        })
        controller.on('dismiss', () => {
          console.debug(TAG, 'share dismiss, unlink image file!')
          FileSystemUtil.unlinkIfExists(tempPath)
        })
      } catch(err) {
        AppLogger.error(TAG, `share image failed with error: ${err.code}, ${err.message}`);
        if (tempPath.length > 0) {
          FileSystemUtil.unlinkIfExists(tempPath)
        }
        showToast('分享失败')
      }
    }
  }

  private normalizeIndex(index: number): number {
    if (this.previewFiles.length === 0) {
      return 0
    }
    return Math.max(0, Math.min(index, this.previewFiles.length - 1))
  }

  private getPreviewItem(index: number): PreviewFile | undefined {
    if (index < 0 || index >= this.previewFiles.length) {
      return undefined
    }
    return this.previewFiles[index]
  }

  private getCurrentPreviewItem(): PreviewFile | undefined {
    return this.getPreviewItem(this.currentIndex)
  }

  private getCurrentImageData(): ArrayBuffer | undefined {
    const previewItem = this.getCurrentPreviewItem()
    if (!previewItem) {
      return undefined
    }
    return this.imageDataMap.get(previewItem.fileId)
  }

  private getHeaderTitle(): string {
    const previewItem = this.getCurrentPreviewItem()
    if (!previewItem) {
      return ''
    }
    return previewItem.fileName
  }

  private getPreviewCounterText(): string {
    return `${this.currentIndex + 1}/${this.previewFiles.length}`
  }

  private prefetchAround(index: number): void {
    this.loadImageAt(index - 1)
    this.loadImageAt(index + 1)
  }

  // 仅 GIF（魔数 "GIF8"）落盘为临时文件，返回其 file:// URI 供 Image 播放动画；其余返回 '' 走单帧 PixelMap。
  private async materializeAnimatedImage(previewItem: PreviewFile, imageData: ArrayBuffer): Promise<string> {
    if (!this.isGifData(imageData)) {
      return ''
    }
    const context = this.getAbilityContext()
    if (!context) {
      return ''
    }
    try {
      const tempPath = `${context.cacheDir}/preview_${CommonUtil.sanitizeAlbumTitle(previewItem.fileName)}.gif`
      await FileSystemUtil.writeArrayBuffer(tempPath, imageData)
      if (!this.tempImageFiles.includes(tempPath)) {
        this.tempImageFiles.push(tempPath)
      }
      return FileSystemUtil.getUriFromPath(tempPath)
    } catch (err) {
      AppLogger.error(TAG, `materialize animated image failed: ${(err as Error)?.message ?? err}`)
      return ''
    }
  }

  private isGifData(data: ArrayBuffer): boolean {
    if (data.byteLength < 4) {
      return false
    }
    const head = new Uint8Array(data, 0, 4)
    // "GIF8" → 0x47 0x49 0x46 0x38（覆盖 GIF87a / GIF89a）
    return head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x38
  }

  private hasImage(fileId: string): boolean {
    this.previewRevision
    return this.imagePixelMaps.has(fileId) || this.imageFileUris.has(fileId)
  }

  private getImageSource(fileId: string): PixelMap | ResourceStr {
    this.previewRevision
    const animatedUri = this.imageFileUris.get(fileId)
    if (animatedUri) {
      return animatedUri
    }
    return this.imagePixelMaps.get(fileId) ?? $r('app.media.ic_picture_damage')
  }

  private isCurrentIndex(index: number): boolean {
    return index === this.currentIndex
  }

  private isImageLoading(fileId: string): boolean {
    return this.loadingIds.includes(fileId)
  }

  private isImageFailed(fileId: string): boolean {
    return this.failedIds.includes(fileId)
  }

  private markLoading(fileId: string, loading: boolean): void {
    if (loading) {
      if (!this.loadingIds.includes(fileId)) {
        this.loadingIds = this.loadingIds.concat([fileId])
      }
    } else {
      this.loadingIds = this.loadingIds.filter((id: string) => id !== fileId)
    }
  }

  private markFailed(fileId: string, failed: boolean): void {
    if (failed) {
      if (!this.failedIds.includes(fileId)) {
        this.failedIds = this.failedIds.concat([fileId])
      }
    } else {
      this.failedIds = this.failedIds.filter((id: string) => id !== fileId)
    }
  }

  getAbilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      return undefined
    }
    return hostContext as common.UIAbilityContext
  }
}
