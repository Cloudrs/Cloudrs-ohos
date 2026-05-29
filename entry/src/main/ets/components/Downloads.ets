import { EmptyState } from "./EmptyState"
import { FileModelState } from "../model/FileModel"
import { CloudThemeToken } from "../model/CloudTheme"
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
        List({ space: CloudThemeToken.transferListGap }) {
          LazyForEach(this.downloadObjects, (item: TransportObject, index) => {
            this.downloadItem(item)
          }, (item: TransportObject, index) => item.item.id + index)
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder noItem() {
    EmptyState({
      icon: $r('app.media.ic_arrowshape_down'),
      title: $r('app.string.no_download_task'),
      description: '下载任务会显示在这里。'
    })
  }

  getDownloadIcon(state: FileModelState) {
    switch (state){
      case FileModelState.COMPLETED:
        return $r('app.media.ic_checkmark_circle')
      case FileModelState.FAILED:
        return $r('app.media.ic_xmark_circle_fill')
      default :
        return $r('app.media.ic_arrowshape_down')
    }
  }

  getStateColor(state: FileModelState): ResourceColor {
    switch (state) {
      case FileModelState.COMPLETED:
        return CloudThemeToken.success
      case FileModelState.FAILED:
        return CloudThemeToken.danger
      default:
        return CloudThemeToken.primary
    }
  }

  @Builder downloadItem(object: TransportObject) {
    Row({ space: CloudThemeToken.transferItemGap }) {
      Image(CommonUtil.getFileIconInfo(object.item.name).icon)
        .width(CloudThemeToken.transferFileIconSize)
        .height(CloudThemeToken.transferFileIconSize)

      Column({ space: CloudThemeToken.transferTextGap }) {
        Text(object.item.name)
          .fontSize(CloudThemeToken.transferNameSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .ellipsisMode(EllipsisMode.CENTER)

        Row({ space: CloudThemeToken.transferMetaGap }) {
          Image(this.getDownloadIcon(object.state))
            .width(CloudThemeToken.transferStateIconSize)
            .height(CloudThemeToken.transferStateIconSize)
            .fillColor(this.getStateColor(object.state))

          if (object.state == FileModelState.RUNNING) {
            Text(CommonUtil.formatBytes(object.speed, 1) + '/s')
              .fontSize(CloudThemeToken.transferMetaSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(CloudThemeToken.textSecondary)
              .margin({ right: CloudThemeToken.transferSpeedRightMargin })
          }

          Text(`${CommonUtil.formatBytes(object.trans, 1)}/${CommonUtil.formatBytes(object.total, 1)}`)
            .fontSize(CloudThemeToken.transferMetaSize)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)

      Progress({value: object.progress, total: 100, type: ProgressType.Capsule})
        .style({
          showDefaultPercentage: true
        })
        .width(CloudThemeToken.transferProgressWidth)
        .height(CloudThemeToken.transferProgressHeight)
    }
    .width('100%')
    .padding(CloudThemeToken.transferItemPadding)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
