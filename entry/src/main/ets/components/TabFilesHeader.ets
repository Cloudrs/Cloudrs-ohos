import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import { TransportObject } from "../model/TransportObject";
import LazyDataSource from "../utils/LazyDataSource";
import { Downloads } from "./Downloads";
import { Uploads } from "./Uploads";

@Component
export struct TabFilesHeader {
  @Prop isRoot: boolean;
  @State showTransport:boolean = false;
  @ObjectLink downloadObjects: LazyDataSource<TransportObject>
  onBackClick?: () => void;
  onTransportClick?: () => void;
  onPersonClick?: () => void;

  @State selectCapsuleOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: $r('app.string.task_download') }, { text: $r('app.string.task_upload') }] as SegmentButtonItemTuple,
    multiply: false,
    backgroundBlurStyle: BlurStyle.BACKGROUND_THICK
  })
  @State selectedIndexes: number[] = [0]

  build() {
    Column() {
      Row() {
        Row({ space: 10 }) {
          if (!this.isRoot) {
            Button() {
              Image($r('app.media.ic_back'))
                .padding(5)
                .fillColor(Color.Black)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(Color.White)
            .onClick(() => {
              if (this.onBackClick) {
                this.onBackClick()
              }
            })
            .transition(TransitionEffect.OPACITY.animation({duration: 200})
              .combine(TransitionEffect.scale({x: 0, y: 0}).animation({duration: 200})))
          }

          Search({ placeholder: $r("app.string.header_search") })
            .searchIcon({ color: Color.Black })
            .backgroundColor(Color.White)
        }
        .width('50%')

        Row({ space: 10 }) {
          Button() {
            Image($r('app.media.ic_transport'))
              .padding(10)
              .fillColor(Color.Black)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.light_light_gray'))
          .onClick(() => {
            this.showTransport = true
            if (this.onTransportClick) {
              this.onTransportClick()
            }
          })
          .bindSheet($$this.showTransport, this.transportBuilder(), {
            // detents: [SheetSize.FIT_CONTENT],
            backgroundColor: Color.White,
            title: this.transportTitle($r('app.string.transport_title'))
          })

          Button() {
            Image($r('app.media.ic_person'))
              .padding(10)
              .fillColor(Color.Black)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.White)
          .onClick(() => {
            if (this.onPersonClick) {
              this.onPersonClick()
            }
          })
        }
        .width(100)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(36)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding({ left: 10, right: 10 })
    .width('100%')
    .height(40)
    .align(Alignment.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder transportTitle(title: ResourceStr) {
    Row() {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder transportBuilder() {
    Column() {
      SegmentButton({ options: this.selectCapsuleOptions, selectedIndexes: $selectedIndexes })
      Column() {
        if (this.selectedIndexes[0] == 0) {
          Downloads({downloadObjects: this.downloadObjects})
        }
        else {
          Uploads()
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
    .padding({left: 10, right: 10, top: 10, bottom: 20})
    .height('100%')
    .width('100%')
    .backgroundColor($r('app.color.sheet_default_background'))
  }
}