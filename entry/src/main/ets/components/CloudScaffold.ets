import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct CloudScaffold {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0
  topPadding: number = CloudThemeToken.scaffoldTopPadding
  bottomPadding: number = CloudThemeToken.scaffoldBottomPadding
  horizontalPadding: number = CloudThemeToken.pagePadding
  scrollable: boolean = true
  avoidTabBar: boolean = true
  scroller?: Scroller
  @BuilderParam content: () => void = this.defaultContent

  @Builder defaultContent() {
  }

  private getTopInset(): number {
    if (this.topRectHeight <= CloudThemeToken.zero) {
      return CloudThemeToken.systemTopFallbackHeight
    }
    return Math.min(this.topRectHeight, CloudThemeToken.systemTopFallbackHeight)
  }

  build() {
    if (this.scrollable) {
      Scroll(this.scroller) {
        Column({ space: CloudThemeToken.sectionGap }) {
          this.content()
        }
        .width('100%')
        .padding({
          left: this.horizontalPadding,
          right: this.horizontalPadding,
          top: this.getTopInset() + this.topPadding,
          bottom: (this.avoidTabBar ? this.tabBarHeight : 0) + this.bottomPadding
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.background)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    } else {
      Column({ space: CloudThemeToken.sectionGap }) {
        this.content()
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.horizontalPadding,
        right: this.horizontalPadding,
        top: this.getTopInset() + this.topPadding,
        bottom: (this.avoidTabBar ? this.tabBarHeight : 0) + this.bottomPadding
      })
      .backgroundColor(CloudThemeToken.background)
    }
  }
}
