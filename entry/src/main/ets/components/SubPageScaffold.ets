import { LengthMetrics } from "@kit.ArkUI";
import {
  DividerShowType, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial
} from "@kit.UIDesignKit";
import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudMaterial } from "../model/CloudMaterial";
import { CloudRouter } from "../utils/CloudRouter";

/**
 * 二级页骨架（设置、账号与安全、关于）：整页是一个 HdsNavigation，返回键用 HDS 原生 backIcon，
 * 在沉浸光感生效范围内（标题栏），效果随设备档位由系统自适应。
 * 内容铺满全页、从标题栏底下滚过：调用方的滚动容器顶部留出 CloudThemeToken.hdsTitleBarHeight，
 * 并把同一个 Scroller 传进来；上滑时标题栏与文件页、相册页一样渐变出模糊材质。
 */
@Component
export struct SubPageScaffold {
  @StorageProp(Constant.TITLE_BUTTON_INSET_END) titleButtonInsetEnd: number = 0;
  @Prop title: ResourceStr
  // 标题栏起始内边距；-1 表示 HDS 默认（宽屏侧栏收起时由 TabMine 传入，让出悬浮折叠键）
  @Prop startPadding: number = -1
  // 内容的滚动控制器，用于标题栏滚动模糊；不传则标题栏保持初始样式
  scroller?: Scroller
  onBackClick?: () => void
  @BuilderParam content: () => void = this.emptyContent

  @Builder emptyContent() {
  }

  build() {
    HdsNavigation() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideBackButton(false)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: this.title
        },
        backIcon: {
          icon: $r('app.media.ic_back'),
          action: () => {
            if (this.onBackClick) {
              this.onBackClick()
            } else {
              CloudRouter.pop()
            }
          }
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
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            },
            // 置透明露出 HDS 标题栏材质（效果随设备档位由系统自适应）；<26 实色
            backIconStyle: {
              backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.surfaceSubtle),
              iconColor: CloudThemeToken.textPrimary
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            },
            backIconStyle: {
              backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.surfaceSubtle),
              iconColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      padding: {
        start: this.startPadding >= 0 ? LengthMetrics.vp(this.startPadding) : undefined,
        end: this.titleButtonInsetEnd > 0 ?
          LengthMetrics.vp(this.titleButtonInsetEnd + CloudThemeToken.spacingCard) : undefined
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable(this.scroller ? [this.scroller] : [])
    .backgroundColor(CloudThemeToken.background)
  }
}
