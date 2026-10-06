import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudRouter } from "../utils/CloudRouter";
import { TitleControlButton } from "./TitleControlButton";

@Component
export struct CommonTitle {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0;
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
      .height(CloudThemeToken.titleBarHeight)
      .width('100%')
      .padding({ left: CloudThemeToken.spacingXs, right: CloudThemeToken.pagePadding })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .backgroundColor(CloudThemeToken.background)
  }
}
