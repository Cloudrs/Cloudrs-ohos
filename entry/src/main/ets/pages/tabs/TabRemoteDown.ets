import Constant from "../../model/Constant";

@Component
export struct TabRemoteDown {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;

  aboutToAppear(): void {

  }

  build() {
    Column() {
      Text('远程下载')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}