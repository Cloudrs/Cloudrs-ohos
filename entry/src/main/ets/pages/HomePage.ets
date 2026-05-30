import Constant from '../model/Constant';
import { TabFiles } from './tabs/TabFiles';
import { TabPictures } from './tabs/TabPictures';
import { TabRemoteDown } from './tabs/TabAria2';
import { TabMine } from './tabs/TabMine';
import { CloudThemeToken } from '../model/CloudTheme';
import { TabId, TabItem, TabList } from '../model/TabData';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { CloudRouter } from '../utils/CloudRouter';

@Component
export struct HomePage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @State currentIndex: number = TabId.FILES;
  @State overLap: boolean = true

  aboutToAppear(): void {
    AppStorage.set(Constant.TAB_BAR_HEIGHT, CloudThemeToken.tabBarHeight)
    CloudRouter.setHomeBackEnabled(this.currentIndex === TabId.FILES)
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
      .tabBar(this.getTabBarStyle(TabList[TabId.FILES]))
      .tabIndex(TabId.FILES)

      TabContent() {
        TabPictures({ overLap: this.overLap })
      }
      .tabBar(this.getTabBarStyle(TabList[TabId.PICTURES]))
      .tabIndex(TabId.PICTURES)

      TabContent() {
        TabRemoteDown({ overLap: this.overLap })
      }
      .tabBar(this.getTabBarStyle(TabList[TabId.REMOTE_DOWN]))
      .tabIndex(TabId.REMOTE_DOWN)

      TabContent() {
        TabMine({ overLap: this.overLap })
      }
      .tabBar(this.getTabBarStyle(TabList[TabId.MINE]))
      .tabIndex(TabId.MINE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
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
  }
}
