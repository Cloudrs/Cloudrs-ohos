import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@ohos.arkui.advanced.SegmentButton";

const TAG = 'Transport'
@Component
export struct Transport {
  @State selectCapsuleOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: $r('app.string.task_download') }, { text: $r('app.string.task_upload') }] as SegmentButtonItemTuple,
    multiply: false,
    backgroundBlurStyle: BlurStyle.BACKGROUND_THICK
  })
  @State selectedIndexes: number[] = [0]

  build() {
    Column() {
      SegmentButton({ options: this.selectCapsuleOptions, selectedIndexes: $selectedIndexes })
      Column() {
        if (this.selectedIndexes[0] == 0) {
          Text('没有下载任务')
        }
        else {
          Text('没有上传任务')
        }
      }
      .width('100%')
      .margin({top: 5})
      .borderRadius(20)
      .backgroundColor($r('app.color.nav_background'))
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .padding({left: 10, right: 10, bottom: 20})
    .height('100%')
    .width('100%')
    .backgroundColor($r('app.color.sheet_default_background'))
  }
}