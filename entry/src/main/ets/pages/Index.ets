import Constant from '../model/Constant';
import { LoginParam } from '../model/net/LoginParam';
import { FileSearchParam, ImagePreview, PhotoLocalPreviewParam, VideoPreview } from '../model/Params';
import { CloudThemeToken } from '../model/CloudTheme';
import { CloudRouter } from '../utils/CloudRouter';
import { AppBoot } from '../utils/AppBoot';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { ImagePreviewPage } from './ImagePreview';
import { VideoPreviewPage } from './VideoPreview';
import { AboutPage } from './AboutPage';
import { FileSearchPage } from './FileSearchPage';
import { PhotoLocalPreviewPage } from './PhotoLocalPreview';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import AppLogger from '../utils/AppLogger';

@Entry
@Component
struct Index {
  private pathStack: NavPathStack = new NavPathStack();
  @State rootPage: string = '';
  @State rootLoginParam: LoginParam = new LoginParam(false, Constant.HOME_PAGE);
  @State overlayPage: string = '';
  @State imagePreviewParam: ImagePreview = new ImagePreview('', '', '');
  @State videoPreviewParam: VideoPreview = new VideoPreview('', '', '');
  @State fileSearchParam: FileSearchParam = new FileSearchParam();
  @State photoLocalPreviewParam: PhotoLocalPreviewParam = new PhotoLocalPreviewParam([], 0, false);
  private startPageScheduled: boolean = false;
  private mainWindow: window.Window | undefined = undefined;
  private windowSizeListener: ((size: window.Size) => void) | undefined = undefined;
  private keyboardHeightListener: ((heightPx: number) => void) | undefined = undefined;

  aboutToAppear(): void {
    this.setupWindowMetrics();
    CloudRouter.init(
      this.pathStack,
      (pageUrl: string, param: Object) => {
        if (pageUrl === Constant.LOGIN_PAGE) {
          this.rootLoginParam = param as LoginParam;
        }
        this.rootPage = pageUrl;
      },
      (pageUrl: string, param: Object) => {
        if (pageUrl === Constant.IAMGE_PREVIEW_PAGE) {
          this.imagePreviewParam = param as ImagePreview;
        } else if (pageUrl === Constant.VIDEO_PREVIEW_PAGE) {
          this.videoPreviewParam = param as VideoPreview;
        } else if (pageUrl === Constant.FILE_SEARCH_PAGE) {
          this.fileSearchParam = param as FileSearchParam;
        } else if (pageUrl === Constant.PHOTO_LOCAL_PREVIEW_PAGE) {
          this.photoLocalPreviewParam = param as PhotoLocalPreviewParam;
        }
        this.overlayPage = pageUrl;
      }
    );
    if (!this.startPageScheduled) {
      this.startPageScheduled = true;
      // 登录态判定依赖 UserDatabase，等首帧后的延迟初始化完成再决策启动页
      AppBoot.whenReady().then(() => {
        if (this.pathStack.size() === 0) {
          CloudRouter.showStartPage();
        }
      });
    }
  }

  aboutToDisappear(): void {
    if (this.mainWindow && this.windowSizeListener) {
      try {
        this.mainWindow.off('windowSizeChange', this.windowSizeListener);
      } catch (_) {
      }
    }
    if (this.mainWindow && this.keyboardHeightListener) {
      try {
        this.mainWindow.off('keyboardHeightChange', this.keyboardHeightListener);
      } catch (_) {
      }
    }
    this.mainWindow = undefined;
    this.windowSizeListener = undefined;
    this.keyboardHeightListener = undefined;
  }

