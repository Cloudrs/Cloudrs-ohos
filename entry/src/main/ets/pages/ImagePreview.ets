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

const TAG: string = 'ImagePreview'

@Component
export struct ImagePreviewPage {
  routeParam?: ImagePreview
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State isLoading: boolean = true;
  @State currentIndex: number = 0
  @State previewFiles: PreviewFile[] = []
  @State previewRevision: number = 0
  @State loadingIds: string[] = []
  @State failedIds: string[] = []
  private fileParam: ImagePreview|null = null;
  private imagePixelMaps: Map<string, PixelMap> = new Map<string, PixelMap>();
  private imageDataMap: Map<string, ArrayBuffer> = new Map<string, ArrayBuffer>();

  @State saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.SAVE_IMAGE,
    buttonType: ButtonType.Capsule
  } // 设置安全控件按钮属性

  async loadImageAt(index: number) {
    const previewItem = this.getPreviewItem(index)
    if (!previewItem) {
      console.error(TAG, 'Missing image preview route param');
      this.isLoading = false;
      return;
    }

    if (this.imagePixelMaps.has(previewItem.fileId) || this.loadingIds.includes(previewItem.fileId)) {
      this.isLoading = this.isCurrentIndex(index) && !this.imagePixelMaps.has(previewItem.fileId)
      return
    }

    this.markLoading(previewItem.fileId, true)
    if (this.isCurrentIndex(index)) {
      this.isLoading = true
    }

    CloudApi.getDownloadUri(previewItem.fileId, {
      onSuccess: async (url: string) => {
        const req = http.createHttp();
        try {
          const resp = await req.request(url, {
            method: http.RequestMethod.GET,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            maxLimit: Constant.IMAGE_PREVIEW_MAX_DOWNLOAD_BYTES,
          });
          if (resp.responseCode === Constant.HTTP_STATUS_OK) {
            const imageData = resp.result as ArrayBuffer;
            const imageSource = image.createImageSource(imageData);
            const pixMap = await imageSource.createPixelMap();
            imageSource.release();
            this.imageDataMap.set(previewItem.fileId, imageData)
            this.imagePixelMaps.set(previewItem.fileId, pixMap)
            this.markFailed(previewItem.fileId, false)
            this.previewRevision++
          } else {
            this.markFailed(previewItem.fileId, true)
          }
        } catch (err) {
          console.error(TAG, `Load preview failed: ${(err as Error)?.message ?? err}`);
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
        console.error(TAG, `Get download URI failed: ${msg}`);
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
    console.info(TAG, `preview param: ${this.fileParam?.fileName ?? ''}, ${this.fileParam?.fileId ?? ''}`)
    this.previewFiles = this.fileParam?.previewFiles?.length ? this.fileParam.previewFiles :
      [new PreviewFile(this.fileParam?.fileName ?? '', this.fileParam?.fileId ?? '', this.fileParam?.fileExtension ?? '')]
    this.currentIndex = this.normalizeIndex(this.fileParam?.currentIndex ?? 0)
    this.loadImageAt(this.currentIndex)
    this.prefetchAround(this.currentIndex)
  }

  build() {
    HdsNavigation() {
      Swiper() {
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

  @Builder previewItem(item: PreviewFile, index: number) {
    Column() {
      if (this.hasImage(item.fileId)) {
        Image(this.getImageSource(item.fileId))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
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
        let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
          photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(context, photoType, extension);
        assetChangeRequest.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, imageData);
        await phAccessHelper.applyChanges(assetChangeRequest);
        showToast('已保存至相册')
      } catch(err) {
        console.error(TAG, `addResourceByArrayBufferDemo failed with error: ${err.code}, ${err.message}`);
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
        console.error(TAG, `share image failed with error: ${err.code}, ${err.message}`);
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

  private hasImage(fileId: string): boolean {
    this.previewRevision
    return this.imagePixelMaps.has(fileId)
  }

  private getImageSource(fileId: string): PixelMap | Resource {
    this.previewRevision
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
