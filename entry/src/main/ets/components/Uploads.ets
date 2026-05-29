import { EmptyState } from "./EmptyState"
import { FileModelState } from "../model/FileModel"
import { CloudThemeToken } from "../model/CloudTheme"
import { ObjectInfo } from "../model/net/ApiTypes"
import { TransportObject } from "../model/TransportObject"
import { CommonUtil } from "../utils/CommonUtil"
import LazyDataSource from "../utils/LazyDataSource"

const TAG = 'Uploads'

@Component
export struct Uploads {
  @ObjectLink uploadObjects: LazyDataSource<TransportObject>

  build() {
    Column() {
      if (this.uploadObjects.totalCount() == 0) {
        this.noItem()
      } else {
        List({space: 10}) {
          LazyForEach(this.uploadObjects, (item: TransportObject, index) => {
            this.uploadItem(item)
          }, (item: TransportObject, index) => item.path + index)
        }
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
      icon: $r('app.media.ic_arrowshape_up'),
      title: $r('app.string.no_upload_task'),
      description: '上传任务会显示在这里。'
    })
  }

  getUploadIcon(state: FileModelState) {
    switch (state){
      case FileModelState.COMPLETED:
        return $r('app.media.ic_checkmark_circle')
      case FileModelState.FAILED:
        return $r('app.media.ic_xmark_circle_fill')
      default :
        return $r('app.media.ic_arrowshape_up')
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

  @Builder uploadItem(object: TransportObject) {
    Row({space: 10}) {
      Image(CommonUtil.getFileIconInfo(object.item.name).icon)
        .width(CloudThemeToken.transferFileIconSize)
        .height(CloudThemeToken.transferFileIconSize)

      Column({space: 8}) {
        Text(object.item.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .ellipsisMode(EllipsisMode.CENTER)

        Row({space: 5}) {
          Image(this.getUploadIcon(object.state))
            .width(CloudThemeToken.transferStateIconSize)
            .height(CloudThemeToken.transferStateIconSize)
            .fillColor(this.getStateColor(object.state))

          if (object.state == FileModelState.RUNNING) {
            Text(this.getRunningText(object))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(CloudThemeToken.textSecondary)
              .margin({right: 10})
          }

          Text(`${CommonUtil.formatBytes(object.trans, 1)}/${CommonUtil.formatBytes(object.total, 1)}`)
            .fontSize(12)
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
    .padding(10)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  getRunningText(object: TransportObject): string {
    if (object.statusText.length > 0) {
      return object.statusText
    }
    if (object.progress >= 99 && object.trans >= object.total) {
      return '服务端处理中'
    }
    return CommonUtil.formatBytes(object.speed, 1) + '/s'
  }
}
