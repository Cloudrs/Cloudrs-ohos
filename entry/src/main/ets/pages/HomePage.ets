import Constant from '../model/Constant';
import { TabFiles } from './tabs/TabFiles';
import { TabPictures } from './tabs/TabPictures';
import { TabRemoteDown } from './tabs/TabAria2';
import { TabMine } from './tabs/TabMine';
import { CloudBreakpoint, CloudThemeToken } from '../model/CloudTheme';
import { BreakpointType } from '../utils/BreakpointType';
import { TabId, TabItem, TabList } from '../model/TabData';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { CloudRouter } from '../utils/CloudRouter';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { AppLockUtil } from '../utils/AppLockUtil';
import { showToast } from '../utils/ToastUtil';
import AppLogger from '../utils/AppLogger';

const HOME_TAB_NAMES: Record<number, string> = { 0: 'files', 1: 'pictures', 2: 'remoteDown', 3: 'mine' };

@Component
export struct HomePage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidth: number = 0;
  @Watch('onForegroundTickChanged')
  @StorageProp(Constant.APP_FOREGROUND_TICK) foregroundTick: number = 0;
  @StorageProp(Constant.APP_LOCKED) appLocked: boolean = false
  @State currentIndex: number = TabId.FILES;
  @State overLap: boolean = true
  @State appLockChecking: boolean = false
  @State appLockError: string = ''
  @State preloadMineIconsEnabled: boolean = false
  @State showSideBar: boolean = true
  private appLockVerifyTimer: number = -1

  aboutToAppear(): void {
    AppStorage.set(Constant.TAB_BAR_HEIGHT, CloudThemeToken.tabBarHeight)
    AppStorage.setOrCreate(Constant.SIDEBAR_VISIBLE, this.showSideBar)
    CloudRouter.setHomeBackEnabled(this.currentIndex === TabId.FILES)
    this.scheduleVerifyAppLock()
    setTimeout(() => {
      this.preloadMineIconsEnabled = true
    }, CloudThemeToken.defaultAnimationDuration * 18)
  }

  private onForegroundTickChanged(): void {
    this.scheduleVerifyAppLock()
  }

  aboutToDisappear(): void {
    if (this.appLockVerifyTimer >= 0) {
      clearTimeout(this.appLockVerifyTimer)
      this.appLockVerifyTimer = -1
    }
  }

  private scheduleVerifyAppLock(): void {
    if (this.appLockVerifyTimer >= 0) {
      clearTimeout(this.appLockVerifyTimer)
    }
    this.appLockVerifyTimer = setTimeout(() => {
      this.appLockVerifyTimer = -1
      this.verifyAppLock()
    }, CloudThemeToken.spacingCard)
  }

  private verifyAppLock(): void {
    if (this.appLockChecking) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (!context) {
      return
    }
    this.appLockError = ''
    this.appLockChecking = true
    AppLockUtil.unlockIfNeeded(context)
      .then((result) => {
        this.appLockChecking = false
        if (result.success) {
          this.appLockError = ''
          return
        }
        this.appLockError = result.message.length > 0 ? result.message : '身份验证失败'
        showToast(this.appLockError)
      })
      .catch((err: Error) => {
        this.appLockChecking = false
        AppLogger.error('HomePage', `app lock failed: ${err.message}`)
        this.appLockError = err.message.length > 0 ? err.message : '身份验证失败'
        showToast(this.appLockError)
      })
  }

  private getTabBarStyle(tab: TabItem): BottomTabBarStyle {
    return BottomTabBarStyle.of(tab.image, tab.text)
      .verticalAlign(VerticalAlign.Center)
      .layoutMode(LayoutMode.VERTICAL)
      .padding(CloudThemeToken.bottomTabBarItemPadding)
      .labelStyle({
        font: { size: CloudThemeToken.textSizeSmall },
        selectedColor: CloudThemeToken.primary,
        unselectedColor: CloudThemeToken.textSecondary
      })
      .iconStyle({
        selectedColor: CloudThemeToken.primary,
        unselectedColor: CloudThemeToken.textSecondary
      })
  }

  private switchTab(index: number): void {
    if (index === this.currentIndex) {
      return
    }
    const prev = this.currentIndex
    this.currentIndex = index
    CloudRouter.setHomeBackEnabled(index === TabId.FILES)
    AppLogger.info('HomePage', `tab change ${HOME_TAB_NAMES[prev] ?? prev} -> ${HOME_TAB_NAMES[index] ?? index}`)
  }

  private currentBreakpoint(): CloudBreakpoint {
    return CloudThemeToken.getBreakpoint(this.windowWidth)
  }

  build() {
    Stack() {
      if (CloudThemeToken.isWideBreakpoint(this.currentBreakpoint())) {
        this.wideLayout()
      } else {
        this.phoneLayout()
      }

      if (this.preloadMineIconsEnabled) {
        this.preloadMineIcons()
      }

      if (this.appLocked) {
        this.appLockOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder phoneLayout() {
    HdsTabs({ index: this.currentIndex }) {
      TabContent() {
        TabFiles({ overLap: this.overLap, isActive: this.currentIndex === TabId.FILES })
      }
      .tabBar(this.getTabBarStyle(TabList[TabId.FILES]))
      .tabIndex(TabId.FILES)

      TabContent() {
        TabPictures({ overLap: this.overLap, isActive: this.currentIndex === TabId.PICTURES })
      }
      .tabBar(this.getTabBarStyle(TabList[TabId.PICTURES]))
      .tabIndex(TabId.PICTURES)

      TabContent() {
        TabRemoteDown({ overLap: this.overLap, isActive: this.currentIndex === TabId.REMOTE_DOWN })
      }
      .tabBar(this.getTabBarStyle(TabList[TabId.REMOTE_DOWN]))
      .tabIndex(TabId.REMOTE_DOWN)

      TabContent() {
        TabMine({ overLap: this.overLap, isActive: this.currentIndex === TabId.MINE })
      }
      .tabBar(this.getTabBarStyle(TabList[TabId.MINE]))
      .tabIndex(TabId.MINE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
    .foregroundBlurStyle(this.appLocked ? BlurStyle.Thin : BlurStyle.NONE, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT
    })
    .barOverlap(true)
    .barBackgroundColor(CloudThemeToken.transparent)
    .barBackgroundBlurStyle(CloudThemeToken.hdsTabBarBlurStyle)
    .barPosition(BarPosition.End)
    .barFloatingStyle({
      barBottomMargin: this.overLap ? this.bottomRectHeight + CloudThemeToken.hdsTabBarBottomMargin :
      CloudThemeToken.hiddenTabBarBottomMargin,
      lightColor: CloudThemeToken.hdsTabBarLightColor,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .vertical(false)
    .barMode(BarMode.Fixed)
    .animationDuration(CloudThemeToken.defaultAnimationDuration)
    .onChange((index: number) => {
      this.switchTab(index)
      return true
    })
  }

  private currentSideBarWidth(): number {
    return new BreakpointType<number>(0, 0,
      CloudThemeToken.sideNavWidthLg, CloudThemeToken.sideNavWidthXl).getValue(this.currentBreakpoint())
  }

  // 控制按钮 top：避开状态栏区。
  // 2in1 装饰条已隐藏 topRectHeight=0；
  // 平板/折叠屏 setWindowLayoutFullScreen 后 topRectHeight 是 status bar 高度，给个保底（~28vp）防它没生效。
  // 偏移取 spacingCard 让按钮垂直中心与标题栏的返回/菜单按钮一致（实测中心线对齐）
  private controlButtonTop(): number {
    if (deviceInfo.deviceType === '2in1') {
      return this.topRectHeight + CloudThemeToken.spacingCard
    }
    return Math.max(this.topRectHeight, CloudThemeToken.statusBarFallbackHeight) + CloudThemeToken.spacingCard
  }

  @Builder wideLayout() {
    Stack({ alignContent: Alignment.TopStart }) {
      SideBarContainer(SideBarContainerType.Embed) {
        this.sideBarContent()
        this.mainTabsContent()
      }
      .showControlButton(false)
      .showSideBar(this.showSideBar)
      .onChange((value: boolean) => {
        this.getUIContext().animateTo({
          duration: CloudThemeToken.defaultAnimationDuration,
          curve: Curve.EaseInOut
        }, () => {
          this.showSideBar = value
          AppStorage.setOrCreate(Constant.SIDEBAR_VISIBLE, value)
        })
      })
      .autoHide(false)
      .sideBarWidth(this.currentSideBarWidth())
      .minSideBarWidth(this.currentSideBarWidth())
      .maxSideBarWidth(this.currentSideBarWidth())
      .divider({
        strokeWidth: CloudThemeToken.hairlinePx,
        color: CloudThemeToken.line
      })
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.background)
      .foregroundBlurStyle(this.appLocked ? BlurStyle.Thin : BlurStyle.NONE, {
        colorMode: ThemeColorMode.SYSTEM,
        adaptiveColor: AdaptiveColor.DEFAULT
      })

      // 自定义折叠按钮（圆角浅灰背景由 Button 自带）
      this.sideBarToggleButton()
    }
    .width('100%')
    .height('100%')
  }

  @Builder sideBarToggleButton() {
    Button({ type: ButtonType.Normal }) {
      Image(this.showSideBar ?
        $r('app.media.ic_sidebar_close') : $r('app.media.ic_sidebar_open'))
        .width(CloudThemeToken.sideBarToggleIconSize)
        .height(CloudThemeToken.sideBarToggleIconSize)
        .fillColor(CloudThemeToken.textPrimary)
        .draggable(false)
    }
    .width(CloudThemeToken.sideBarToggleSize)
    .height(CloudThemeToken.sideBarToggleSize)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
    .borderRadius(CloudThemeToken.actionRadiusForWidth(this.windowWidth, CloudThemeToken.sideBarToggleRadius))
    .padding(0)
    .margin({
      left: CloudThemeToken.spacingCard,
      top: this.controlButtonTop()
    })
    .onClick(() => {
      this.getUIContext().animateTo({
        duration: CloudThemeToken.defaultAnimationDuration,
        curve: Curve.EaseInOut
      }, () => {
        this.showSideBar = !this.showSideBar
        AppStorage.setOrCreate(Constant.SIDEBAR_VISIBLE, this.showSideBar)
      })
    })
  }

  @Builder sideBarContent() {
    Column({ space: CloudThemeToken.sideNavGap }) {
      ForEach(TabList, (tab: TabItem) => {
        this.sideNavItem(tab)
      }, (tab: TabItem) => `sideNav-${tab.tabId}`)
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.controlButtonTop() + CloudThemeToken.sideBarToggleSize + CloudThemeToken.spacingCard,
      bottom: this.bottomRectHeight + CloudThemeToken.sideNavVerticalPadding,
      left: CloudThemeToken.sideNavHorizontalPadding,
      right: CloudThemeToken.sideNavHorizontalPadding
    })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder sideNavItem(tab: TabItem) {
    if (this.currentBreakpoint() === CloudBreakpoint.XL) {
      Row({ space: CloudThemeToken.spacingSection }) {
        Image(tab.image)
          .width(CloudThemeToken.iconBoxSm)
          .height(CloudThemeToken.iconBoxSm)
          .fillColor(this.currentIndex === tab.tabId ?
            CloudThemeToken.primary : CloudThemeToken.textSecondary)
          .draggable(false)
        Text(tab.text)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(this.currentIndex === tab.tabId ?
            CloudThemeToken.primary : CloudThemeToken.textPrimary)
          .fontWeight(this.currentIndex === tab.tabId ? FontWeight.Medium : FontWeight.Regular)
          .layoutWeight(1)
      }
      .width('100%')
      .height(CloudThemeToken.sideNavItemHeight)
      .padding({
        left: CloudThemeToken.spacingPage,
        right: CloudThemeToken.spacingPage
      })
      .borderRadius(CloudThemeToken.sideNavItemRadius)
      .backgroundColor(this.currentIndex === tab.tabId ?
        CloudThemeToken.primarySoft : CloudThemeToken.transparent)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.switchTab(tab.tabId)
      })
    } else {
      Column({ space: CloudThemeToken.spacingXs }) {
        Image(tab.image)
          .width(CloudThemeToken.iconBoxSm)
          .height(CloudThemeToken.iconBoxSm)
          .fillColor(this.currentIndex === tab.tabId ?
            CloudThemeToken.primary : CloudThemeToken.textSecondary)
          .draggable(false)
        Text(tab.text)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(this.currentIndex === tab.tabId ?
            CloudThemeToken.primary : CloudThemeToken.textSecondary)
          .fontWeight(this.currentIndex === tab.tabId ? FontWeight.Medium : FontWeight.Regular)
          .maxLines(1)
      }
      .width('100%')
      .height(CloudThemeToken.sideNavItemHeight)
      .borderRadius(CloudThemeToken.sideNavItemRadius)
      .backgroundColor(this.currentIndex === tab.tabId ?
        CloudThemeToken.primarySoft : CloudThemeToken.transparent)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.switchTab(tab.tabId)
      })
    }
  }

  @Builder mainTabsContent() {
    Stack() {
      if (this.currentIndex === TabId.FILES) {
        TabFiles({ overLap: this.overLap, isActive: true })
      } else if (this.currentIndex === TabId.PICTURES) {
        TabPictures({ overLap: this.overLap, isActive: true })
      } else if (this.currentIndex === TabId.REMOTE_DOWN) {
        TabRemoteDown({ overLap: this.overLap, isActive: true })
      } else if (this.currentIndex === TabId.MINE) {
        TabMine({ overLap: this.overLap, isActive: true })
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder appLockOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(245, 248, 252, 0.62)')
        .foregroundBlurStyle(BlurStyle.Thin, {
          colorMode: ThemeColorMode.SYSTEM,
          adaptiveColor: AdaptiveColor.DEFAULT,
          scale: CloudThemeToken.fullOpacity
        })

      Column({ space: CloudThemeToken.spacingSection }) {
        Image($r('app.media.ic_privacy_secure'))
          .width(CloudThemeToken.iconBox2xl)
          .height(CloudThemeToken.iconBox2xl)
          .padding(CloudThemeToken.spacingCard)
          .fillColor(CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.primarySoft)
          .borderRadius(CloudThemeToken.controlRadiusRoundXl)
          .draggable(false)

        Text('已开启系统认证保护')
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)

        Text(this.appLockChecking ? '正在等待系统认证' :
          (this.appLockError.length > 0 ? this.appLockError : '隐私保护中'))
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(2)
          .textAlign(TextAlign.Center)

        if (this.appLockError.length > 0) {
          Button('重试')
            .height(CloudThemeToken.rowHeightLg)
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.onPrimary)
            .backgroundColor(CloudThemeToken.primary)
            .borderRadius(CloudThemeToken.controlRadiusRoundMd)
            .enabled(!this.appLockChecking)
            .onClick(() => {
              this.verifyAppLock()
            })
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding(CloudThemeToken.spacingPage)
    }
    .width('100%')
    .height('100%')
    .zIndex(CloudThemeToken.overlayZIndex + 10)
    .transition(TransitionEffect.OPACITY.animation({
      duration: CloudThemeToken.defaultAnimationDuration,
      curve: Curve.EaseOut
    }))
  }

  @Builder preloadMineIcons() {
    Row() {
      this.preloadIcon($r('app.media.ic_externaldrive_fill'))
      this.preloadIcon($r('app.media.ic_square_logout'))
      this.preloadIcon($r('app.media.ic_privacy_secure'))
      this.preloadIcon($r('app.media.ic_theme_setting'))
      this.preloadIcon($r('app.media.ic_more_setting'))
      this.preloadIcon($r('app.media.ic_info_circle'))
      this.preloadIcon($r('app.media.ic_chevron_right'))
      this.preloadIcon($r('app.media.ic_feedback'))
      this.preloadIcon($r('app.media.ic_web_jump'))
    }
    .width(1)
    .height(1)
    .opacity(0)
    .enabled(false)
    .position({ x: -CloudThemeToken.iconBoxLg, y: -CloudThemeToken.iconBoxLg })
  }

  @Builder preloadIcon(icon: ResourceStr) {
    Image(icon)
      .width(1)
      .height(1)
      .draggable(false)
  }
}
