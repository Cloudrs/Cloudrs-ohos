import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { VideoPreview } from "../model/Params";
import { CloudApi } from "../model/net/CloudApi";
import { CloudRouter } from "../utils/CloudRouter";
import { showToast } from "../utils/ToastUtil";
import { CloudIconButton } from "../components/CloudIconButton";

const TAG: string = 'VideoPreview'
const videoDownloadUriCache: Map<string, string> = new Map<string, string>()

@Component
export struct VideoPreviewPage {
  routeParam?: VideoPreview
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @State videoUrl: string = ''
  @State isLoading: boolean = true
  @State isFailed: boolean = false
  @State isPlaying: boolean = false
  @State isSeeking: boolean = false
  @State isFullscreen: boolean = false
  @State currentTime: number = 0
  @State duration: number = 0
  private fileParam: VideoPreview | null = null
  private controller: VideoController = new VideoController()

  aboutToAppear(): void {
    if (this.routeParam) {
      this.fileParam = this.routeParam
    }
    this.loadVideoUrl()
  }

  build() {
    Column() {
      if (!this.isFullscreen) {
        Blank().height(CloudThemeToken.getSafeTopInset(this.sysTopRectHeight))
        this.previewHeader()
      }

      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.videoUrl.length > CloudThemeToken.zero) {
            Video({
              src: this.videoUrl,
              controller: this.controller
            })
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .autoPlay(false)
              .controls(false)
              .onPrepared((event) => {
                this.duration = Math.max(event.duration, CloudThemeToken.zero)
                this.isLoading = false
                this.isPlaying = true
                this.controller.start()
              })
              .onStart(() => {
                this.isPlaying = true
                this.isLoading = false
              })
              .onPause(() => {
                this.isPlaying = false
              })
              .onFinish(() => {
                this.isPlaying = false
                this.currentTime = this.duration
              })
              .onUpdate((event) => {
                if (!this.isSeeking) {
                  this.currentTime = Math.min(event.time, this.getSafeDuration())
                }
              })
              .onError(() => {
                this.isPlaying = false
                this.isLoading = false
                this.isFailed = true
                showToast('视频播放失败')
              })
              .onClick(() => {
                this.togglePlayback()
              })
          }

          if (this.isLoading) {
            Column({ space: CloudThemeToken.spacingSection }) {
              LoadingProgress()
                .width(CloudThemeToken.iconButtonSize)
                .height(CloudThemeToken.iconButtonSize)
                .color(CloudThemeToken.primary)
              Text('正在打开视频')
                .fontSize(CloudThemeToken.textSizeBody)
                .fontColor(CloudThemeToken.onPrimary)
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
          }

          if (this.isFailed) {
            Column({ space: CloudThemeToken.spacingSection }) {
              Image($r('app.media.ic_file_video'))
                .width(CloudThemeToken.imagePreviewErrorImageSize)
                .height(CloudThemeToken.imagePreviewErrorImageSize)
                .fillColor(CloudThemeToken.textSecondary)
              Text('视频预览失败')
                .fontSize(CloudThemeToken.textSizeBodyPlus)
                .fontColor(CloudThemeToken.onPrimary)
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .height('100%')

        if (this.isFullscreen) {
          this.fullscreenCloseButton()
        }

        if (this.videoUrl.length > CloudThemeToken.zero && !this.isFailed) {
          this.videoControls()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(CloudThemeToken.previewBackground)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.previewBackground)
  }

  @Builder previewHeader() {
    Column() {
      Row() {
        CloudIconButton({
          icon: $r('app.media.ic_xmark_bold'),
          buttonSize: CloudThemeToken.smallIconButtonSize,
          iconSize: CloudThemeToken.sheetActionIconSize,
          buttonBackground: CloudThemeToken.previewCloseButtonBackground,
          iconColor: CloudThemeToken.previewCloseIcon,
          onAction: () => {
            CloudRouter.pop()
          }
        })

        Text(this.fileParam?.fileName ?? '')
          .fontSize(CloudThemeToken.imagePreviewTitleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .textAlign(TextAlign.Center)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
          .layoutWeight(1)

        Blank()
          .width(CloudThemeToken.smallIconButtonSize)
          .height(CloudThemeToken.smallIconButtonSize)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .padding(CloudThemeToken.imagePreviewHeaderPadding)
      Divider().strokeWidth(CloudThemeToken.imagePreviewDividerWidth).color(CloudThemeToken.line)
    }
    .justifyContent(FlexAlign.Center)
    .height(CloudThemeToken.titleBarHeight)
    .width('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  private loadVideoUrl(): void {
    if (!this.fileParam) {
      this.isLoading = false
      this.isFailed = true
      return
    }

    this.isLoading = true
    this.isFailed = false
    const cachedUrl = videoDownloadUriCache.get(this.fileParam.fileId)
    if (cachedUrl && cachedUrl.length > CloudThemeToken.zero) {
      this.videoUrl = cachedUrl
      return
    }
    CloudApi.getDownloadUri(this.fileParam.fileId, {
      onSuccess: (url: string) => {
        videoDownloadUriCache.set(this.fileParam!.fileId, url)
        this.videoUrl = url
      },
      onFailure: (msg: string) => {
        console.error(TAG, `Get video download URI failed: ${msg}`)
        this.isLoading = false
        this.isFailed = true
        showToast('获取视频地址失败')
      }
    })
  }

  @Builder videoControls() {
    Column({ space: CloudThemeToken.spacingXs }) {
      Slider({
        value: this.currentTime,
        min: CloudThemeToken.zero,
        max: this.getSafeDuration(),
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .height(CloudThemeToken.rowHeightSm)
        .selectedColor(CloudThemeToken.primary)
        .trackColor('rgba(255, 255, 255, 0.28)')
        .blockColor(CloudThemeToken.onPrimary)
        .trackThickness(CloudThemeToken.spacingXs)
        .blockSize({
          width: CloudThemeToken.spacingPage,
          height: CloudThemeToken.spacingPage
        })
        .onChange((value: number, mode: SliderChangeMode) => {
          this.onSeek(value, mode)
        })

      Row({ space: CloudThemeToken.spacingCard }) {
        this.playbackButton()

        Text(`${this.formatTime(this.currentTime)} / ${this.formatTime(this.duration)}`)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.onPrimary)
          .textAlign(TextAlign.Start)
          .layoutWeight(1)

        this.fullscreenButton()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSection,
      right: CloudThemeToken.spacingSection,
      top: CloudThemeToken.spacingXl,
      bottom: CloudThemeToken.spacingSection
    })
    .margin({
      left: CloudThemeToken.spacingPage,
      right: CloudThemeToken.spacingPage,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingPage
    })
    .borderRadius(CloudThemeToken.videoPreviewControlsPanelRadius)
    .backgroundColor(CloudThemeToken.videoPreviewControlsBackground)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
  }

  @Builder fullscreenCloseButton() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() {
        this.videoControlButton($r('app.media.ic_xmark_bold'), CloudThemeToken.videoPreviewCloseIconSize, () => {
          CloudRouter.pop()
        })
      }
        .margin({
          left: CloudThemeToken.spacingPage,
          top: CloudThemeToken.getSafeTopInset(this.sysTopRectHeight) + CloudThemeToken.spacingCard
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder playbackButton() {
    Stack() {
      if (this.isPlaying) {
        Image($r('app.media.ic_pause_fill'))
          .width(CloudThemeToken.videoPreviewControlIconSize)
          .height(CloudThemeToken.videoPreviewControlIconSize)
          .fillColor(CloudThemeToken.onPrimary)
          .draggable(false)
      } else {
        Image($r('app.media.ic_play_fill'))
          .width(CloudThemeToken.videoPreviewControlIconSize)
          .height(CloudThemeToken.videoPreviewControlIconSize)
          .fillColor(CloudThemeToken.onPrimary)
          .draggable(false)
      }
    }
    .width(CloudThemeToken.videoPreviewControlSize)
    .height(CloudThemeToken.videoPreviewControlSize)
    .borderRadius(CloudThemeToken.videoPreviewControlSize / CloudThemeToken.halfDivisor)
    .backgroundColor(CloudThemeToken.videoPreviewControlBackground)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .border({
      width: CloudThemeToken.videoPreviewControlBorderWidth,
      color: CloudThemeToken.videoPreviewControlBorder
    })
    .clip(true)
    .onClick(() => {
      this.togglePlayback()
    })
  }

  @Builder videoControlButton(icon: ResourceStr, iconSize: number, onAction: () => void) {
    Stack() {
      Image(icon)
        .width(iconSize)
        .height(iconSize)
        .fillColor(CloudThemeToken.onPrimary)
        .draggable(false)
    }
    .width(CloudThemeToken.videoPreviewControlSize)
    .height(CloudThemeToken.videoPreviewControlSize)
    .borderRadius(CloudThemeToken.videoPreviewControlSize / CloudThemeToken.halfDivisor)
    .backgroundColor(CloudThemeToken.videoPreviewControlBackground)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .border({
      width: CloudThemeToken.videoPreviewControlBorderWidth,
      color: CloudThemeToken.videoPreviewControlBorder
    })
    .clip(true)
    .onClick(() => {
      onAction()
    })
  }

  @Builder fullscreenButton() {
    Stack() {
      if (this.isFullscreen) {
        Image($r('app.media.ic_fullscreen_exit'))
          .width(CloudThemeToken.videoPreviewControlIconSize)
          .height(CloudThemeToken.videoPreviewControlIconSize)
          .fillColor(CloudThemeToken.onPrimary)
          .draggable(false)
      } else {
        Image($r('app.media.ic_fullscreen'))
          .width(CloudThemeToken.videoPreviewControlIconSize)
          .height(CloudThemeToken.videoPreviewControlIconSize)
          .fillColor(CloudThemeToken.onPrimary)
          .draggable(false)
      }
    }
    .width(CloudThemeToken.videoPreviewControlSize)
    .height(CloudThemeToken.videoPreviewControlSize)
    .borderRadius(CloudThemeToken.videoPreviewControlSize / CloudThemeToken.halfDivisor)
    .backgroundColor(CloudThemeToken.videoPreviewControlBackground)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .border({
      width: CloudThemeToken.videoPreviewControlBorderWidth,
      color: CloudThemeToken.videoPreviewControlBorder
    })
    .clip(true)
    .onClick(() => {
      this.toggleFullscreen()
    })
  }

  private togglePlayback(): void {
    if (this.videoUrl.length <= CloudThemeToken.zero || this.isFailed || this.isLoading) {
      return
    }
    if (this.isPlaying) {
      this.isPlaying = false
      this.controller.pause()
    } else {
      if (this.currentTime >= this.getSafeDuration()) {
        this.currentTime = CloudThemeToken.zero
        this.controller.setCurrentTime(CloudThemeToken.zero)
      }
      this.isPlaying = true
      this.controller.start()
    }
  }

  private toggleFullscreen(): void {
    this.isFullscreen = !this.isFullscreen
  }

  private onSeek(value: number, mode: SliderChangeMode): void {
    const targetTime = Math.max(CloudThemeToken.zero, Math.min(value, this.getSafeDuration()))
    this.currentTime = targetTime
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.isSeeking = true
      return
    }
    this.isSeeking = false
    this.controller.setCurrentTime(targetTime)
  }

  private getSafeDuration(): number {
    return Math.max(this.duration, 1)
  }

  private formatTime(time: number): string {
    const safeTime = Math.max(CloudThemeToken.zero, Math.floor(time))
    const minutes = Math.floor(safeTime / Constant.SECONDS_PER_MINUTE)
    const seconds = safeTime % Constant.SECONDS_PER_MINUTE
    const secondText = seconds < Constant.DATE_PAD_THRESHOLD ? `0${seconds}` : seconds.toString()
    return `${minutes}:${secondText}`
  }
}
