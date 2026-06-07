import Constant from '../model/Constant';
import { LoginParam } from '../model/net/LoginParam';
import { FileSearchParam, ImagePreview, PhotoLocalPreviewParam, VideoPreview } from '../model/Params';
import { CloudThemeToken } from '../model/CloudTheme';
import { CloudRouter } from '../utils/CloudRouter';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { ImagePreviewPage } from './ImagePreview';
import { VideoPreviewPage } from './VideoPreview';
import { AboutPage } from './AboutPage';
import { FileSearchPage } from './FileSearchPage';
import { PhotoLocalPreviewPage } from './PhotoLocalPreview';

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

  aboutToAppear(): void {
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
      setTimeout(() => {
        if (this.pathStack.size() === 0) {
          CloudRouter.showStartPage();
        }
      }, 0);
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
