import { CloudThemeToken } from "../model/CloudTheme"
import { DetailData } from "../model/DetailData"
import { CommonUtil } from "../utils/CommonUtil"
import { DateFormatUtil } from "../utils/DateFormatUtil"

@Component
export struct DetailSheet {
  @Prop detailData: DetailData

  private getTypeText(): ResourceStr {
    return this.detailData.isDir ? $r('app.string.detail_dir_name') : $r('app.string.detail_filename')
  }

  private getPolicyText(): ResourceStr {
    return this.detailData.detailInfo.policy === '' ? $r('app.string.detail_policy_default') :
    this.detailData.detailInfo.policy
  }

  private formatTime(value: string): string {
    if (value.length === 0) {
      return '-'
    }
    let date = new Date(value)
    if (Number.isNaN(date.getTime())) {
      return value
    }
    return DateFormatUtil.format(date)
  }

  build() {
    Column({ space: CloudThemeToken.detailSheetGap }) {
      this.header()
      this.summary()
      this.detailList()
      Blank().height(CloudThemeToken.detailSpacerHeight)
    }
    .padding({
      left: CloudThemeToken.detailSheetHorizontalPadding,
      right: CloudThemeToken.detailSheetHorizontalPadding,
      bottom: CloudThemeToken.detailSheetBottomPadding
    })
    .width('100%')
    .constraintSize({ minHeight: CloudThemeToken.detailSheetMinHeight })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder header() {
    Row() {
      Text($r('app.string.detail_title'))
        .fontSize(CloudThemeToken.textSizeHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(CloudThemeToken.detailSheetHeaderHeight)
    .alignItems(VerticalAlign.Center)
  }

  @Builder summary() {
    Row({ space: CloudThemeToken.detailSheetSummaryGap }) {
      Stack() {
        Image(this.detailData.isDir ? $r('app.media.folder_fill') : $r('app.media.ic_doc_text_fill'))
          .width(CloudThemeToken.detailSheetIconSize)
          .height(CloudThemeToken.detailSheetIconSize)
          .objectFit(ImageFit.Contain)
      }
      .width(CloudThemeToken.detailSheetIconBoxSize)
      .height(CloudThemeToken.detailSheetIconBoxSize)
      .borderRadius(CloudThemeToken.cardRadius)
      .backgroundColor(CloudThemeToken.primarySoft)

      Column({ space: CloudThemeToken.detailSheetTextGap }) {
        Text(this.detailData.name)
          .fontSize(CloudThemeToken.textSizeLargePlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(2)
          .wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detailData.isDir ? '文件夹' : CommonUtil.formatBytes(this.detailData.detailInfo.size))
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(CloudThemeToken.detailSheetSummaryPadding)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder detailList() {
    Column({ space: CloudThemeToken.zero }) {
      this.commonRow(this.getTypeText(), this.detailData.name)
      this.commonDivider()
      this.commonRow($r('app.string.detail_size'), CommonUtil.formatBytes(this.detailData.detailInfo.size))
      this.commonDivider()
      this.commonRow($r('app.string.detail_policy'), this.getPolicyText())

      if (this.detailData.isDir) {
        this.commonDivider()
        this.commonRow($r('app.string.detail_include_dirs'), this.detailData.detailInfo.child_folder_num.toFixed(0))
        this.commonDivider()
        this.commonRow($r("app.string.detail_include_files"), this.detailData.detailInfo.child_file_num.toFixed(0))
      }

      this.commonDivider()
      this.commonRow($r('app.string.detail_created_at'), this.formatTime(this.detailData.detailInfo.created_at))
      this.commonDivider()
      this.commonRow($r('app.string.detail_updated_at'), this.formatTime(this.detailData.detailInfo.updated_at))
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.detailSheetListHorizontalPadding,
      right: CloudThemeToken.detailSheetListHorizontalPadding
    })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
  }

  @Builder commonRow(title: ResourceStr, value: ResourceStr) {
    Row({ space: CloudThemeToken.detailSheetRowGap }) {
      Text(title)
        .fontColor(CloudThemeToken.textSecondary)
        .fontSize(CloudThemeToken.textSizeBody)
        .maxLines(1)
      Text(value)
        .fontColor(CloudThemeToken.textPrimary)
        .fontSize(CloudThemeToken.textSizeBody)
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.MARQUEE })
        .textAlign(TextAlign.End)
        .layoutWeight(1)
    }
    .height(CloudThemeToken.detailSheetRowHeight)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder commonDivider() {
    Divider()
      .color(CloudThemeToken.line)
      .strokeWidth('1px')
  }
}
