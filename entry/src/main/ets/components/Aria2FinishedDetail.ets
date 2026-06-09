import Constant from "../model/Constant"
import { CloudThemeToken } from "../model/CloudTheme"
import { Aria2Files, Aria2Finished, Aria2Status, TaskError } from "../model/net/ApiTypes"
import { CommonUtil } from "../utils/CommonUtil"
import { DateFormatUtil } from "../utils/DateFormatUtil"
import { CloudIconButton } from "./CloudIconButton"

@Component
export struct Aria2FinishedDetail {
  @Prop detailData: Aria2Finished
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State detailGridWidth: number = 0
  onDeleteClick?: () => void
  onClose?: () => void

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
    // 这里用的是内容容器宽度阈值，跟窗口断点解耦
    if (this.detailGridWidth >= CloudThemeToken.wideBreakpoint) {
      return CloudThemeToken.aria2DetailWideColumns
    }
    if (this.detailGridWidth >= CloudThemeToken.tabletBreakpoint) {
      return CloudThemeToken.aria2DetailTabletColumns
    }
    return this.detailGridWidth >= CloudThemeToken.twoColumnBreakpoint ?
      CloudThemeToken.aria2DetailMediumColumns : CloudThemeToken.aria2DetailPhoneColumns
  }

  getDetailGridColumnsTemplate(): string {
    let columns = this.getDetailGridColumns()
    let templates: string[] = []
    for (let index = 0; index < columns; index++) {
      templates.push(CloudThemeToken.singleColumnTemplate)
    }
    return templates.join(' ')
  }

  build() {
    Column({ space: CloudThemeToken.aria2DetailGap }){
      Row({ space: CloudThemeToken.spacingCard }) {
        Text(this.getTaskName())
          .fontSize(CloudThemeToken.aria2DetailTitleSize)
          .wordBreak(WordBreak.BREAK_ALL)
          .fontWeight(FontWeight.Bolder)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        CloudIconButton({
          icon: $r('app.media.ic_xmark_bold'),
          buttonSize: CloudThemeToken.iconBoxSm,
          iconSize: CloudThemeToken.sheetActionIconSize,
          buttonBackground: CloudThemeToken.surfaceSubtle,
          iconColor: CloudThemeToken.textSecondary,
          onAction: () => {
            this.onClose?.()
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: CloudThemeToken.aria2DetailStatusGap }) {
        Image($r('app.media.ic_bell_fill'))
          .width(CloudThemeToken.aria2DetailStatusIconSize)
          .height(CloudThemeToken.aria2DetailStatusIconSize)
          .fillColor(this.detailData.task_status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)

        Text(this.detailData.task_status == Aria2Status.FINISHED ?
          $r('app.string.download_finished') : this.getErrorInfo())
          .fontSize(CloudThemeToken.aria2DetailStatusTextSize)
          .fontStyle(this.detailData.task_status == Aria2Status.FINISHED ? FontStyle.Normal : FontStyle.Italic)
          .layoutWeight(1)
          .wordBreak(WordBreak.BREAK_ALL)
          .fontColor(this.detailData.task_status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)
      }
      .height(CloudThemeToken.aria2DetailStatusHeight)
      .width('100%')
      .borderRadius(CloudThemeToken.cardRadius)
      .padding({
        left: CloudThemeToken.aria2DetailStatusHorizontalPadding,
        right: CloudThemeToken.aria2DetailStatusHorizontalPadding
      })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .backgroundColor(this.detailData.task_status == Aria2Status.FINISHED ?
        CloudThemeToken.successSoft : CloudThemeToken.dangerSoft)

      Scroll() {
        Column({ space: CloudThemeToken.aria2DetailGap }) {
          Text($r('app.string.task_detail'))
            .fontSize(CloudThemeToken.aria2DetailSectionTitleSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)

          this.taskDetail()

          Text($r('app.string.files_list'))
            .fontSize(CloudThemeToken.aria2DetailSectionTitleSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)

          Column({ space: CloudThemeToken.aria2DetailFileListGap }) {
            ForEach(this.detailData.files, (item: Aria2Files) => {
              this.fileItem(item.path)
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      this.detailTool()
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.pagePadding,
      right: CloudThemeToken.pagePadding,
      top: CloudThemeToken.aria2DetailSheetTopPadding,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
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
    .columnsGap(CloudThemeToken.aria2DetailGridGap)
    .rowsGap(CloudThemeToken.aria2DetailGridGap)
    .width('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      let width = Number(newArea.width)
      if (!Number.isNaN(width) && Math.abs(width - this.detailGridWidth) >= CloudThemeToken.layoutChangeThreshold) {
        this.detailGridWidth = width
      }
    })
  }

  @Builder taskDetailItem(title: ResourceStr, content: ResourceStr, icon: Resource) {
    Row() {
      Column({ space: CloudThemeToken.aria2DetailCardTextGap }) {
        Text(title)
          .fontSize(CloudThemeToken.aria2DetailCardTitleSize)
          .fontColor(CloudThemeToken.textSecondary)
        Text(content)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .fontSize(CloudThemeToken.aria2DetailCardContentSize)
          .fontWeight(FontWeight.Bolder)
          .fontColor(CloudThemeToken.textPrimary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Image(icon)
        .width(CloudThemeToken.aria2DetailCardIconSize)
        .height(CloudThemeToken.aria2DetailCardIconSize)
        .fillColor(CloudThemeToken.primary)
    }
    .height(CloudThemeToken.aria2DetailCardHeight)
    .padding(CloudThemeToken.aria2DetailCardPadding)
    .borderRadius(CloudThemeToken.cardRadius)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder fileItem(fileName: string) {
    Row() {
      Text(fileName)
        .fontSize(CloudThemeToken.aria2DetailFileTextSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .maxLines(2)
        .wordBreak(WordBreak.BREAK_ALL)
        .textOverflow({overflow: TextOverflow.Ellipsis})
    }
    .width('100%')
    .padding(CloudThemeToken.aria2DetailFilePadding)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder detailTool() {
    Row() {
      Blank()
        .layoutWeight(1)

      Image($r('app.media.ic_delete_fill'))
        .width(CloudThemeToken.aria2DetailToolIconSize)
        .height(CloudThemeToken.aria2DetailToolIconSize)
        .fillColor(CloudThemeToken.danger)
        .onClick(() => {
          if (this.onDeleteClick) {
            this.onDeleteClick()
          }
        })
    }
    .width('100%')
    .height(CloudThemeToken.aria2DetailToolHeight)
    .padding({
      left: CloudThemeToken.aria2DetailToolHorizontalPadding,
      right: CloudThemeToken.aria2DetailToolHorizontalPadding,
      bottom: CloudThemeToken.aria2DetailToolBottomPadding
    })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

}
