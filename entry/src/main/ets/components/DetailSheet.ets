import { DateUtil } from "@pura/harmony-utils"
import { CloudThemeToken } from "../model/CloudTheme"
import { DetailData } from "../model/DetailData"
import { CommonUtil } from "../utils/CommonUtil"

@Component
export struct DetailSheet {
  @Prop detailData: DetailData

  build() {
    Column({ space: 0 }) {
      Row() {
        Text($r('app.string.detail_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)

      this.commonRow(this.detailData.isDir ? $r('app.string.detail_dir_name') : $r('app.string.detail_filename'), this.detailData.name)
      this.commonDivider()

      this.commonRow($r('app.string.detail_size'), CommonUtil.formatBytes(this.detailData.detailInfo.size))
      this.commonDivider()

      this.commonRow($r('app.string.detail_policy'),
        this.detailData.detailInfo.policy === '' ? $r('app.string.detail_policy_default') : this.detailData.detailInfo.policy)
      this.commonDivider()

      if (this.detailData.isDir) {
        this.commonRow($r('app.string.detail_include_dirs'), this.detailData.detailInfo.child_folder_num.toFixed(0))
        this.commonDivider()

        this.commonRow($r("app.string.detail_include_files"), this.detailData.detailInfo.child_file_num.toFixed(0))
        this.commonDivider()
      }

      this.commonRow($r('app.string.detail_created_at'), DateUtil.getFormatDateStr(new Date(this.detailData.detailInfo.created_at)))
      this.commonDivider()

      this.commonRow($r('app.string.detail_updated_at'), DateUtil.getFormatDateStr(new Date(this.detailData.detailInfo.updated_at)))
      this.commonDivider()

      Blank().height(8)
    }
    .padding({ left: 20, right: 20, bottom: 20 })
    .width('100%')
    .constraintSize({ minHeight: 360 })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder commonRow(title: string|Resource, value: string|Resource) {
    Row() {
      Text(title)
        .fontColor(CloudThemeToken.textSecondary)
        .fontSize(16)
      Text(value)
        .fontColor(CloudThemeToken.textPrimary)
        .fontSize(14)
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(1)
        .textOverflow({overflow: TextOverflow.MARQUEE})
        .textAlign(TextAlign.End)
        .layoutWeight(1)
    }
    .height(50)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder commonDivider() {
    Divider().color(CloudThemeToken.line).strokeWidth('1px')
  }
}
