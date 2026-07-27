import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { VideoPreview } from "../model/Params";
import { CloudApi } from "../model/net/CloudApi";
import UserPreferences from "../model/UserPreferences";
import { CloudRouter } from "../utils/CloudRouter";
import { ContinuationCenter } from "../utils/ContinuationCenter";
import { common } from "@kit.AbilityKit";
import { showApiFailureToast, showToast } from "../utils/ToastUtil";
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
// 等待双击识别完成后再执行 2in1 鼠标单击动作，避免双击先触发暂停
const MOUSE_DOUBLE_CLICK_DELAY_MS: number = 300
const videoDownloadUriCache: Map<string, string> = new Map<string, string>()

@Component
export struct VideoPreviewPage {
  routeParam?: VideoPreview
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @State videoUrl: string = ''
  @State isLoading: boolean = true
  @State isFailed: boolean = false
  // 自动换链重试计数；@State 供加载提示文案显示重试进度
  @State playRetryCount: number = 0
  // 每次挂载新直链递增；播放器异步回调只允许修改对应代次的状态
  @State videoGeneration: number = 0
  // prepare 超时定时器：播放器连不上流时系统要 ~30s 才报错，主动掐短
  private prepareTimeoutTimer: number = -1
  private videoMountAt: number = 0
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
  // 仅当视频全屏主动放大了 PC 窗口时，退出才恢复原来的浮窗尺寸
  private shouldRecoverWindowAfterFullscreen: boolean = false
  // 原本已最大化的窗口退出视频全屏时，只退出沉浸展现，不改变窗口尺寸
  private shouldExitPcImmersiveAfterFullscreen: boolean = false
  private holdSeekTimer: number = -1
  private mouseSingleClickTimer: number = -1
  private lastMouseDoubleClickAt: number = 0
  private videoAreaWidth: number = 0
  // 松手/拖动后发起的精确 seek 目标；播放器回报追上之前忽略旧位置，避免进度条回弹
  private pendingSeekTarget: number = -1
  private ignoredUpdateCount: number = 0
  private swipeSeekStartTime: number = 0
  // 长按快退前是否在播放，松手后用于恢复
  private holdWasPlaying: boolean = false
  // 接续恢复：起播位置(秒)，prepared 后 seek 过去
  private pendingResumeTime: number = 0
  // 接续恢复：源端处于暂停时，起播定位画面后立即暂停
  private pendingPauseAfterStart: boolean = false

  aboutToAppear(): void {
    if (this.routeParam) {
      this.fileParam = this.routeParam
      this.pendingResumeTime = Math.max(this.routeParam.startTime, CloudThemeToken.zero)
      this.pendingPauseAfterStart = !this.routeParam.autoPlay
    }
    this.prepareWindow()
    this.loadVideoUrl()
    this.publishContinuationState()
    harmonyShare.on('knockShare', this.knockShareCallback)
  }

  aboutToDisappear(): void {
    // 离开视频页即撤下接续入口，避免在无内容可接的页面暴露接续图标
    ContinuationCenter.clearVideoState()
    ContinuationCenter.setMissionContinueState(this.abilityContext(), false)
    harmonyShare.off('knockShare', this.knockShareCallback)
    this.stopHoldSeek()
    this.cancelPendingMouseSingleClick()
    this.clearPrepareTimeout()
    // 显式停止播放，立刻掐断流媒体连接释放服务器带宽；
    // 只靠组件卸载让 AVPlayer 异步释放，服务器会继续往半死连接里灌数据
    try {
      this.controller.stop()
    } catch (err) {
      AppLogger.warn(TAG, `stop on disappear failed: ${(err as Error)?.message ?? err}`)
    }
    this.setSystemBarsVisible(true)
    this.applyPcFullscreenWindow(false)
    this.setOrientation(window.Orientation.UNSPECIFIED)
    this.isFullscreen = false
  }

