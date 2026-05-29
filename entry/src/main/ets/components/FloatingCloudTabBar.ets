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
    return CloudThemeToken.floatingTabBarPhoneWidthPercent
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
          .padding({
            left: CloudThemeToken.floatingTabBarHorizontalPadding,
            right: CloudThemeToken.floatingTabBarHorizontalPadding
          })
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)

          Divider()
            .width(CloudThemeToken.floatingTabBarHighlightWidthPercent)
            .height(CloudThemeToken.floatingTabBarHighlightHeight)
            .color(CloudThemeToken.glassHighlight)
            .margin({ top: CloudThemeToken.floatingTabBarHighlightTopMargin })
        }
        .width(this.getBarWidth())
        .height(CloudThemeToken.floatingTabBarVisualHeight)
        .borderRadius(CloudThemeToken.tabBarRadius)
        .backgroundColor(CloudThemeToken.surfaceTranslucent)
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .border({ width: CloudThemeToken.floatingTabBarBorderWidth, color: CloudThemeToken.line })
        .shadow({
          radius: CloudThemeToken.floatingTabBarShadowRadius,
          color: CloudThemeToken.floatingShadow,
          offsetX: 0,
          offsetY: CloudThemeToken.floatingTabBarShadowOffsetY
        })
      }
      .width('100%')
      .padding({ bottom: this.bottomInset + CloudThemeToken.floatingTabBarBottomGap })
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(CloudThemeToken.floatingTabBarZIndex)
      .transition(TransitionEffect.OPACITY.animation({
        duration: CloudThemeToken.floatingTabBarTransitionDuration,
        curve: Curve.EaseOut
      }))
    }
  }

  @Builder
  TabButton(tab: TabItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Stack({ alignContent: Alignment.Top }) {
        Row({ space: this.isSelected(tab) ? CloudThemeToken.floatingTabSelectedGap : 0 }) {
          Image(tab.image)
            .width(CloudThemeToken.floatingTabIconSize)
            .height(CloudThemeToken.floatingTabIconSize)
            .fillColor(this.isSelected(tab) ? CloudThemeToken.onPrimary : CloudThemeToken.textSecondary)

          if (this.isSelected(tab)) {
            Text(tab.text)
              .fontSize(CloudThemeToken.floatingTabTextSize)
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
            .width(CloudThemeToken.floatingTabSelectedHighlightWidth)
            .height(CloudThemeToken.floatingTabSelectedHighlightHeight)
            .color(CloudThemeToken.selectedHighlight)
            .margin({ top: CloudThemeToken.floatingTabSelectedHighlightTopMargin })
        }
      }
      .width('100%')
      .height('100%')
    }
    .width(this.getItemWidth())
    .height(CloudThemeToken.floatingTabItemHeight)
    .padding({
      left: this.isSelected(tab) ? CloudThemeToken.floatingTabSelectedHorizontalPadding : 0,
      right: this.isSelected(tab) ? CloudThemeToken.floatingTabSelectedHorizontalPadding : 0
    })
    .borderRadius(CloudThemeToken.controlRadius)
    .backgroundColor(this.isSelected(tab) ? CloudThemeToken.primary : CloudThemeToken.transparent)
    .shadow(this.isSelected(tab) ? {
      radius: CloudThemeToken.floatingTabSelectedShadowRadius,
      color: CloudThemeToken.selectedGlow,
      offsetX: 0,
      offsetY: CloudThemeToken.floatingTabSelectedShadowOffsetY
    } : {
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
    .animation({ duration: CloudThemeToken.floatingTabAnimationDuration, curve: Curve.EaseOut })
  }
}
