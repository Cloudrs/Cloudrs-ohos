import {
  DividerShowType, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial
} from "@kit.UIDesignKit";
import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudRouter } from "../utils/CloudRouter";
import { WindowMover } from "../utils/WindowMover";
import { TitleControlButton } from "./TitleControlButton";

/**
 * 二级页骨架（设置、账号与安全、相册备份）：整页是一个 HdsNavigation，标题栏在沉浸光感生效范围内，效果随设备档位由系统自适应。
 * 内容铺满全页、从标题栏底下滚过：调用方的滚动容器顶部留出 CloudThemeToken.hdsTitleBarHeight，
 * 并把同一个 Scroller 传进来；上滑时标题栏与文件页、相册页一样渐变出模糊材质。
 * 返回键和标题放在 stackBuilder 里自绘（HDS 原生返回键与标题做不了入场动效）：先内容后标题栏，
 * 整页滑入快到位时，返回键和标题再从屏幕最右侧滑入。
 */
@Component
export struct SubPageScaffold {
  @StorageProp(Constant.TITLE_BUTTON_INSET_END) titleButtonInsetEnd: number = 0;
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0;
  @Prop title: ResourceStr
  // 标题栏起始内边距；-1 表示默认 pagePadding（宽屏侧栏收起时由 TabMine 传入，让出悬浮折叠键）
  @Prop startPadding: number = -1
  // 内容的滚动控制器，用于标题栏滚动模糊；不传则标题栏保持初始样式
  scroller?: Scroller
  onBackClick?: () => void
  @BuilderParam content: () => void = this.emptyContent
  @State titleEntered: boolean = false

  @Builder emptyContent() {
  }

  private goBack(): void {
    if (this.onBackClick) {
      this.onBackClick()
    } else {
      CloudRouter.pop()
    }
  }

  private playTitleEnter(): void {
    if (this.titleEntered) {
      return
    }
    // 宽屏在「我的」内容区内原地打开（由 TabMine 传入返回回调）没有整页滑入，标题栏不必等页面到位
    this.getUIContext().animateTo({
      duration: CloudThemeToken.subPageTitleEnterDuration,
      delay: this.onBackClick ? 0 : CloudThemeToken.subPageTitleEnterDelay,
      curve: Curve.Friction
    }, () => {
      this.titleEntered = true
    })
  }

  @Builder titleStack() {
    Row({ space: CloudThemeToken.spacingXl }) {
      TitleControlButton({
        icon: $r('app.media.ic_back'),
        label: '返回',
        inTitleBar: true,
        onAction: () => this.goBack()
      })
      Text(this.title)
        .fontSize(CloudThemeToken.textSizeHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .height('100%')
        .onTouch(WindowMover.onTouch)
    }
    .width('100%')
    .height('100%')
    // stackBuilder 从标题栏左缘排起、不随 titleBar.padding 平移，左右边距在这里给；右侧让出 2in1 窗口三键
    .padding({
      left: this.startPadding >= 0 ? this.startPadding : CloudThemeToken.pagePadding,
      right: CloudThemeToken.pagePadding + this.titleButtonInsetEnd
    })
    .alignItems(VerticalAlign.Center)
    // 入场前整体推到屏幕右缘之外，入场时从最右侧滑到位
    .translate({ x: this.titleEntered ? 0 : this.windowWidthVp })
    .onAppear(() => this.playTitleEnter())
  }

  build() {
    HdsNavigation() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: ' '
        },
        stackBuilder: () => {
          this.titleStack()
        },
        divider: {
          showType: DividerShowType.OFF
        }
      },
      style: {
        // 与文件页、相册页同款：内容滚入标题栏底下时渐变出沉浸模糊
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        // 标题是空占位，但两态都得给标题色：开了滚动效果后 HDS 按它推状态栏图标深浅，缺省会推成白色
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable(this.scroller ? [this.scroller] : [])
    .backgroundColor(CloudThemeToken.background)
  }
}