  private setupWindowMetrics(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (!context) {
      return;
    }
    window.getLastWindow(context).then((win) => {
      this.mainWindow = win;
      this.publishWindowSize();
      const listener: (size: window.Size) => void = (size: window.Size) => {
        this.publishWindowSize(size);
      };
      this.windowSizeListener = listener;
      try {
        win.on('windowSizeChange', listener);
      } catch (err) {
        AppLogger.warn('Index', `register windowSizeChange failed: ${(err as Error)?.message ?? err}`);
      }
      // 键盘高度进 AppStorage，输入类弹窗据此手动避让（bindSheet 单挡 FIT_CONTENT 时系统避让只保证光标可见）
      const kbListener: (heightPx: number) => void = (heightPx: number) => {
        AppStorage.setOrCreate(Constant.KEYBOARD_HEIGHT_VP, this.getUIContext().px2vp(heightPx));
      };
      this.keyboardHeightListener = kbListener;
      try {
        win.on('keyboardHeightChange', kbListener);
      } catch (err) {
        AppLogger.warn('Index', `register keyboardHeightChange failed: ${(err as Error)?.message ?? err}`);
      }
    }).catch((err: Error) => {
      AppLogger.warn('Index', `getLastWindow failed: ${err.message}`);
    });
  }

  private publishWindowSize(size?: window.Size): void {
    if (!this.mainWindow) {
      return;
    }
    try {
      const uiContext = this.getUIContext();
      // 兜底：把 status bar 高度也在这里刷新；EntryAbility 早期可能抛 1300002 走 catch，留下 0
      try {
        const topAreaPx = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
        const topAreaVp = uiContext.px2vp(topAreaPx);
        if (topAreaVp > 0) {
          AppStorage.setOrCreate(Constant.SYSTEM_TOP_RECT_HEIGHT, topAreaVp);
        }
        const bottomAreaPx = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height;
        const bottomAreaVp = uiContext.px2vp(bottomAreaPx);
        if (bottomAreaVp > 0) {
          AppStorage.setOrCreate(Constant.NAV_BOTTOM_RECT_HEIGHT, bottomAreaVp);
        }
      } catch (_) {
      }
      let widthPx: number;
      let heightPx: number;
      if (size) {
        widthPx = size.width;
        heightPx = size.height;
      } else {
        const props = this.mainWindow.getWindowProperties();
        widthPx = props.windowRect.width;
        heightPx = props.windowRect.height;
      }
      const heightVp = uiContext.px2vp(heightPx);
      let widthVp = uiContext.px2vp(widthPx);
      // 2in1 上窗口含两侧装饰条（约 5.4vp x 2），扣掉才能得到真实内容宽
      if (deviceInfo.deviceType === '2in1') {
        widthVp = widthVp - 2 * CloudThemeToken.twoInOneDecorPaddingVp;
      }
      // 2in1 设备 PC 风格，达到 lg 阈值就直接进入 xl 布局（带文字侧边栏 + 居中 sheet）
      // 平板/折叠屏继续按宽度断点，因为它们在 lg 段更适合紧凑图标导航
      const rawWidthVp = widthVp;
      if (deviceInfo.deviceType === '2in1' && widthVp >= CloudThemeToken.breakpointLg) {
        widthVp = Math.max(widthVp, CloudThemeToken.breakpointXl);
      }
      const bp = CloudThemeToken.getBreakpoint(widthVp);
      AppStorage.setOrCreate(Constant.WINDOW_WIDTH_VP, widthVp);
      AppStorage.setOrCreate(Constant.WINDOW_HEIGHT_VP, heightVp);
      AppStorage.setOrCreate(Constant.LAYOUT_MODE, bp);
      AppLogger.info('Index',
        `window metrics rawWidthVp=${rawWidthVp.toFixed(1)} effectiveWidthVp=${widthVp.toFixed(1)} heightVp=${heightVp.toFixed(1)} bp=${bp} deviceType=${deviceInfo.deviceType}`);
    } catch (err) {
      AppLogger.warn('Index', `publishWindowSize failed: ${(err as Error)?.message ?? err}`);
    }
  }

  onBackPress(): boolean {
    if (CloudRouter.hasOverlay()) {
      CloudRouter.pop();
      return true;
    }
    if (this.pathStack.size() > 0) {
      return false;
    }
    if (this.rootPage === Constant.LOGIN_PAGE) {
      return CloudRouter.handleExitBack(this.getUIContext());
    }
    return CloudRouter.handleHomeBack(this.getUIContext());
  }

