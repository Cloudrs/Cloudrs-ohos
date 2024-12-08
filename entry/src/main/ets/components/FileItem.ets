
import { DateUtil } from "@pura/harmony-utils";
import { ObjectInfo } from "../model/net/ApiTypes";
import { LengthMetrics, LengthUnit } from "@kit.ArkUI";
import { FileMenuType } from "../model/FileMenuType";
import { image } from "@kit.ImageKit";
import LazyDataSource from "../utils/LazyDataSource";

const TAG = 'TabItem';

@Extend(Column)
function itemStyle() {
  .width('100%')
  .borderRadius(10)
  .clip(true)
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
  @Prop index: number
  @Prop item: ObjectInfo
  @Consume thumbImage: Map<string, PixelMap>
  onMenuClick?: (item: ObjectInfo, type: FileMenuType) => void

  aboutToAppear(): void {
    console.debug(TAG, 'aboutToAppear')
  }

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
          .draggable(false)

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
    .bindContextMenu(this.fileMenu(item), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [1.0, 0.95]
      }
    })
  }

  @Builder fileItem(item: ObjectInfo) {
    Column({space: 10}) {
      Text() {
        ImageSpan(this.getThumbData(item.id) ?? $r('app.media.ic_doc_text_fill'))
          .objectFit(this.getThumbData(item.id) ? ImageFit.Cover : ImageFit.CENTER)
          .draggable(false)
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
      .padding({left: 7, right: 7, bottom: 5})
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .bindContextMenu(this.fileMenu(item), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [1.0, 1.0]
      }
    })
    .height(160)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .itemStyle()
  }

  @Builder fileMenu(item: ObjectInfo) {
    Menu() {
      MenuItemGroup() {
        if (item.type == 'dir') {
          MenuItem({ content: $r('app.string.dir_enter') })
            .onClick(() => {
              if (this.onMenuClick) {
                this.onMenuClick(item, FileMenuType.DIR_ENTER)
              }
            })
        } else {
          MenuItem({ content: $r('app.string.preview') })
            .onClick(() => {
              if (this.onMenuClick) {
                this.onMenuClick(item, FileMenuType.PREVIEW)
              }
            })
        }
        MenuItem({ content: $r('app.string.file_details') })
          .onClick(() => {
            if (this.onMenuClick) {
              this.onMenuClick(item, FileMenuType.DETAIL)
            }
          })
        MenuItem({ content: $r('app.string.rename') })
          .onClick(() => {
            if (this.onMenuClick) {
              this.onMenuClick(item, FileMenuType.RENAME)
            }
          })
        MenuItem({ content: $r('app.string.copy') })
          .onClick(() => {
            if (this.onMenuClick) {
              this.onMenuClick(item, FileMenuType.COPY)
            }
          })
        MenuItem({ content: $r('app.string.move') })
          .onClick(() => {
            if (this.onMenuClick) {
              this.onMenuClick(item, FileMenuType.MOVE)
            }
          })
        MenuItem({ content: $r('app.string.cloud_share') })
          .onClick(() => {
            if (this.onMenuClick) {
              this.onMenuClick(item, FileMenuType.CREATE_SHARE)
            }
          })
      }
      if (item.type == 'file') {
        MenuItemGroup() {
          MenuItem({content: $r('app.string.file_download')})
            .onClick(() => {
              if (this.onMenuClick) {
                this.onMenuClick(item, FileMenuType.DOWNLOAD)
              }
            })
        }
      }
      MenuItemGroup() {
        MenuItem({content: $r('app.string.delete')})
          .contentFontColor(Color.Red)
          .onClick(() => {
            if (this.onMenuClick) {
              this.onMenuClick(item, FileMenuType.DELETE)
            }
          })
      }
    }
    .width(220)
    .padding(0)
    .margin(0)
    .backgroundColor($r('app.color.file_menu_background'))
    .menuItemDivider({
      color: $r("app.color.menu_divider_line"),
      strokeWidth: {value: 2, unit: LengthUnit.PX}
    })
    .menuItemGroupDivider({
      color: $r("app.color.menu_divider_group_line"),
      strokeWidth: LengthMetrics.vp(5),
      startMargin: LengthMetrics.vp(0),
      endMargin: LengthMetrics.vp(0)
    })
  }
}