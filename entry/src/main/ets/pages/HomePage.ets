import Constant from '../model/Constant';
import { HMRouter } from '@hadss/hmrouter';
import { TabFiles } from './tabs/TabFiles';
import { TabPictures } from './tabs/TabPictures';
import { TabRemoteDown } from './tabs/TabAria2';
import { TabMine } from './tabs/TabMine';
import { CloudThemeToken } from '../model/CloudTheme';
import { TabItem, TabList } from '../model/TabData';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';

@HMRouter({pageUrl: Constant.HOME_PAGE, interceptors: [Constant.ACCESS_INTERCEPTOR], lifecycle: 'ExitLifecycle'})
@Component
export struct HomePage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @State currentIndex: number = 0;
  @State overLap: boolean = true

  aboutToAppear(): void {
    AppStorage.set(Constant.TAB_BAR_HEIGHT, CloudThemeToken.tabBarHeight)
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
    HdsTabs({ index: this.currentIndex }) {
      TabContent() {
        TabFiles({ overLap: this.overLap })
      }
      .tabBar(this.getTabBarStyle(TabList[0]))
      .tabIndex(0)

      TabContent() {
        TabPictures({ overLap: this.overLap })
      }
      .tabBar(this.getTabBarStyle(TabList[1]))
      .tabIndex(1)

      TabContent() {
        TabRemoteDown({ overLap: this.overLap })
      }
      .tabBar(this.getTabBarStyle(TabList[2]))
      .tabIndex(2)

      TabContent() {
        TabMine({ overLap: this.overLap })
      }
      .tabBar(this.getTabBarStyle(TabList[3]))
      .tabIndex(3)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
    .barOverlap(true)
    .barBackgroundColor(CloudThemeToken.transparent)
    .barBackgroundBlurStyle(BlurStyle.Regular)
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
      return true
    })
  }
}
