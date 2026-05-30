import Constant from '../model/Constant';
import { LoginParam } from '../model/net/LoginParam';
import { ImagePreview } from '../model/Params';
import { CloudThemeToken } from '../model/CloudTheme';
import { CloudRouter } from '../utils/CloudRouter';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { ImagePreviewPage } from './ImagePreview';
import { AboutPage } from './AboutPage';

@Entry
@Component
struct Index {
  @State pathStack: NavPathStack = new NavPathStack();
  @State rootPage: string = Constant.LOGIN_PAGE;
  @State rootLoginParam: LoginParam = new LoginParam(false, Constant.HOME_PAGE);
  @State overlayPage: string = '';
  @State imagePreviewParam: ImagePreview = new ImagePreview('', '', '');

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
        }
        this.overlayPage = pageUrl;
      }
    );
    if (this.pathStack.size() === 0) {
      CloudRouter.showStartPage();
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
    } else {
      HomePage()
    }
  }

  @Builder overlayBuilder() {
    if (this.overlayPage === Constant.IAMGE_PREVIEW_PAGE) {
      ImagePreviewPage({ routeParam: this.imagePreviewParam })
        .zIndex(CloudThemeToken.overlayZIndex)
    } else if (this.overlayPage === Constant.ABOUT_PAGE) {
      AboutPage()
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