  // 挂载/换链后启动 prepare 看门狗：超时未起播按播放错误处理
  private armPrepareTimeout(): void {
    this.clearPrepareTimeout()
    this.videoMountAt = new Date().getTime()
    const generation = this.videoGeneration
    this.prepareTimeoutTimer = setTimeout(() => {
      if (generation !== this.videoGeneration) {
        return
      }
      this.prepareTimeoutTimer = -1
      AppLogger.warn(TAG, `prepare timeout after ${Constant.VIDEO_PREPARE_TIMEOUT_MS}ms`)
      this.handlePlayError(generation)
    }, Constant.VIDEO_PREPARE_TIMEOUT_MS)
  }

  private clearPrepareTimeout(): void {
    if (this.prepareTimeoutTimer >= 0) {
      clearTimeout(this.prepareTimeoutTimer)
      this.prepareTimeoutTimer = -1
    }
  }

  private abilityContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
  }

  /**
   * 上报可接续状态并放开系统接续入口。
   * 只带 fileId 与账号定位，不带直链 —— 直链是短时效签名地址，
   * 跨设备传过去大概率已失效，对端自行重新获取。
   */
  private publishContinuationState(): void {
    const param = this.fileParam
    if (!param) {
      return
    }
    const userName =
      (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string) ?? ''
    const siteUrl =
      (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string) ?? ''
    ContinuationCenter.setVideoState({
      fileId: param.fileId,
      fileName: param.fileName,
      fileExtension: param.fileExtension,
      sharePath: param.sharePath,
      currentTime: this.currentTime,
      isPlaying: this.isPlaying,
      userName: userName,
      siteUrl: siteUrl
    })
    ContinuationCenter.setMissionContinueState(this.abilityContext(), true)
  }

  /** 播放进度变化时同步给接续中枢，纯内存写 */
  private reportContinuationProgress(): void {
    ContinuationCenter.updateVideoProgress(this.currentTime, this.isPlaying)
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

  @Builder videoPlayer(generation: number) {
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
        if (generation !== this.videoGeneration) {
          return
        }
        this.clearPrepareTimeout()
        AppLogger.info(TAG, `prepared in ${new Date().getTime() - this.videoMountAt}ms`)
        this.duration = Math.max(event.duration, CloudThemeToken.zero)
        this.isLoading = false
        // 接续恢复：先定位再起播，画面直接落在源端的进度上
        if (this.pendingResumeTime > CloudThemeToken.zero) {
          this.currentTime = Math.min(this.pendingResumeTime, this.getSafeDuration())
          this.pendingResumeTime = 0
          this.commitSeek(this.currentTime)
        }
        this.isPlaying = true
        this.controller.start()
      })
      .onStart(() => {
        if (generation !== this.videoGeneration) {
          return
        }
        this.clearPrepareTimeout()
        this.isPlaying = true
        this.isLoading = false
        // 源端接续过来时是暂停态：定位画面后立刻停住
        if (this.pendingPauseAfterStart) {
          this.pendingPauseAfterStart = false
          this.isPlaying = false
          this.controller.pause()
        }
        this.reportContinuationProgress()
      })
      .onPause(() => {
        this.isPlaying = false
        this.reportContinuationProgress()
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
        this.reportContinuationProgress()
      })
      .onError(() => {
        this.handlePlayError(generation)
      })
      .onClick((event: ClickEvent) => {
        this.handleVideoClick(event)
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

  build() {
    HdsNavigation() {
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.videoUrl.length > CloudThemeToken.zero) {
            this.videoPlayer(this.videoGeneration)
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
              Text(this.loadingHintText())
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
              Button('重试')
                .fontSize(CloudThemeToken.textSizeBody)
                .fontColor(CloudThemeToken.onPrimary)
                .backgroundColor(CloudThemeToken.primary)
                .onClick(() => {
                  this.playRetryCount = 0
                  this.videoUrl = ''
                  this.loadVideoUrl(true)
                })
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

  private loadVideoUrl(forceRefresh: boolean = false): void {
    if (!this.fileParam) {
      this.isLoading = false
      this.isFailed = true
      return
    }

    this.isLoading = true
    this.isFailed = false
    if (forceRefresh) {
      // 直链是短时效签名链接，播放失败大概率是缓存的旧链过期，强制换新链
      videoDownloadUriCache.delete(this.fileParam.fileId)
    } else {
      const cachedUrl = videoDownloadUriCache.get(this.fileParam.fileId)
      if (cachedUrl && cachedUrl.length > CloudThemeToken.zero) {
        AppLogger.info(TAG, `open from cache, host=${this.extractHost(cachedUrl)}`)
        this.mountVideoUrl(cachedUrl)
        return
      }
    }
    AppLogger.info(TAG, 'fetch download uri')
    CloudApi.getDownloadUri(this.fileParam.fileId, {
      onSuccess: (url: string) => {
        const resolvedUrl = (url.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
          url.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) ? url : CloudApi.getBaseURL() + url
        videoDownloadUriCache.set(this.fileParam!.fileId, resolvedUrl)
        AppLogger.info(TAG, `got download uri, host=${this.extractHost(resolvedUrl)}`)
        this.mountVideoUrl(resolvedUrl)
      },
      onFailure: (msg: string) => {
        AppLogger.error(TAG, `Get video download URI failed: ${msg}`)
        this.isLoading = false
        this.isFailed = true
        showApiFailureToast(msg, '获取视频地址失败')
      }
    })
  }

  private mountVideoUrl(url: string): void {
    this.videoGeneration++
    this.videoUrl = url
    this.armPrepareTimeout()
  }

  // 播放出错/prepare 超时：先自动换新直链重试，重试次数用完才落到失败态
  private handlePlayError(generation: number): void {
    if (generation !== this.videoGeneration) {
      AppLogger.info(TAG, `ignore stale video callback, generation=${generation}, active=${this.videoGeneration}`)
      return
    }
    this.clearPrepareTimeout()
    this.isPlaying = false
    if (this.isFailed) {
      return
    }
    // 已在换链取新地址的路上（Video 已卸载），忽略旧实例迟到的错误回调
    if (this.videoUrl.length === 0 && this.isLoading) {
      return
    }
    const elapsed = this.videoMountAt > 0 ? new Date().getTime() - this.videoMountAt : -1
    if (this.playRetryCount < Constant.VIDEO_PLAY_MAX_AUTO_RETRY) {
      this.playRetryCount++
      AppLogger.warn(TAG, `video play error after ${elapsed}ms, auto retry ${this.playRetryCount}`)
      this.videoUrl = ''
      this.loadVideoUrl(true)
    } else {
      AppLogger.warn(TAG, `video play error after ${elapsed}ms, retries exhausted`)
      this.isLoading = false
      this.isFailed = true
      showToast('视频播放失败')
    }
  }

  // 只取 host 供日志定位，不落带签名参数的完整直链
  private extractHost(url: string): string {
    const parts = url.split('/')
    return parts.length > 2 ? parts[2] : url.substring(0, Math.min(url.length, 32))
  }

  private loadingHintText(): string {
    return this.playRetryCount > 0
      ? `加载失败，自动重试中 (${this.playRetryCount}/${Constant.VIDEO_PLAY_MAX_AUTO_RETRY})`
      : '正在打开视频'
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
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(this.isFullscreen
        ? $r('sys.symbol.arrow_down_right_and_arrow_up_left')
        : $r('sys.symbol.arrow_up_left_and_arrow_down_right'))
        .fontSize(CloudThemeToken.videoPreviewControlIconSize)
        .fontColor([CloudThemeToken.onPrimary])
        .fontWeight(FontWeight.Medium)
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

  private handleVideoClick(event: ClickEvent): void {
    const isPcMouseClick = !this.supportsOrientation && event.source === SourceType.Mouse
    if (!isPcMouseClick) {
      this.handleVideoSingleClick()
      return
    }
    const clickAt = new Date().getTime()
    // 屏蔽系统在已判定双击后可能补发的尾随 click。
    if (clickAt - this.lastMouseDoubleClickAt <= MOUSE_DOUBLE_CLICK_DELAY_MS) {
      return
    }
    if (this.mouseSingleClickTimer >= 0) {
      this.cancelPendingMouseSingleClick()
      this.lastMouseDoubleClickAt = clickAt
      this.toggleFullscreen()
      return
    }
    this.mouseSingleClickTimer = setTimeout(() => {
      this.mouseSingleClickTimer = -1
      this.handleVideoSingleClick()
    }, MOUSE_DOUBLE_CLICK_DELAY_MS)
  }

  private handleVideoSingleClick(): void {
    if (this.isFullscreen) {
      // 全屏观影时点击屏幕切换控制栏显隐
      this.controlsVisible = !this.controlsVisible
    } else {
      this.togglePlayback()
    }
  }

  private cancelPendingMouseSingleClick(): void {
    if (this.mouseSingleClickTimer >= 0) {
      clearTimeout(this.mouseSingleClickTimer)
      this.mouseSingleClickTimer = -1
    }
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
      // 窗口异步获取期间用户可能已点击全屏，补做一次窗口状态同步
      if (this.isFullscreen) {
        this.applyFullscreenWindow(true)
      }
    }).catch((err: Error) => {
      AppLogger.warn(TAG, `get last window failed: ${err.message}`)
    })
  }

  private applyFullscreenWindow(active: boolean): void {
    this.setOrientation(active
      ? window.Orientation.AUTO_ROTATION_LANDSCAPE_RESTRICTED
      : window.Orientation.AUTO_ROTATION_RESTRICTED)
    this.setSystemBarsVisible(!active)
    this.applyPcFullscreenWindow(active)
  }

  private applyPcFullscreenWindow(active: boolean): void {
    const win = this.mainWindow
    if (!win || this.supportsOrientation) {
      return
    }
    if (active) {
      // 避免重复的全屏同步把“原始为浮窗”误判成“原始已最大化”
      if (this.shouldRecoverWindowAfterFullscreen || this.shouldExitPcImmersiveAfterFullscreen) {
        return
      }
      try {
        const status = win.getWindowStatus()
        if (status === window.WindowStatusType.FULL_SCREEN) {
          return
        }
        this.shouldRecoverWindowAfterFullscreen = status !== window.WindowStatusType.MAXIMIZE
        this.shouldExitPcImmersiveAfterFullscreen = status === window.WindowStatusType.MAXIMIZE
      } catch (err) {
        this.shouldRecoverWindowAfterFullscreen = false
        this.shouldExitPcImmersiveAfterFullscreen = false
        AppLogger.warn(TAG, `get window status failed: ${(err as Error)?.message ?? err}`)
      }
      win.maximize(window.MaximizePresentation.ENTER_IMMERSIVE_DISABLE_TITLE_AND_DOCK_HOVER).catch((err: Error) => {
        this.shouldRecoverWindowAfterFullscreen = false
        this.shouldExitPcImmersiveAfterFullscreen = false
        AppLogger.warn(TAG, `maximize video window failed: ${err.message}`)
      })
      return
    }
    if (this.shouldRecoverWindowAfterFullscreen) {
      this.shouldRecoverWindowAfterFullscreen = false
      win.recover().catch((err: Error) => {
        AppLogger.warn(TAG, `recover video window failed: ${err.message}`)
      })
      return
    }
    if (this.shouldExitPcImmersiveAfterFullscreen) {
      this.shouldExitPcImmersiveAfterFullscreen = false
      win.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).catch((err: Error) => {
        AppLogger.warn(TAG, `exit video immersive window failed: ${err.message}`)
      })
    }
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
