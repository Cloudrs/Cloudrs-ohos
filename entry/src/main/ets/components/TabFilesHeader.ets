import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import { TransportObject } from "../model/TransportObject";
import LazyDataSource from "../utils/LazyDataSource";
import { Downloads, TransferAction } from "./Downloads";
import { Uploads } from "./Uploads";
import { CloudThemeToken } from "../model/CloudTheme";
import Constant from "../model/Constant";
import { CloudIconButton } from "./CloudIconButton";

@Component
export struct TabFilesHeader {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0
  @Prop isRoot: boolean;
  @Link searchKeyword: string;
  @State showTransport:boolean = false;
  @ObjectLink downloadObjects: LazyDataSource<TransportObject>
  @ObjectLink uploadObjects: LazyDataSource<TransportObject>
  @Prop downloadingCount: number = 0;
  @Prop uploadingCount: number = 0;
  onBackClick?: () => void;
  onTransportClick?: () => void;
  onPersonClick?: () => void;
  onSearchChange?: () => void;
  onDownloadAction?: (object: TransportObject, action: TransferAction) => void;

  @State selectCapsuleOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: $r('app.string.task_download') }, { text: $r('app.string.task_upload') }] as SegmentButtonItemTuple,
    multiply: false,
    backgroundBlurStyle: BlurStyle.BACKGROUND_THICK
  })
  @State selectedIndexes: number[] = [CloudThemeToken.primarySegmentIndex]


  build() {
    Column() {
      Row() {
        Row({ space: CloudThemeToken.filesHeaderGap }) {
          if (!this.isRoot) {
            CloudIconButton({
              icon: $r('app.media.ic_back'),
              iconSize: CloudThemeToken.iconButtonSize,
              iconPadding: CloudThemeToken.filesHeaderBackIconPadding,
              buttonBackground: CloudThemeToken.surface,
              iconColor: CloudThemeToken.textPrimary,
              onAction: () => {
                if (this.onBackClick) {
                  this.onBackClick()
                }
              }
            })
            .transition(TransitionEffect.OPACITY.animation({ duration: CloudThemeToken.filesHeaderTransitionDuration })
              .combine(TransitionEffect.scale({ x: CloudThemeToken.hiddenScale, y: CloudThemeToken.hiddenScale })
                .animation({ duration: CloudThemeToken.filesHeaderTransitionDuration })))
          }

          Search({ value: $$this.searchKeyword, placeholder: $r("app.string.header_search") })
            .searchIcon({ color: CloudThemeToken.textPrimary })
            .backgroundColor(CloudThemeToken.surface)
            .onChange((value: string) => {
              this.searchKeyword = value
              if (this.onSearchChange) {
                this.onSearchChange()
              }
            })
        }
        .width('50%')

        Row({ space: CloudThemeToken.filesHeaderGap }) {
          CloudIconButton({
            icon: $r('app.media.ic_transport'),
            iconSize: CloudThemeToken.iconButtonSize,
            iconPadding: CloudThemeToken.filesHeaderIconPadding,
            buttonBackground: CloudThemeToken.surfaceSubtle,
            iconColor: CloudThemeToken.textPrimary,
            badgeCount: this.downloadingCount + this.uploadingCount,
            onAction: () => {
              this.showTransport = true
              if (this.onTransportClick) {
                this.onTransportClick()
              }
            }
          })
          .bindSheet($$this.showTransport, this.transportBuilder(), {
            showClose: true,
            backgroundColor: CloudThemeToken.surface,
            title: { title: $r('app.string.transport_title') },
            preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
            width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
            onDisappear: () => {
              this.showTransport = false
            }
          })

          CloudIconButton({
            icon: $r('app.media.ic_person'),
            iconSize: CloudThemeToken.iconButtonSize,
            iconPadding: CloudThemeToken.filesHeaderIconPadding,
            buttonBackground: CloudThemeToken.surface,
            iconColor: CloudThemeToken.textPrimary,
            onAction: () => {
              if (this.onPersonClick) {
                this.onPersonClick()
              }
            }
          })
        }
        .width(CloudThemeToken.filesHeaderActionWidth)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(CloudThemeToken.iconButtonSize)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding({ left: CloudThemeToken.filesHeaderPadding, right: CloudThemeToken.filesHeaderPadding })
    .width('100%')
    .height(CloudThemeToken.iconButtonSize)
    .align(Alignment.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder transportTitle(title: ResourceStr) {
    Row() {
      Text(title)
        .fontSize(CloudThemeToken.filesTransportTitleSize)
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
        if (this.selectedIndexes[CloudThemeToken.primarySegmentIndex] == CloudThemeToken.primarySegmentIndex) {
          Downloads({
            downloadObjects: this.downloadObjects,
            onAction: (object: TransportObject, action: TransferAction) => {
              if (this.onDownloadAction) {
                this.onDownloadAction(object, action)
              }
            }
          })
        }
        else {
          Uploads({uploadObjects: this.uploadObjects})
        }
      }
      .width('100%')
      .margin({ top: CloudThemeToken.filesTransportContentTopMargin })
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.background)
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .padding({
      left: CloudThemeToken.filesHeaderPadding,
      right: CloudThemeToken.filesHeaderPadding,
      top: CloudThemeToken.filesHeaderPadding,
      bottom: this.bottomRectHeight + CloudThemeToken.filesTransportPaddingBottom
    })
    .height('100%')
    .width('100%')
    .backgroundColor(CloudThemeToken.background)
  }
}
