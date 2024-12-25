import { ObjectInfo } from "../model/net/ApiTypes"
import { TransportObject } from "../model/TransportObject"
import { CommonUtil } from "../utils/CommonUtil"
import LazyDataSource from "../utils/LazyDataSource"

const TAG = 'Downloads'

@Component
export struct Downloads {
  @ObjectLink downloadObjects: LazyDataSource<TransportObject>

  build() {
    Column() {
      if (this.downloadObjects.totalCount() == 0) {
        this.noItem()
      } else {
        List({space: 10}) {
          LazyForEach(this.downloadObjects, (item: TransportObject, index) => {
            this.downloadItem(item)
          }, (item: TransportObject, index) => item.item.id + index)
        }
        .width('100%')
        .height('100%')
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r('app.color.sheet_default_background'))
  }

  @Builder noItem() {
    Row() {
      Text($r('app.string.no_download_task'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.aria2_no_task_font'))
    }
    .height(80)
    .width('100%')
    .borderRadius(10)
    .padding(10)
    .backgroundColor($r("app.color.aria2_default_background"))
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder downloadItem(object: TransportObject) {
    Row({space: 10}) {
      Image(CommonUtil.getFileIconInfo(object.item.name).icon).width(40).height(40)

      Column({space: 10}) {
        Text(object.item.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .ellipsisMode(EllipsisMode.CENTER)

        Row({space: 10}) {
          Image($r('app.media.ic_arrowshape_down'))
            .width(12)
            .height(12)
            .fillColor(Color.Black)
          Text(CommonUtil.formatBytes(object.speed, 1)+'/s')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
          Text(`${CommonUtil.formatBytes(object.trans, 1)}/${CommonUtil.formatBytes(object.total, 1)}`)
            .fontSize(12)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
      .layoutWeight(1)

      Progress({value: object.progress, total: 100, type: ProgressType.Capsule})
        .style({
          showDefaultPercentage: true
        })
        .width(60)
        .height(30)
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor($r("app.color.aria2_default_background"))
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}