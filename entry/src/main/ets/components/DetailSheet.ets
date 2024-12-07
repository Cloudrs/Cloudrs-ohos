import { DateUtil } from "@pura/harmony-utils"
import Constant from "../model/Constant"
import { DetailData } from "../model/DetailData"
import { formatBytes } from "../utils/Common"

@Component
export struct DetailSheet {
  @Prop detailData: DetailData
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;

  build() {
    Column() {
      this.commonRow(this.detailData.isDir ? $r('app.string.detail_dir_name') : $r('app.string.detail_filename'), this.detailData.name)
      this.commonDivider()

      this.commonRow($r('app.string.detail_size'), formatBytes(this.detailData.detailInfo.size))
      this.commonDivider()

      this.commonRow($r('app.string.detail_policy'),
        this.detailData.detailInfo.policy === '' ? $r('app.string.detail_policy_default') : this.detailData.detailInfo.policy)
      this.commonDivider()

      if (this.detailData.isDir) {
        this.commonRow($r('app.string.detail_include_dirs'), this.detailData.detailInfo.child_folder_num.toFixed(0))
        this.commonDivider()

        this.commonRow($r('app.string.details_include_files'), this.detailData.detailInfo.child_file_num.toFixed(0))
        this.commonDivider()
      }

      this.commonRow($r('app.string.detail_created_at'), DateUtil.getFormatDateStr(new Date(this.detailData.detailInfo.created_at)))
      this.commonDivider()

      this.commonRow($r('app.string.detail_updated_at'), DateUtil.getFormatDateStr(new Date(this.detailData.detailInfo.updated_at)))
      this.commonDivider()

      Blank().height(this.bottomRectHeight)
    }
    .padding({left: 20, right: 20, bottom: 20 })
    .width('100%')
  }

  @Builder commonRow(title: string|Resource, value: string|Resource) {
    Row() {
      Text(title)
        .fontColor(Color.Gray)
        .fontSize(16)
      Text(value)
        .fontColor(Color.Black)
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
    Divider().color($r('app.color.default_line_color')).strokeWidth('2px')
  }
}