import { CloudLayoutMode, CloudThemeToken } from '../model/CloudTheme';
import { TabItem, TabList } from '../model/TabData';

@Component
export struct FloatingCloudTabBar {
  @Prop currentIndex: number = 0
  @Prop visible: boolean = true
  @Prop bottomInset: number = 0
  @Prop containerWidth: number = 0
  onTabClick?: (index: number) => void

  private getLayoutMode(): CloudLayoutMode {
    return CloudThemeToken.getLayoutMode(this.containerWidth)
  }

  private getBarWidth(): Length {
    if (this.getLayoutMode() !== CloudLayoutMode.PHONE) {
      return CloudThemeToken.floatingTabBarMaxWidth
    }
    return '92%'
  }

  private getItemWidth(): Length {
    if (this.getLayoutMode() !== CloudLayoutMode.PHONE) {
      return CloudThemeToken.floatingTabItemWideWidth
    }
    return '25%'
  }

  private isSelected(tab: TabItem): boolean {
    return this.currentIndex === tab.tabId
  }

  build() {
    if (this.visible) {
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          Row() {
            ForEach(TabList, (tab: TabItem) => {
              this.TabButton(tab)
            }, (tab: TabItem) => tab.tabId.toString())
          }
          .width('100%')
          .height(CloudThemeToken.floatingTabBarVisualHeight)
          .padding({ left: 8, right: 8 })
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)

          Divider()
            .width('88%')
            .height(1)
            .color(CloudThemeToken.glassHighlight)
            .margin({ top: 1 })
        }
        .width(this.getBarWidth())
        .height(CloudThemeToken.floatingTabBarVisualHeight)
        .borderRadius(CloudThemeToken.tabBarRadius)
        .backgroundColor(CloudThemeToken.surfaceTranslucent)
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .border({ width: 1, color: CloudThemeToken.line })
        .shadow({ radius: 26, color: CloudThemeToken.floatingShadow, offsetX: 0, offsetY: 12 })
      }
      .width('100%')
      .padding({ bottom: this.bottomInset + CloudThemeToken.floatingTabBarBottomGap })
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(20)
      .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
    }
  }

  @Builder
  TabButton(tab: TabItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Stack({ alignContent: Alignment.Top }) {
        Row({ space: this.isSelected(tab) ? 6 : 0 }) {
          Image(tab.image)
            .width(20)
            .height(20)
            .fillColor(this.isSelected(tab) ? CloudThemeToken.onPrimary : CloudThemeToken.textSecondary)

          if (this.isSelected(tab)) {
            Text(tab.text)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(CloudThemeToken.onPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        if (this.isSelected(tab)) {
          Divider()
            .width(42)
            .height(1)
            .color(CloudThemeToken.selectedHighlight)
            .margin({ top: 3 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .width(this.getItemWidth())
    .height(CloudThemeToken.floatingTabItemHeight)
    .padding({ left: this.isSelected(tab) ? 12 : 0, right: this.isSelected(tab) ? 12 : 0 })
    .borderRadius(CloudThemeToken.controlRadius)
    .backgroundColor(this.isSelected(tab) ? CloudThemeToken.primary : CloudThemeToken.transparent)
    .shadow(this.isSelected(tab) ? { radius: 14, color: CloudThemeToken.selectedGlow, offsetX: 0, offsetY: 6 } : {
      radius: 0,
      color: CloudThemeToken.transparent,
      offsetX: 0,
      offsetY: 0
    })
    .onClick(() => {
      if (this.onTabClick) {
        this.onTabClick(tab.tabId)
      }
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }
}
