import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudRouter } from "../utils/CloudRouter";
import { TitleControlButton } from "./TitleControlButton";

@Component
export struct CommonTitle {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0;
  // 2in1 隐藏系统标题栏后窗口三键区宽度（其它设备为 0）
  @StorageProp(Constant.TITLE_BUTTON_INSET_END) titleButtonInsetEnd: number = 0;
  @Prop title: ResourceStr
  onBackClick?: ()=>void

  build() {
    Column() {
      Blank()
        .height(CloudThemeToken.getSafeTopInset(this.topRectHeight))

      Row({ space: CloudThemeToken.spacingPage }) {
        // 与 HDS 返回键、标题栏其它按钮同款（TitleControlButton：通透材质 + 光感）
        TitleControlButton({
          icon: $r('app.media.ic_back'),
          label: '返回',
          onAction: () => {
            if (this.onBackClick) {
              this.onBackClick()
            } else {
              CloudRouter.pop()
            }
          }
        })

        Text(this.title)
          .fontColor(CloudThemeToken.textPrimary)
          .fontSize(CloudThemeToken.commonTitleTextSize)
          .fontWeight(FontWeight.Bold)
      }
      // 2in1 自绘窗口三键在 titleRowHeight 行内垂直居中，标题行同高才能与三键对齐；右侧让出三键区
      .height(this.titleButtonInsetEnd > 0 ? CloudThemeToken.titleRowHeight : CloudThemeToken.titleBarHeight)
      .width('100%')
      // 返回键圆底与页面内容左缘对齐（pagePadding），与文本预览顶栏的 12+4 一致
      .padding({ left: CloudThemeToken.pagePadding, right: CloudThemeToken.pagePadding + this.titleButtonInsetEnd })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .backgroundColor(CloudThemeToken.background)
  }
}
