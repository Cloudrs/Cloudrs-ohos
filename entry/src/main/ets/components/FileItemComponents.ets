import { HMRouterMgr } from "@hadss/hmrouter";
import { DateUtil } from "@pura/harmony-utils";
import { ObjectInfo } from "../model/net/ApiTypes";

@Extend(Column)
function itemStyle() {
  .borderRadius(7)
  .alignItems(HorizontalAlign.Start)
  .justifyContent(FlexAlign.Center)
  .backgroundColor(Color.White)
}

@Component
export struct FileItemComponents {
  @Prop item: ObjectInfo;

  build() {
    if (this.item.type === 'dir') {
      this.directoryItem()
    } else if (this.item.type === 'file') {
      this.fileItem()
    }
  }

  @Builder
  directoryItem() {
    Column() {
      Row({ space: 10 }) {
        Image($r('app.media.ic_folder_fill'))
          .width(40)
          .height(40)
          .fillColor($r('app.color.file_folder'))

        Column({ space: 3 }) {
          Text(this.item.name)
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(DateUtil.getFormatDateStr(new Date(this.item.date), 'yyyy-MM-dd'))
            .fontSize(12)
            .fontColor($r('app.color.light_gray'))
        }
        .layoutWeight(1)
        .height(40)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height(60)
    .padding({left: 10, right: 10})
    .itemStyle()
    .onClick(() => {

    })
  }

  @Builder
  fileItem() {
    Column({space: 10}) {
      Text() {
        ImageSpan($r('app.media.ic_doc_text_fill'))
          .width(40)
          .height(40)
      }
      .textAlign(TextAlign.Center)
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.file_icon_background'))

      Column({ space: 3 }) {
        Text(this.item.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .width('100%')

        Text(DateUtil.getFormatDateStr(new Date(this.item.date), 'yyyy-MM-dd'))
          .fontSize(12)
          .fontColor($r('app.color.light_gray'))
      }
      .height(40)
      .padding({left: 10, right: 10})
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(160)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .itemStyle()
    .onClick(() => {

    })
  }
}