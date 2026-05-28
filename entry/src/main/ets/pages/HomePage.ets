import Constant from '../model/Constant';
import { HMRouter } from '@hadss/hmrouter';
import { TabId, TabItem, TabList } from '../model/TabData';
import { TabFiles } from './tabs/TabFiles';
import { TabPictures } from './tabs/TabPictures';
import { TabRemoteDown } from './tabs/TabAria2';
import { TabMine } from './tabs/TabMine';
import { CloudThemeToken } from '../model/CloudTheme';

@HMRouter({pageUrl: 'HomePage', interceptors: ['AccessInterceptor'], lifecycle: 'ExitLifecycle'})
@Component
export struct HomePage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @State currentIndex: number = 0;
  @State overLap: boolean = true
  private controller: TabsController = new TabsController()

  aboutToAppear(): void {
    AppStorage.set(Constant.TAB_BAR_HEIGHT, CloudThemeToken.tabBarHeight)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
      TabContent() {
        TabFiles({ overLap: this.overLap })
      }.tabBar(this.TabBuilder(TabList[TabId.FILES]))

      TabContent() {
        TabPictures()
      }.tabBar(this.TabBuilder(TabList[TabId.PICTURES]))

      TabContent() {
        TabRemoteDown()
      }.tabBar(this.TabBuilder(TabList[TabId.REMOTE_DOWN]))

      TabContent() {
        TabMine()
      }.tabBar(this.TabBuilder(TabList[TabId.MINE]))
    }
    .width('100%')
    .barHeight(this.overLap ? this.tabBarHeight : 0)
    .barWidth(this.overLap ? '92%' : '0%')
    .layoutWeight(1)
    .barOverlap(true)
    .barBackgroundColor(CloudThemeToken.surfaceTranslucent)
    .barBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .barMode(BarMode.Fixed)
    .backgroundColor(CloudThemeToken.background)
    .onChange((index) => {
      this.currentIndex = index;
      return true
    })
  }

  @Builder
  TabBuilder(tab: TabItem) {
    Column() {
      Row({ space: this.currentIndex === tab.tabId ? 5 : 0 }) {
        Image(tab.image)
          .width(20)
          .height(20)
          .fillColor(this.currentIndex === tab.tabId ? Color.White : CloudThemeToken.textSecondary)
        if (this.currentIndex === tab.tabId) {
          Text(tab.text)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .height(42)
      .padding({ left: this.currentIndex === tab.tabId ? 14 : 0, right: this.currentIndex === tab.tabId ? 14 : 0 })
      .borderRadius(CloudThemeToken.controlRadius)
      .backgroundColor(this.currentIndex === tab.tabId ? CloudThemeToken.primary : Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .animation({ duration: 180, curve: Curve.EaseOut })

      if (this.currentIndex !== tab.tabId) {
        Text(tab.text)
          .fontSize(10)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .padding({ top: 8, bottom: this.bottomRectHeight + 8 })
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .animation({ duration: 180, curve: Curve.EaseOut })
  }
}
