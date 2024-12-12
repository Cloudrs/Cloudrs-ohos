import Constant from '../model/Constant';
import { HMRouter } from '@hadss/hmrouter';
import { TabId, TabItem, TabList } from '../model/TabData';
import { TabFiles } from './tabs/TabFiles';
import { TabPictures } from './tabs/TabPictures';
import { TabRemoteDown } from './tabs/TabRemoteDown';
import { TabMine } from './tabs/TabMine';

@HMRouter({pageUrl: Constant.HOME_PAGE, interceptors: [Constant.ACCESS_INTERCEPTOR], lifecycle: 'ExitLifecycle'})
@Preview
@Component
export struct HomePage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State currentIndex: number = 0;
  @State overLap:boolean = true
  private controller: TabsController = new TabsController()

  build() {
    Tabs({barPosition: BarPosition.End, controller: this.controller}) {
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
    // .height('100%')
    .barHeight(70)
    .barWidth('100%')
    .layoutWeight(1)
    .barOverlap(true)
    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.Thin)
    .barMode(BarMode.Fixed)
    .divider({ strokeWidth: 1, color: $r("app.color.default_line_color") })
    .onChange((index) => {
      this.currentIndex = index;
      return true
    })
  }

  @Builder
  TabBuilder(tab: TabItem) {
    Column({space: 5}) {
      Image(tab.image)
        .width(20)
        .fillColor(this.currentIndex === tab.tabId ? $r('app.color.tab_bar_select') : $r('app.color.tab_bar_default'))
      Text(tab.text)
        .fontSize(11)
        .fontColor(this.currentIndex === tab.tabId ? $r('app.color.tab_bar_select') : $r('app.color.tab_bar_default'))
    }
    .padding({top: 10, bottom: this.bottomRectHeight})
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
