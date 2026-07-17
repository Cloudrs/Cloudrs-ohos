import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { VideoPreview } from "../model/Params";
import { CloudApi } from "../model/net/CloudApi";
import { CloudRouter } from "../utils/CloudRouter";
import { showToast } from "../utils/ToastUtil";
import AppLogger from "../utils/AppLogger";
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial } from "@kit.UIDesignKit";
import { window } from "@kit.ArkUI";
import { deviceInfo } from "@kit.BasicServicesKit";
import { harmonyShare } from "@kit.ShareKit";
import { KnockShareUtil } from "../utils/KnockShareUtil";
import { KeyCode } from "@kit.InputKit";

const TAG: string = 'VideoPreview'
// 键盘 ←/→ 单次快退/快进秒数(PC/2in1 外接键盘场景)
const KEYBOARD_SEEK_STEP_SECONDS: number = 5
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
  @State controlsVisible: boolean = true
  // 长按快进/快退方向：1 快进、-1 快退、0 未触发
  @State holdSeekDirection: number = 0
  // 横向滑动调节进度中
  @State isSwipeSeeking: boolean = false
  @State playbackRate: number = Constant.VIDEO_NORMAL_PLAY_SPEED
  @State currentTime: number = 0
  @State duration: number = 0
  private fileParam: VideoPreview | null = null
  private controller: VideoController = new VideoController()
  private mainWindow: window.Window | null = null
  // 2in1 为自由窗口形态，不做屏幕方向控制
  private supportsOrientation: boolean = deviceInfo.deviceType !== '2in1'
  private holdSeekTimer: number = -1
  private videoAreaWidth: number = 0
  // 松手/拖动后发起的精确 seek 目标；播放器回报追上之前忽略旧位置，避免进度条回弹
  private pendingSeekTarget: number = -1
  private ignoredUpdateCount: number = 0
  private swipeSeekStartTime: number = 0
  // 长按快退前是否在播放，松手后用于恢复
  private holdWasPlaying: boolean = false

  aboutToAppear(): void {
    if (this.routeParam) {
      this.fileParam = this.routeParam
    }
    this.prepareWindow()
    this.loadVideoUrl()
    harmonyShare.on('knockShare', this.knockShareCallback)
  }

  aboutToDisappear(): void {
    harmonyShare.off('knockShare', this.knockShareCallback)
    this.stopHoldSeek()
    this.setSystemBarsVisible(true)
    this.setOrientation(window.Orientation.UNSPECIFIED)
  }

  private knockShareCallback = (sharableTarget: harmonyShare.SharableTarget): void => {
    this.handleKnockShare(sharableTarget)
  }

  // 分层策略:视频已下载完成则分享文件本体(对端存入图库),否则分享下载直链(对端浏览器在线看/下载)。
  private async handleKnockShare(sharableTarget: harmonyShare.SharableTarget): Promise<void> {
    try {
      const param = this.fileParam
      if (!param) {
        await sharableTarget.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR)
        return
      }
      const localUri = KnockShareUtil.findLocalDownloadUri(param.fileId)
      if (localUri.length > 0) {
        await sharableTarget.share(KnockShareUtil.buildFileShareData(param.fileName, localUri))
        return
      }
      if (KnockShareUtil.useShareLink() && param.sharePath.length > 0) {
        const link = await KnockShareUtil.createOrReuseShareLink(param.fileId, param.sharePath)
        if (link) {
          await sharableTarget.share(KnockShareUtil.buildLinkShareData(param.fileName, link.url, link.password))
          if (link.password.length > 0) {
            showToast(`分享链接提取码：${link.password}`)
          }
          return
        }
        // 创建分享链接失败,回退下载直链
      }
      if (this.videoUrl.length > 0) {
        await sharableTarget.share(KnockShareUtil.buildLinkShareData(param.fileName, this.videoUrl))
        return
      }
      // 直链尚未取到(加载中或失败),及时终止避免对端等待
      await sharableTarget.reject(harmonyShare.SharableErrorCode.DOWNLOAD_ERROR)
    } catch (err) {
      AppLogger.error(TAG, `knock share failed: ${(err as Error)?.message ?? err}`)
    }
  }

  build() {
    HdsNavigation() {
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.videoUrl.length > CloudThemeToken.zero) {
            Video({
              src: this.videoUrl,
              currentProgressRate: this.playbackRate,
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
                // 长按快退期间播放器可能回报结束，不要覆盖回退中的进度
                if (this.holdSeekDirection >= 0) {
                  this.currentTime = this.duration
                }
              })
              .onUpdate((event) => {
                if (this.isSeeking) {
                  return
                }
                if (this.pendingSeekTarget >= CloudThemeToken.zero) {
                  const reachedTarget = Math.abs(event.time - this.pendingSeekTarget) <=
                    Constant.VIDEO_SEEK_SYNC_TOLERANCE_SECONDS
                  if (!reachedTarget && this.ignoredUpdateCount < Constant.VIDEO_SEEK_SYNC_MAX_IGNORED) {
                    this.ignoredUpdateCount++
                    return
                  }
                  this.pendingSeekTarget = -1
                }
                this.currentTime = Math.min(event.time, this.getSafeDuration())
              })
              .onError(() => {
                AppLogger.warn(TAG, 'video play error')
                this.isPlaying = false
                this.isLoading = false
                this.isFailed = true
                showToast('视频播放失败')
              })
              .onClick(() => {
                if (this.isFullscreen) {
                  // 全屏观影时点击屏幕切换控制栏显隐
                  this.controlsVisible = !this.controlsVisible
                } else {
                  this.togglePlayback()
                }
              })
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                this.videoAreaWidth = Number(newArea.width)
              })
              .gesture(
                LongPressGesture()
                  .onAction((event: GestureEvent) => {
                    // 长按右半边快进、左半边快退，松手停止
                    const touchX = event.fingerList[Constant.FIRST_ARRAY_INDEX]?.localX ?? this.videoAreaWidth
                    this.startHoldSeek(touchX < this.videoAreaWidth / CloudThemeToken.halfDivisor ? -1 : 1)
                  })
                  .onActionEnd(() => {
                    this.stopHoldSeek()
                  })
                  .onActionCancel(() => {
                    this.stopHoldSeek()
                  })
              )
              .gesture(
                PanGesture({ direction: PanDirection.Horizontal })
                  .onActionStart(() => {
                    this.startSwipeSeek()
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.updateSwipeSeek(event.offsetX)
                  })
                  .onActionEnd(() => {
                    this.finishSwipeSeek()
                  })
                  .onActionCancel(() => {
                    this.finishSwipeSeek()
                  })
              )
          }

          if (this.holdSeekDirection !== 0 || this.isSwipeSeeking) {
            Text(this.seekHintText())
              .fontSize(CloudThemeToken.textSizeBody)
              .fontColor(CloudThemeToken.onPrimary)
              .padding({
                left: CloudThemeToken.spacingSection,
                right: CloudThemeToken.spacingSection,
                top: CloudThemeToken.spacingXs,
                bottom: CloudThemeToken.spacingXs
              })
              .borderRadius(CloudThemeToken.videoPreviewControlsPanelRadius)
              .backgroundColor(CloudThemeToken.videoPreviewControlsBackground)
              .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
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

        if (this.isFullscreen && this.controlsVisible) {
          this.fullscreenTopBar()
        }

        if (this.videoUrl.length > CloudThemeToken.zero && !this.isFailed &&
          (!this.isFullscreen || this.controlsVisible)) {
          this.videoControls()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(CloudThemeToken.previewBackground)
      // PC/2in1 键盘控制。←/→ 用 keyboardShortcut:不依赖焦点,挂树即响应。
      .keyboardShortcut(FunctionKey.DPAD_LEFT, [], () => {
        this.keyboardSeek(-KEYBOARD_SEEK_STEP_SECONDS)
      })
      .keyboardShortcut(FunctionKey.DPAD_RIGHT, [], () => {
        this.keyboardSeek(KEYBOARD_SEEK_STEP_SECONDS)
      })
      // 空格/F 无法绑定 keyboardShortcut(字符键必须带修饰键),走 onKeyEvent,
      // 依赖焦点:onAppear 后主动抓焦,点击视频区域焦点回到本容器。
      .id('videoKeyRoot')
      .focusable(true)
      .focusOnTouch(true)
      .onKeyEvent((event?: KeyEvent) => {
        this.handleKeyEvent(event)
      })
      .onAppear(() => {
        this.grabKeyFocus()
      })
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideBackButton(false)
    .hideTitleBar(this.isFullscreen)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: this.fileParam?.fileName ?? ''
        },
        backIcon: {
          icon: $r('app.media.ic_back'),
          action: () => {
            CloudRouter.pop()
          }
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
      AppLogger.info(TAG, 'open from cache')
      this.videoUrl = cachedUrl
      return
    }
    AppLogger.info(TAG, 'fetch download uri')
    CloudApi.getDownloadUri(this.fileParam.fileId, {
      onSuccess: (url: string) => {
        const resolvedUrl = (url.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
          url.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) ? url : CloudApi.getBaseURL() + url
        videoDownloadUriCache.set(this.fileParam!.fileId, resolvedUrl)
        this.videoUrl = resolvedUrl
      },
      onFailure: (msg: string) => {
        AppLogger.error(TAG, `Get video download URI failed: ${msg}`)
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
      // 全屏时导航条已隐藏，控制栏贴近屏幕底部
      bottom: this.isFullscreen ? CloudThemeToken.spacingPage : this.bottomRectHeight + CloudThemeToken.spacingPage
    })
    .borderRadius(CloudThemeToken.videoPreviewControlsPanelRadius)
    .backgroundColor(CloudThemeToken.videoPreviewControlsBackground)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .transition(TransitionEffect.OPACITY.animation({ duration: CloudThemeToken.filesHeaderTransitionDuration }))
  }

  @Builder fullscreenTopBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: CloudThemeToken.spacingCard }) {
        this.videoControlButton($r('app.media.ic_back'), CloudThemeToken.videoPreviewCloseIconSize, () => {
          CloudRouter.pop()
        })
        Text(this.fileParam?.fileName ?? '')
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.onPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_ALL)
          // 无背景,浅色画面下靠阴影保证可读
          .textShadow({
            radius: CloudThemeToken.videoPreviewTitleShadowRadius,
            color: CloudThemeToken.videoPreviewTitleShadowColor
          })
          .hitTestBehavior(HitTestMode.None)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .padding({
        left: CloudThemeToken.spacingPage,
        right: CloudThemeToken.spacingPage,
        top: CloudThemeToken.getSafeTopInset(this.sysTopRectHeight) + CloudThemeToken.spacingCard
      })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .transition(TransitionEffect.OPACITY.animation({ duration: CloudThemeToken.filesHeaderTransitionDuration }))
  }

  @Builder playbackButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
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
    Button({ type: ButtonType.Circle, stateEffect: true }) {
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
    this.videoControlButton(this.isFullscreen ? $r('app.media.ic_fullscreen_exit') : $r('app.media.ic_fullscreen'),
      CloudThemeToken.videoPreviewControlIconSize, () => {
      this.toggleFullscreen()
    })
  }

  // 按键事件派发依赖焦点链,页面出现后把焦点主动请求到根容器上(延迟等焦点系统就绪)
  private grabKeyFocus(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('videoKeyRoot')
      } catch (err) {
        AppLogger.warn(TAG, `request key focus failed: ${(err as Error)?.message ?? err}`)
      }
    }, 100)
  }

  private handleKeyEvent(event?: KeyEvent): void {
    if (!event || event.type !== KeyType.Down) {
      return
    }
    switch (event.keyCode) {
      case KeyCode.KEYCODE_SPACE:
      case KeyCode.KEYCODE_MEDIA_PLAY_PAUSE:
        this.togglePlayback()
        break
      case KeyCode.KEYCODE_F:
        this.toggleFullscreen()
        break
      default:
        break
    }
  }

  private keyboardSeek(deltaSeconds: number): void {
    if (this.videoUrl.length <= CloudThemeToken.zero || this.isFailed || this.isLoading) {
      return
    }
    const target = Math.max(CloudThemeToken.zero,
      Math.min(this.currentTime + deltaSeconds, this.getSafeDuration()))
    this.currentTime = target
    this.commitSeek(target)
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
    this.controlsVisible = true
    this.applyFullscreenWindow(this.isFullscreen)
  }

  private prepareWindow(): void {
    const context = this.getUIContext().getHostContext()
    if (!context) {
      return
    }
    window.getLastWindow(context).then((win: window.Window) => {
      this.mainWindow = win
      // 视频播放期间跟随设备翻转自动切换横竖屏（尊重系统旋转锁定）
      this.setOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
    }).catch((err: Error) => {
      AppLogger.warn(TAG, `get last window failed: ${err.message}`)
    })
  }

  private applyFullscreenWindow(active: boolean): void {
    this.setOrientation(active
      ? window.Orientation.AUTO_ROTATION_LANDSCAPE_RESTRICTED
      : window.Orientation.AUTO_ROTATION_RESTRICTED)
    this.setSystemBarsVisible(!active)
  }

  private setOrientation(orientation: window.Orientation): void {
    if (!this.mainWindow || !this.supportsOrientation) {
      return
    }
    this.mainWindow.setPreferredOrientation(orientation).catch((err: Error) => {
      AppLogger.warn(TAG, `setPreferredOrientation failed: ${err.message}`)
    })
  }

  private setSystemBarsVisible(visible: boolean): void {
    const win = this.mainWindow
    if (!win) {
      return
    }
    win.setSpecificSystemBarEnabled('status', visible, true).catch((err: Error) => {
      AppLogger.warn(TAG, `set status bar failed: ${err.message}`)
    })
    win.setSpecificSystemBarEnabled('navigationIndicator', visible, true).catch((err: Error) => {
      AppLogger.warn(TAG, `set navigation indicator failed: ${err.message}`)
    })
  }

  private startHoldSeek(direction: number): void {
    if (this.videoUrl.length <= CloudThemeToken.zero || this.isFailed || this.isLoading ||
      this.holdSeekDirection !== 0) {
      return
    }
    this.holdSeekDirection = direction
    if (direction > 0) {
      // 快进：倍速播放，画面声音真实快进
      if (!this.isPlaying) {
        this.isPlaying = true
        this.controller.start()
      }
      this.playbackRate = Constant.VIDEO_HOLD_FAST_PLAY_SPEED
      return
    }
    // 快退：暂停后逐步精确 seek，画面跟随回退
    this.holdWasPlaying = this.isPlaying
    if (this.isPlaying) {
      this.isPlaying = false
      this.controller.pause()
    }
    this.isSeeking = true
    this.stepHoldSeek()
    this.holdSeekTimer = setInterval(() => {
      this.stepHoldSeek()
    }, Constant.VIDEO_HOLD_SEEK_INTERVAL_MS)
  }

  private stepHoldSeek(): void {
    const target = Math.max(CloudThemeToken.zero,
      this.currentTime - Constant.VIDEO_HOLD_SEEK_STEP_SECONDS)
    this.currentTime = target
    this.controller.setCurrentTime(target, SeekMode.Accurate)
  }

  private stopHoldSeek(): void {
    if (this.holdSeekTimer >= 0) {
      clearInterval(this.holdSeekTimer)
      this.holdSeekTimer = -1
    }
    if (this.holdSeekDirection === 0) {
      return
    }
    const direction = this.holdSeekDirection
    this.holdSeekDirection = 0
    if (direction > 0) {
      // 松手恢复正常倍速继续播放
      this.playbackRate = Constant.VIDEO_NORMAL_PLAY_SPEED
      return
    }
    this.isSeeking = false
    this.commitSeek(this.currentTime)
    if (this.holdWasPlaying) {
      this.isPlaying = true
      this.controller.start()
    }
  }

  private commitSeek(target: number): void {
    this.pendingSeekTarget = target
    this.ignoredUpdateCount = 0
    this.controller.setCurrentTime(target, SeekMode.Accurate)
  }

  private startSwipeSeek(): void {
    if (this.videoUrl.length <= CloudThemeToken.zero || this.isFailed || this.isLoading ||
      this.holdSeekDirection !== 0) {
      return
    }
    this.isSwipeSeeking = true
    this.isSeeking = true
    this.swipeSeekStartTime = this.currentTime
  }

  private updateSwipeSeek(offsetX: number): void {
    if (!this.isSwipeSeeking || this.videoAreaWidth <= CloudThemeToken.zero) {
      return
    }
    // 滑动距离按屏宽比例映射到全片时长：滑满一屏 = 拉动整个视频
    const deltaSeconds = offsetX / this.videoAreaWidth * this.getSafeDuration()
    this.currentTime = Math.max(CloudThemeToken.zero,
      Math.min(this.swipeSeekStartTime + deltaSeconds, this.getSafeDuration()))
  }

  private finishSwipeSeek(): void {
    if (!this.isSwipeSeeking) {
      return
    }
    this.isSwipeSeeking = false
    this.isSeeking = false
    this.commitSeek(this.currentTime)
  }

  private seekHintText(): string {
    if (this.holdSeekDirection > 0) {
      return `${Constant.VIDEO_HOLD_FAST_PLAY_SPEED}x 快进播放中`
    }
    if (this.holdSeekDirection < 0) {
      return `快退 ${this.formatTime(this.currentTime)} / ${this.formatTime(this.duration)}`
    }
    const deltaSeconds = Math.round(this.currentTime - this.swipeSeekStartTime)
    const sign = deltaSeconds >= 0 ? '+' : '-'
    return `${sign}${Math.abs(deltaSeconds)}秒 ${this.formatTime(this.currentTime)} / ${this.formatTime(this.duration)}`
  }

  private onSeek(value: number, mode: SliderChangeMode): void {
    const targetTime = Math.max(CloudThemeToken.zero, Math.min(value, this.getSafeDuration()))
    this.currentTime = targetTime
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.isSeeking = true
      return
    }
    this.isSeeking = false
    this.commitSeek(targetTime)
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
