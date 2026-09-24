import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct CloudScaffold {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0
  // @Prop：随父组件状态变化刷新（如宽屏侧栏收起时动态让位）
  @Prop topPadding: number = CloudThemeToken.scaffoldTopPadding
  bottomPadding: number = CloudThemeToken.scaffoldBottomPadding
  horizontalPadding: number = CloudThemeToken.pagePadding
  scrollable: boolean = true
  avoidTabBar: boolean = true
  // 页面底色，默认不透明背板；沉浸页（如 2in1 我的页透壁纸）可传透明让位给身后
  bgColor: ResourceColor = CloudThemeToken.background
  scroller?: Scroller
  @BuilderParam content: () => void = this.defaultContent

  @Builder defaultContent() {
  }

  private getTopInset(): number {
    return CloudThemeToken.getSafeTopInset(this.topRectHeight)
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
      .backgroundColor(this.bgColor)
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
      .backgroundColor(this.bgColor)
    }
  }
}
