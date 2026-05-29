import Constant from '../model/Constant';
import { HMRouter } from '@hadss/hmrouter';
import { TabFiles } from './tabs/TabFiles';
import { TabPictures } from './tabs/TabPictures';
import { TabRemoteDown } from './tabs/TabAria2';
import { TabMine } from './tabs/TabMine';
import { CloudThemeToken } from '../model/CloudTheme';
import { FloatingCloudTabBar } from '../components/FloatingCloudTabBar';

@HMRouter({pageUrl: Constant.HOME_PAGE, interceptors: [Constant.ACCESS_INTERCEPTOR], lifecycle: 'ExitLifecycle'})
@Component
export struct HomePage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @State currentIndex: number = 0;
  @State pageWidth: number = 0;
  @State overLap: boolean = true
  private controller: TabsController = new TabsController()

  aboutToAppear(): void {
    AppStorage.set(Constant.TAB_BAR_HEIGHT, CloudThemeToken.tabBarHeight)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
        TabContent() {
          TabFiles({ overLap: this.overLap })
        }

        TabContent() {
          TabPictures({ overLap: this.overLap })
        }

        TabContent() {
          TabRemoteDown({ overLap: this.overLap })
        }

        TabContent() {
          TabMine({ overLap: this.overLap })
        }
      }
      .width('100%')
      .height('100%')
      .barHeight(0)
      .barWidth(0)
      .barOverlap(true)
      .barMode(BarMode.Fixed)
      .backgroundColor(CloudThemeToken.background)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        let width = Number(newArea.width)
        if (!Number.isNaN(width) && Math.abs(width - this.pageWidth) >= 1) {
          this.pageWidth = width
        }
      })
      .onChange((index) => {
        this.currentIndex = index;
        return true
      })

      FloatingCloudTabBar({
        currentIndex: this.currentIndex,
        visible: this.overLap,
        bottomInset: this.bottomRectHeight,
        containerWidth: this.pageWidth,
        onTabClick: (index: number) => {
          this.currentIndex = index
          this.controller.changeIndex(index)
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
