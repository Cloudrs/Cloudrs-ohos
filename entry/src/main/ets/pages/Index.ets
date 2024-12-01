import { HMDefaultGlobalAnimator, HMNavigation } from "@hadss/hmrouter";
import { AttributeUpdater } from "@kit.ArkUI";
import Constant from "../model/Constant";

@Entry
@Component
export struct Index {
  modifier: NavModifier = new NavModifier();

  build() {
    // @Entry中需要再套一层容器组件,Column或者Stack
    Column(){
      // 使用HMNavigation容器
      HMNavigation({
        navigationId: 'mainNavigation', homePageUrl: Constant.HOME_PAGE, options: {
          standardAnimator: HMDefaultGlobalAnimator.STANDARD_ANIMATOR,
          dialogAnimator: HMDefaultGlobalAnimator.DIALOG_ANIMATOR,
          modifier: this.modifier
        }
      }) {
        Text('导航HMRouter')
      }
    }
    .height('100%')
    .width('100%')
  }
}

class NavModifier extends AttributeUpdater<NavigationAttribute> {
  initializeModifier(instance: NavigationAttribute): void {
    instance.mode(NavigationMode.Stack);
    instance.navBarWidth('100%');
    instance.hideTitleBar(true);
    instance.hideToolBar(true);
  }
}