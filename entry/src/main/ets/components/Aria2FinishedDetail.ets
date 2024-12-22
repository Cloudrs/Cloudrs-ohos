import { DateUtil } from "@pura/harmony-utils"
import Constant from "../model/Constant"
import { Aria2Files, Aria2Finished, Aria2Status, TaskError } from "../model/net/ApiTypes"
import { CommonUtil } from "../utils/CommonUtil"

@Component
export struct Aria2FinishedDetail {
  @Prop detailData: Aria2Finished
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  onDeleteClick?: () => void

  getErrorInfo() {
    if (this.detailData.task_error != '') {
      let status_error: TaskError = JSON.parse(this.detailData.task_error)
      return `${status_error.msg}:${status_error.error}`
    } else {
      return this.detailData.error
    }
  }

  build() {
    Column({space: 15}){
      Text(this.detailData.name)
        .fontSize(24)
        .wordBreak(WordBreak.BREAK_ALL)
        .fontWeight(FontWeight.Bolder)
        .padding({right: 40})

      Row({space: 10}) {
        Image($r('app.media.ic_bell_fill'))
          .width(20)
          .height(20)
          .fillColor(this.detailData.task_status == Aria2Status.FINISHED ? Color.Green : Color.Red)

        Text(this.detailData.task_status == Aria2Status.FINISHED ?
          $r('app.string.download_finished') : this.getErrorInfo())
          .fontSize(14)
          .fontStyle(this.detailData.task_status == Aria2Status.FINISHED ? FontStyle.Normal : FontStyle.Italic)
          .layoutWeight(1)
          .wordBreak(WordBreak.BREAK_ALL)
          .fontColor(this.detailData.task_status == Aria2Status.FINISHED ? Color.Green : Color.Red)
      }
      .height(40)
      .width('100%')
      .borderRadius(5)
      .padding({left: 10, right: 10})
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .backgroundColor(this.detailData.task_status == Aria2Status.FINISHED ?
        $r("app.color.aria2_status_finished") : $r("app.color.aria2_status_error"))

      Text($r('app.string.task_detail'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      this.taskDetail()

      Text($r('app.string.files_list'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      List({space: 5}) {
        ForEach(this.detailData.files, (item: Aria2Files, index) => {
          this.fileItem(item.path)
        })
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)

      this.detailTool()
    }
    .width('100%')
    .padding({ left: 15, right: 15, top: 25, bottom: this.bottomRectHeight })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(Color.White)
  }

  @Builder taskDetail() {
    Grid() {
      GridItem() {
        this.taskDetailItem($r('app.string.create_date'),
          DateUtil.getFormatDateStr(new Date(this.detailData.create), 'yyyy-MM-dd'),
          $r('app.media.ic_calendar_add'))
      }

      GridItem() {
        this.taskDetailItem($r('app.string.update_date'),
          DateUtil.getFormatDateStr(new Date(this.detailData.update), 'yyyy-MM-dd'),
          $r('app.media.ic_calendar_check'))
      }

      GridItem() {
        this.taskDetailItem($r('app.string.dst_path'),
          this.detailData.dst,
          $r('app.media.ic_folder_fill'))
      }

      GridItem() {
        this.taskDetailItem($r('app.string.total_size'),
          CommonUtil.formatBytes(this.detailData.total, 1),
          $r('app.media.ic_doc_text_fill'))
      }

      GridItem() {
        this.taskDetailItem($r('app.string.node'),
          this.detailData.node,
          $r('app.media.ic_node'))
      }
    }
    .columnsTemplate('1fr 1fr')
    .maxCount(2)
    .columnsGap(10)
    .rowsGap(10)
  }

  @Builder taskDetailItem(title: ResourceStr, content: ResourceStr, icon: Resource) {
    Row() {
      Column({space: 5}) {
        Text(title)
          .fontSize(14)
          .fontColor($r('app.color.common_font_gray'))
        Text(content)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .fontSize(16)
          .fontWeight(FontWeight.Bolder)
          .fontColor(Color.Black)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Image(icon)
        .width(24)
        .height(24)
    }
    .height(70)
    .padding(15)
    .borderRadius(15)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.aria2_default_background'))
  }

  @Builder fileItem(fileName: string) {
    Row() {
      Text(fileName)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .maxLines(2)
        .wordBreak(WordBreak.BREAK_ALL)
        .textOverflow({overflow: TextOverflow.Ellipsis})
    }
    .width('100%')
    .padding(20)
    .borderRadius(15)
    .backgroundColor($r('app.color.aria2_default_background'))
  }

  @Builder detailTool() {
    Row() {
      Blank()
        .layoutWeight(1)

      Image($r('app.media.ic_delete_fill'))
        .width(24)
        .height(24)
        .onClick(() => {
          if (this.onDeleteClick) {
            this.onDeleteClick()
          }
        })
    }
    .width('100%')
    .height(30)
    .padding({ left: 10, right: 10, bottom: 20 })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

}