import Constant from '../model/Constant';
import { TabFiles } from './tabs/TabFiles';
import { TabPictures } from './tabs/TabPictures';
import { TabRemoteDown } from './tabs/TabAria2';
import { TabMine } from './tabs/TabMine';
import { CloudThemeToken } from '../model/CloudTheme';
import { TabId, TabItem, TabList } from '../model/TabData';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { CloudRouter } from '../utils/CloudRouter';
import { common } from '@kit.AbilityKit';
import { AppLockUtil } from '../utils/AppLockUtil';
import { showToast } from '../utils/ToastUtil';

@Component
export struct HomePage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @Watch('onForegroundTickChanged')
  @StorageProp(Constant.APP_FOREGROUND_TICK) foregroundTick: number = 0;
  @StorageProp(Constant.APP_LOCKED) appLocked: boolean = false
  @State currentIndex: number = TabId.FILES;
  @State overLap: boolean = true
  @State appLockChecking: boolean = false
  @State appLockError: string = ''
  @State preloadMineIconsEnabled: boolean = false
  private appLockVerifyTimer: number = -1

  aboutToAppear(): void {
    AppStorage.set(Constant.TAB_BAR_HEIGHT, CloudThemeToken.tabBarHeight)
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
        console.error(`App lock failed: ${err.message}`)
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

  build() {
    Stack() {
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
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .vertical(false)
      .barMode(BarMode.Fixed)
      .animationDuration(CloudThemeToken.defaultAnimationDuration)
      .onChange((index: number) => {
        this.currentIndex = index
        CloudRouter.setHomeBackEnabled(index === TabId.FILES)
        return true
      })

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
