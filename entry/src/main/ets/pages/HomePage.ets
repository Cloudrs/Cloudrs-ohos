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
import { deviceInfo, SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit';
import { CloudMaterial } from '../model/CloudMaterial';
import { AppLockUtil } from '../utils/AppLockUtil';
import { showToast } from '../utils/ToastUtil';
import AppLogger from '../utils/AppLogger';
import { TitleControlButton } from '../components/TitleControlButton';
import { WindowMover } from '../utils/WindowMover';
import UserPreferences from '../model/UserPreferences';
import UserDatabase from '../model/UserDatabase';
import { DbUserInfo } from '../model/net/ApiTypes';
import { AccountAvatar } from '../components/AccountAvatar';
import { UserSwitchSheet } from '../components/UserSwitchSheet';

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
  // 侧栏底部账号卡片：切账号后按 scope 变化重读
  @Watch('loadAccountCard')
  @StorageProp(Constant.ACTIVE_ACCOUNT_SCOPE) accountScope: string = ''
  @State accountInfo: DbUserInfo | null = null
  @State showAccountSheet: boolean = false
  private accountUser: string = ''
  private accountUrl: string = ''
  private appLockVerifyTimer: number = -1

  aboutToAppear(): void {
    AppStorage.set(Constant.TAB_BAR_HEIGHT, CloudThemeToken.tabBarHeight)
    AppStorage.setOrCreate(Constant.SIDEBAR_VISIBLE, this.showSideBar)
    this.loadAccountCard()
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
      // 未选中用正文黑（参考 IT之家 风格，细描边图标配黑色更利落），选中主色
      .labelStyle({
        font: { size: CloudThemeToken.textSizeSmall },
        selectedColor: CloudThemeToken.primary,
        unselectedColor: CloudThemeToken.textPrimary
      })
      .iconStyle({
        selectedColor: CloudThemeToken.primary,
        unselectedColor: CloudThemeToken.textPrimary
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

  private loadAccountCard(): void {
    this.accountUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string
    this.accountUrl = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string
    this.accountInfo = this.accountUser.length > 0 ? UserDatabase.getUserInfo(this.accountUser, this.accountUrl) : null
  }

  private accountHost(): string {
    return this.accountUrl.replace(/^https?:\/\//, '').replace(/\/+$/, '')
  }

  // 折叠键：XL 展开时收进侧栏顶行右端，LG 展开时居中于图标栏顶部，收起时停在内容区左上角
  private sideBarToggleLeft(): number {
    if (!this.showSideBar) {
      return CloudThemeToken.spacingCard
    }
    const width = this.currentSideBarWidth()
    if (this.currentBreakpoint() === CloudBreakpoint.XL) {
      return width - CloudThemeToken.spacingCard - CloudThemeToken.sideBarToggleSize
    }
    return (width - CloudThemeToken.sideBarToggleSize) / CloudThemeToken.halfDivisor
  }

  private sideBarToggleTop(): number {
    if (deviceInfo.deviceType === '2in1') {
      // 系统标题栏已隐藏，顶行与窗口三键区同高（rowHeight5xl），折叠键在其中垂直居中
      return (CloudThemeToken.rowHeight5xl - CloudThemeToken.sideBarToggleSize) / CloudThemeToken.halfDivisor
    }
    // 上移一点，与 HDS 标题栏返回键垂直居中对齐（两者分属不同布局系统，实测偏低约 3vp）
    return this.controlButtonTop() - CloudThemeToken.spacingTiny
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

  @SuppressWarnings({ rules: [SuppressWarningsType.COMPATIBILITY] })
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

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAccountSheet, this.accountSwitchSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          title: { title: '选择账号' },
          showClose: true,
          backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
          systemMaterial: CloudMaterial.sheetMaterial(),
          preferType: CloudThemeToken.sheetTypeForWidth(this.windowWidth),
          width: CloudThemeToken.sheetWidthForWidth(this.windowWidth)
        })
    }
    .width('100%')
    .height('100%')
  }

  // 折叠键与文件页 HDS 返回键并排：同用 TitleControlButton，底色、光感与菜单键一致。
  // 展开/收起同一个侧栏面板图标，靠按钮位置区分
  @Builder sideBarToggleButton() {
    Column() {
      TitleControlButton({
        icon: $r('app.media.ic_sidebar_panel'),
        label: this.showSideBar ? '收起侧栏' : '展开侧栏',
        onAction: () => {
          this.getUIContext().animateTo({
            duration: CloudThemeToken.defaultAnimationDuration,
            curve: Curve.EaseInOut
          }, () => {
            this.showSideBar = !this.showSideBar
            AppStorage.setOrCreate(Constant.SIDEBAR_VISIBLE, this.showSideBar)
          })
        }
      })
    }
    .margin({
      left: this.sideBarToggleLeft(),
      top: this.sideBarToggleTop()
    })
  }

  // 侧栏与内容区同用应用背景色（同色统一），仅靠 SideBarContainer 分隔线与选中高亮区分。
  // XL 为原生风侧栏；LG 为图标栏（Rail）
  @Builder sideBarContent() {
    if (this.currentBreakpoint() === CloudBreakpoint.XL) {
      this.sideBarContentXl()
    } else {
      this.sideBarContentRail()
    }
  }

  // 参照系统「文件管理」：顶行品牌（兼窗口拖动区，折叠键浮在其右端）、分组小标题、紧凑导航行、底部账号卡片
  @Builder sideBarContentXl() {
    Column() {
      Row({ space: CloudThemeToken.spacingCard }) {
        Image($r('app.media.cloudrs'))
          .width(CloudThemeToken.sideNavLogoSize)
          .height(CloudThemeToken.sideNavLogoSize)
          .borderRadius(CloudThemeToken.controlRadiusSm)
          .draggable(false)
        Text('Cloudrs')
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight5xl)
      .padding({
        left: CloudThemeToken.spacingSection,
        right: CloudThemeToken.spacingCard + CloudThemeToken.sideBarToggleSize
      })
      // 隐藏系统标题栏后由这行承担窗口拖动（折叠键是浮层，不在此行内，不会误触发）
      .onTouch((event: TouchEvent) => {
        WindowMover.onTouch(event)
      })

      Text('浏览')
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
        .padding({
          left: CloudThemeToken.spacingSection,
          top: CloudThemeToken.spacingXs,
          bottom: CloudThemeToken.spacingSm
        })

      Column({ space: CloudThemeToken.sideNavRowGap }) {
        ForEach(TabList, (tab: TabItem) => {
          this.sideNavItem(tab)
        }, (tab: TabItem) => `sideNav-${tab.tabId}`)
      }
      .width('100%')

      Blank()

      this.sideAccountCard()
    }
    .width('100%')
    .height('100%')
    .padding({
      left: CloudThemeToken.spacingCard,
      right: CloudThemeToken.spacingCard,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingCard
    })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(CloudThemeToken.background)
  }

  // 当前账号：头像 + 昵称 + 站点，点击弹出账号切换
  @Builder sideAccountCard() {
    Row({ space: CloudThemeToken.spacingCard }) {
      if (this.accountInfo) {
        AccountAvatar({
          baseUrl: this.accountInfo.url,
          userId: this.accountInfo.userinfo.id,
          avatar: this.accountInfo.userinfo.avatar,
          cookie: this.accountInfo.cookie,
          refreshToken: this.accountInfo.refresh_token,
          username: this.accountInfo.username,
          avatarSize: CloudThemeToken.iconBoxXs,
          radius: CloudThemeToken.iconBoxXs / CloudThemeToken.halfDivisor
        })
      }
      Column({ space: CloudThemeToken.spacingTiny }) {
        Text(this.accountInfo?.userinfo.nickname || this.accountUser)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.accountHost())
          .fontSize(CloudThemeToken.textSizeMicro)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(CloudThemeToken.iconMd)
        .fontColor([CloudThemeToken.textSecondary])
    }
    .width('100%')
    .padding(CloudThemeToken.spacingCard)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .alignItems(VerticalAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .accessibilityText('切换账号')
    .onClick(() => {
      this.loadAccountCard()
      this.showAccountSheet = true
    })
  }

  @Builder accountSwitchSheet() {
    UserSwitchSheet({
      currentUser: this.accountUser,
      currentUrl: this.accountUrl,
      onSelect: (user: DbUserInfo) => {
        // 过期账号会跳登录页，得先把 sheet 关掉再跳
        if (CloudRouter.switchToUser(user.username, user.url, () => { this.showAccountSheet = false })) {
          this.showAccountSheet = false
          this.loadAccountCard()
        }
      },
      onClose: () => {
        this.showAccountSheet = false
      }
    })
  }

  @Builder sideBarContentRail() {
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
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder sideNavItem(tab: TabItem) {
    if (this.currentBreakpoint() === CloudBreakpoint.XL) {
      Row({ space: CloudThemeToken.spacingCard }) {
        // 细描边图标自带约 3vp 内缩，24 的框里字形约 20，与紧凑行 14 号字匀称
        Image(tab.image)
          .width(CloudThemeToken.icon3xl)
          .height(CloudThemeToken.icon3xl)
          .fillColor(this.currentIndex === tab.tabId ?
            CloudThemeToken.primary : CloudThemeToken.textPrimary)
          .draggable(false)
        Text(tab.text)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(this.currentIndex === tab.tabId ?
            CloudThemeToken.primary : CloudThemeToken.textPrimary)
          .fontWeight(this.currentIndex === tab.tabId ? FontWeight.Medium : FontWeight.Regular)
          .layoutWeight(1)
      }
      .width('100%')
      .height(CloudThemeToken.sideNavRowHeight)
      .padding({
        left: CloudThemeToken.spacingSection,
        right: CloudThemeToken.spacingSection
      })
      .borderRadius(CloudThemeToken.sideNavRowRadius)
      .backgroundColor(this.currentIndex === tab.tabId ?
        CloudThemeToken.primarySoft : CloudThemeToken.transparent)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.switchTab(tab.tabId)
      })
    } else {
      Column({ space: CloudThemeToken.spacingXs }) {
        Image(tab.image)
          .width(CloudThemeToken.icon4xl)
          .height(CloudThemeToken.icon4xl)
          .fillColor(this.currentIndex === tab.tabId ?
            CloudThemeToken.primary : CloudThemeToken.textPrimary)
          .draggable(false)
        Text(tab.text)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(this.currentIndex === tab.tabId ?
            CloudThemeToken.primary : CloudThemeToken.textPrimary)
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
      // 2in1 侧栏切页时保留相册组件实例，只切换可见性。
      // TabPictures 会在 aboutToAppear 后异步加载照片记录；如果跟随条件分支销毁重建，
      // 每次从文件页切回来都会先以空 photos 渲染“还没有本地照片”，下一拍才显示网格。
      TabPictures({
        overLap: this.overLap,
        isActive: this.currentIndex === TabId.PICTURES
      })
        .width('100%')
        .height('100%')
        .visibility(this.currentIndex === TabId.PICTURES ? Visibility.Visible : Visibility.Hidden)

      if (this.currentIndex === TabId.FILES) {
        TabFiles({ overLap: this.overLap, isActive: true })
      } else if (this.currentIndex === TabId.REMOTE_DOWN) {
        TabRemoteDown({ overLap: this.overLap, isActive: true })
      } else if (this.currentIndex === TabId.MINE) {
        TabMine({ overLap: this.overLap, isActive: true })
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(CloudThemeToken.background)
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