  build() {
    Stack() {
      Navigation(this.pathStack) {
        this.rootBuilder()
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .navBarWidth('100%')
      .hideTitleBar(true)
      .hideToolBar(true)
      .hideBackButton(true)
      .navDestination((name: string, param: Object) => {
        this.destinationBuilder(name, param);
      })

      this.overlayBuilder()
    }
    .width('100%')
    .height('100%')
  }

  @Builder rootBuilder() {
    if (this.rootPage === Constant.LOGIN_PAGE) {
      LoginPage({ routeParam: this.rootLoginParam })
    } else if (this.rootPage === Constant.HOME_PAGE) {
      HomePage()
    } else {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.background)
    }
  }

  @Builder overlayBuilder() {
    if (this.overlayPage === Constant.IAMGE_PREVIEW_PAGE) {
      ImagePreviewPage({ routeParam: this.imagePreviewParam })
        .zIndex(CloudThemeToken.overlayZIndex)
    } else if (this.overlayPage === Constant.VIDEO_PREVIEW_PAGE) {
      VideoPreviewPage({ routeParam: this.videoPreviewParam })
        .zIndex(CloudThemeToken.overlayZIndex)
    } else if (this.overlayPage === Constant.FILE_SEARCH_PAGE) {
      FileSearchPage({ routeParam: this.fileSearchParam })
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY
          .animation({ duration: CloudThemeToken.defaultAnimationDuration, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: CloudThemeToken.iconBoxLg })
            .animation({ duration: CloudThemeToken.defaultAnimationDuration, curve: Curve.EaseOut })))
        .zIndex(CloudThemeToken.overlayZIndex)
    } else if (this.overlayPage === Constant.ABOUT_PAGE) {
      AboutPage()
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY
          .animation({ duration: CloudThemeToken.defaultAnimationDuration, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: CloudThemeToken.iconBoxLg })
            .animation({ duration: CloudThemeToken.defaultAnimationDuration, curve: Curve.EaseOut })))
        .zIndex(CloudThemeToken.overlayZIndex)
    } else if (this.overlayPage === Constant.PHOTO_LOCAL_PREVIEW_PAGE) {
      PhotoLocalPreviewPage({ routeParam: this.photoLocalPreviewParam })
        .width('100%')
        .height('100%')
        .zIndex(CloudThemeToken.overlayZIndex)
    }
  }

  @Builder destinationBuilder(name: string, param: Object) {
    if (name === Constant.IAMGE_PREVIEW_PAGE) {
      NavDestination() {
        Stack() {
          ImagePreviewPage({ routeParam: param as ImagePreview })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.previewBackground)
      }
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.previewBackground)
    } else if (name === Constant.VIDEO_PREVIEW_PAGE) {
      NavDestination() {
        Stack() {
          VideoPreviewPage({ routeParam: param as VideoPreview })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.previewBackground)
      }
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.previewBackground)
    } else if (name === Constant.ABOUT_PAGE) {
      NavDestination() {
        Stack() {
          AboutPage()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.background)
      }
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.background)
    } else if (name === Constant.FILE_SEARCH_PAGE) {
      NavDestination() {
        Stack() {
          FileSearchPage({ routeParam: param as FileSearchParam })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.surface)
      }
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.surface)
    } else if (name === Constant.PHOTO_LOCAL_PREVIEW_PAGE) {
      NavDestination() {
        Stack() {
          PhotoLocalPreviewPage({ routeParam: param as PhotoLocalPreviewParam })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.previewBackground)
      }
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.previewBackground)
    } else {
      NavDestination() {
        Stack() {
          HomePage()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(CloudThemeToken.background)
      }
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.background)
      .onBackPressed(() => {
        return CloudRouter.handleHomeBack(this.getUIContext());
      })
    }
  }
}
