
import { DateUtil } from "@pura/harmony-utils";
import { ObjectInfo } from "../model/net/ApiTypes";
import { LengthMetrics } from "@kit.ArkUI";

@Extend(Column)
function itemStyle() {
  .width('100%')
  .borderRadius(7)
  .alignItems(HorizontalAlign.Start)
  .justifyContent(FlexAlign.Center)
  .backgroundColor(Color.White)
}

@Extend(Text)
function itemFileNameStyle() {
  .fontSize(16)
  .fontWeight(FontWeight.Medium)
  .wordBreak(WordBreak.BREAK_ALL)
  .maxLines(1)
  .textOverflow({overflow: TextOverflow.Ellipsis})
  .width('100%')
}

@Extend(Text)
function itemFileDateStyle() {
  .fontSize(12)
  .fontColor($r('app.color.light_gray'))
}

@Component
export struct FileItem {
  @Prop item: ObjectInfo
  @Consume thumbImage: Map<string, PixelMap>
  onItemClick?: (item: ObjectInfo) => void

  getThumbData(id: string): PixelMap|undefined {
    if (this.thumbImage.has(id)) {
      return this.thumbImage.get(id)
    }
    return undefined
  }

  build() {
    if (this.item.type === 'dir') {
      this.directoryItem(this.item)
    } else if (this.item.type === 'file') {
      this.fileItem(this.item)
    }
  }

  @Builder directoryItem(item: ObjectInfo) {
    Column() {
      Row({ space: 10 }) {
        Image($r('app.media.ic_folder_fill'))
          .width(40)
          .height(40)
          .fillColor($r('app.color.file_folder'))

        Column({ space: 3 }) {
          Text(item.name)
            .itemFileNameStyle()

          Text(DateUtil.getFormatDateStr(new Date(item.date), 'yyyy-MM-dd'))
            .itemFileDateStyle()
        }
        .layoutWeight(1)
        .height(40)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .height(60)
    .padding({left: 10, right: 10})
    .itemStyle()
    .bindContextMenu(this.fileMenu(), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [1.0, 0.95]
      }
    })
    .onClick(async () => {
      if (this.onItemClick) {
        this.onItemClick(item)
      }
    })
  }

  @Builder fileItem(item: ObjectInfo) {
    Column({space: 10}) {
      Text() {
        ImageSpan(item.thumb ? this.getThumbData(item.id) : $r('app.media.ic_doc_text_fill'))
          .objectFit(item.thumb ? ImageFit.Cover : ImageFit.CENTER)
      }
      .textAlign(TextAlign.Center)
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.file_icon_background'))

      Column({ space: 3 }) {
        Text(item.name)
          .itemFileNameStyle()

        Text(DateUtil.getFormatDateStr(new Date(item.date), 'yyyy-MM-dd'))
          .itemFileDateStyle()
      }
      .height(40)
      .padding({left: 10, right: 10})
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .bindContextMenu(this.fileMenu(), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [1.0, 0.95]
      }
    })
    .height(160)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .itemStyle()
    .onClick(() => {
      if (this.onItemClick) {
        this.onItemClick(item)
      }
    })
  }

  @Builder fileMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.dir_enter') })
        MenuItem({ content: $r('app.string.file_details') })
        MenuItem({ content: $r('app.string.rename') })
        MenuItem({ content: $r('app.string.copy') })
        MenuItem({ content: $r('app.string.move') })
        MenuItem({ content: $r('app.string.cloud_share') })
      }
      MenuItemGroup() {
        MenuItem({content: $r('app.string.delete')})
          .contentFontColor(Color.Red)
      }
    }
    .width(250)
    .menuItemDivider({
      strokeWidth: LengthMetrics.px(1),
      color: $r("app.color.menu_divider_line"),
      startMargin: LengthMetrics.px(0),
      endMargin: LengthMetrics.px(0),
    })
    .menuItemGroupDivider({
      color: $r("app.color.menu_divider_group_line"),
      strokeWidth: LengthMetrics.px(15),
      startMargin: LengthMetrics.px(0),
      endMargin:LengthMetrics.px(0)
    })
    .backgroundColor($r('app.color.file_menu_background'))
  }
}