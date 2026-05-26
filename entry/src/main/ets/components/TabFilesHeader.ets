import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import { TransportObject } from "../model/TransportObject";
import LazyDataSource from "../utils/LazyDataSource";
import { Downloads } from "./Downloads";
import { Uploads } from "./Uploads";
import { CloudThemeToken } from "../model/CloudTheme";

@Component
export struct TabFilesHeader {
  @Prop isRoot: boolean;
  @State showTransport:boolean = false;
  @ObjectLink downloadObjects: LazyDataSource<TransportObject>
  @ObjectLink uploadObjects: LazyDataSource<TransportObject>
  @Prop downloadingCount: number = 0;
  @Prop uploadingCount: number = 0;
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
                .fillColor(CloudThemeToken.textPrimary)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(CloudThemeToken.surface)
            .onClick(() => {
              if (this.onBackClick) {
                this.onBackClick()
              }
            })
            .transition(TransitionEffect.OPACITY.animation({duration: 200})
              .combine(TransitionEffect.scale({x: 0, y: 0}).animation({duration: 200})))
          }

          Search({ placeholder: $r("app.string.header_search") })
            .searchIcon({ color: CloudThemeToken.textPrimary })
            .backgroundColor(CloudThemeToken.surface)
        }
        .width('50%')

        Row({ space: 10 }) {
          Button() {
            Badge({
              count: this.downloadingCount+this.uploadingCount,
              style: {badgeSize:12},
              position: BadgePosition.RightTop
            }) {
              Image($r('app.media.ic_transport'))
                .padding(10)
                .fillColor(CloudThemeToken.textPrimary)
            }
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .onClick(() => {
            this.showTransport = true
            if (this.onTransportClick) {
              this.onTransportClick()
            }
          })
          .bindSheet($$this.showTransport, this.transportBuilder(), {
            // detents: [SheetSize.FIT_CONTENT],
            backgroundColor: CloudThemeToken.surface,
            title: this.transportTitle($r('app.string.transport_title'))
          })

          Button() {
            Image($r('app.media.ic_person'))
              .padding(10)
              .fillColor(CloudThemeToken.textPrimary)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(CloudThemeToken.surface)
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
        .fontColor(CloudThemeToken.textPrimary)
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
          Uploads({uploadObjects: this.uploadObjects})
        }
      }
      .width('100%')
      .margin({top: 10})
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.background)
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .padding({left: 10, right: 10, top: 10, bottom: 20})
    .height('100%')
    .width('100%')
    .backgroundColor(CloudThemeToken.background)
  }
}
