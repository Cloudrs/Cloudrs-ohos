import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudRouter } from "../utils/CloudRouter";

@Component
export struct CommonTitle {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @Prop title: ResourceStr
  onBackClick?: ()=>void

  build() {
    Column() {
      Blank()
        .height(CloudThemeToken.getSafeTopInset(this.topRectHeight))

      Row({ space: CloudThemeToken.spacingPage }) {
        Button({type: ButtonType.Circle}) {
          Image($r('app.media.ic_back'))
            .padding(CloudThemeToken.commonTitleIconPadding)
            .fillColor(CloudThemeToken.textPrimary)
        }
        .width(CloudThemeToken.iconButtonSize)
        .height(CloudThemeToken.iconButtonSize)
        .backgroundColor(CloudThemeToken.surface)
        .onClick(() => {
          if (this.onBackClick) {
            this.onBackClick()
          } else {
            CloudRouter.pop()
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
