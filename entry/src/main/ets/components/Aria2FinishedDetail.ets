import Constant from "../model/Constant"
import { CloudLayoutMode, CloudThemeToken } from "../model/CloudTheme"
import { Aria2Files, Aria2Finished, Aria2Status, TaskError } from "../model/net/ApiTypes"
import { CommonUtil } from "../utils/CommonUtil"
import { DateFormatUtil } from "../utils/DateFormatUtil"

@Component
export struct Aria2FinishedDetail {
  @Prop detailData: Aria2Finished
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State detailGridWidth: number = 0
  onDeleteClick?: () => void

  getTaskName(): string {
    if (!this.detailData.name || this.detailData.name.trim().length === 0 || this.detailData.name === '.') {
      return this.detailData.gid
    }
    return this.detailData.name
  }

  getErrorInfo() {
    if (this.detailData.task_error && this.detailData.task_error.trim().length > 0) {
      try {
        let statusError: TaskError = JSON.parse(this.detailData.task_error)
        return `${statusError.msg}:${statusError.error}`
      } catch (e) {
        return this.detailData.task_error
      }
    }

    if (this.detailData.error && this.detailData.error.trim().length > 0) {
      try {
        let error: TaskError = JSON.parse(this.detailData.error)
        return `${error.msg}:${error.error}`
      } catch (e) {
        return this.detailData.error
      }
    }

    return '任务执行失败'
  }

  getDetailGridColumns(): number {
    let layoutMode = CloudThemeToken.getLayoutMode(this.detailGridWidth)
    if (layoutMode === CloudLayoutMode.WIDE) {
      return 3
    }
    if (layoutMode === CloudLayoutMode.TABLET) {
      return 2
    }
    return this.detailGridWidth >= CloudThemeToken.twoColumnBreakpoint ? 2 : 1
  }

  getDetailGridColumnsTemplate(): string {
    let columns = this.getDetailGridColumns()
    let templates: string[] = []
    for (let index = 0; index < columns; index++) {
      templates.push('1fr')
    }
    return templates.join(' ')
  }

  build() {
    Column({space: 15}){
      Text(this.getTaskName())
        .fontSize(24)
        .wordBreak(WordBreak.BREAK_ALL)
        .fontWeight(FontWeight.Bolder)
        .fontColor(CloudThemeToken.textPrimary)
        .padding({right: 40})

      Row({space: 10}) {
        Image($r('app.media.ic_bell_fill'))
          .width(20)
          .height(20)
          .fillColor(this.detailData.task_status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)

        Text(this.detailData.task_status == Aria2Status.FINISHED ?
          $r('app.string.download_finished') : this.getErrorInfo())
          .fontSize(14)
          .fontStyle(this.detailData.task_status == Aria2Status.FINISHED ? FontStyle.Normal : FontStyle.Italic)
          .layoutWeight(1)
          .wordBreak(WordBreak.BREAK_ALL)
          .fontColor(this.detailData.task_status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)
      }
      .height(40)
      .width('100%')
      .borderRadius(CloudThemeToken.cardRadius)
      .padding({left: 10, right: 10})
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .backgroundColor(this.detailData.task_status == Aria2Status.FINISHED ?
        CloudThemeToken.successSoft : CloudThemeToken.dangerSoft)

      Text($r('app.string.task_detail'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)

      this.taskDetail()

      Text($r('app.string.files_list'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)

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
    .padding({ left: CloudThemeToken.pagePadding, right: CloudThemeToken.pagePadding, top: 25, bottom: this.bottomRectHeight })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder taskDetail() {
    Grid() {
      GridItem() {
        this.taskDetailItem($r('app.string.create_date'),
          DateFormatUtil.format(new Date(this.detailData.create), 'yyyy-MM-dd'),
          $r('app.media.ic_calendar_add'))
      }

      GridItem() {
        this.taskDetailItem($r('app.string.update_date'),
          DateFormatUtil.format(new Date(this.detailData.update), 'yyyy-MM-dd'),
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
    .columnsTemplate(this.getDetailGridColumnsTemplate())
    .maxCount(this.getDetailGridColumns())
    .columnsGap(10)
    .rowsGap(10)
    .width('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      let width = Number(newArea.width)
      if (!Number.isNaN(width) && Math.abs(width - this.detailGridWidth) >= 1) {
        this.detailGridWidth = width
      }
    })
  }

  @Builder taskDetailItem(title: ResourceStr, content: ResourceStr, icon: Resource) {
    Row() {
      Column({space: 5}) {
        Text(title)
          .fontSize(14)
          .fontColor(CloudThemeToken.textSecondary)
        Text(content)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .fontSize(16)
          .fontWeight(FontWeight.Bolder)
          .fontColor(CloudThemeToken.textPrimary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Image(icon)
        .width(24)
        .height(24)
        .fillColor(CloudThemeToken.primary)
    }
    .height(70)
    .padding(15)
    .borderRadius(CloudThemeToken.cardRadius)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder fileItem(fileName: string) {
    Row() {
      Text(fileName)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .maxLines(2)
        .wordBreak(WordBreak.BREAK_ALL)
        .textOverflow({overflow: TextOverflow.Ellipsis})
    }
    .width('100%')
    .padding(20)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder detailTool() {
    Row() {
      Blank()
        .layoutWeight(1)

      Image($r('app.media.ic_delete_fill'))
        .width(24)
        .height(24)
        .fillColor(CloudThemeToken.danger)
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
