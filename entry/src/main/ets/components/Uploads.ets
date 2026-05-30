import { EmptyState } from "./EmptyState"
import { FileModelState } from "../model/FileModel"
import { CloudThemeToken } from "../model/CloudTheme"
import { TransportObject } from "../model/TransportObject"
import { CommonUtil } from "../utils/CommonUtil"
import LazyDataSource from "../utils/LazyDataSource"
import { TransferStateUtil } from "../utils/TransferStateUtil"

const TAG = 'Uploads'

@Component
export struct Uploads {
  @ObjectLink uploadObjects: LazyDataSource<TransportObject>

  build() {
    Column() {
      if (this.uploadObjects.totalCount() == CloudThemeToken.zero) {
        this.noItem()
      } else {
        List({ space: CloudThemeToken.transferListGap }) {
          LazyForEach(this.uploadObjects, (item: TransportObject, index) => {
            this.uploadItem(item)
          }, (item: TransportObject, index) => item.path + index)
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
      icon: $r('app.media.ic_arrowshape_up'),
      title: $r('app.string.no_upload_task'),
      description: '上传任务会显示在这里。'
    })
  }

  getUploadIcon(state: FileModelState) {
    return TransferStateUtil.getStateIcon(state, $r('app.media.ic_arrowshape_up'))
  }

  getStateColor(state: FileModelState): ResourceColor {
    return TransferStateUtil.getStateColor(state)
  }

  @Builder uploadItem(object: TransportObject) {
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
          Image(this.getUploadIcon(object.state))
            .width(CloudThemeToken.transferStateIconSize)
            .height(CloudThemeToken.transferStateIconSize)
            .fillColor(this.getStateColor(object.state))

          Text(this.getStateText(object))
            .fontSize(CloudThemeToken.transferMetaSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getStateColor(object.state))
            .margin({ right: CloudThemeToken.transferSpeedRightMargin })

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

      Progress({value: object.progress, total: CloudThemeToken.percentageFull, type: ProgressType.Capsule})
        .style({
          showDefaultPercentage: true
        })
        .width(CloudThemeToken.transferProgressWidth)
        .height(CloudThemeToken.transferProgressHeight)
        .color(this.getStateColor(object.state))
        .backgroundColor(CloudThemeToken.surfaceSubtle)
    }
    .width('100%')
    .padding(CloudThemeToken.transferItemPadding)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  getStateText(object: TransportObject): string {
    return TransferStateUtil.getCommonStateText(object.state, '上传失败') ?? this.getRunningText(object)
  }

  private getRunningText(object: TransportObject): string {
    if (object.statusText.length > 0) {
      return object.statusText
    }
    if (TransferStateUtil.isServerProcessing(object)) {
      return '服务端处理中'
    }
    return TransferStateUtil.getSpeedText(object)
  }
}
