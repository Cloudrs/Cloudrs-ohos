
import { DateUtil } from "@pura/harmony-utils";
import { ObjectInfo } from "../model/net/ApiTypes";
import { LengthMetrics, LengthUnit } from "@kit.ArkUI";
import { FileMenuType, ShowType } from "../model/MenuModel";
import Constant from "../model/Constant";
import { CommonUtil } from "../utils/CommonUtil";
import { CloudThemeToken } from "../model/CloudTheme";

const TAG = 'ObjectItem';

@Extend(Column)
function itemStyle() {
  .width('100%')
  .borderRadius(CloudThemeToken.cardRadius)
  .clip(true)
  .alignItems(HorizontalAlign.Start)
  .justifyContent(FlexAlign.Center)
  .backgroundColor(CloudThemeToken.surface)
}

@Extend(Text)
function itemFileNameStyle() {
  .fontSize(16)
  .fontWeight(FontWeight.Medium)
  .fontColor(CloudThemeToken.textPrimary)
  .wordBreak(WordBreak.BREAK_ALL)
  .maxLines(1)
  .textOverflow({overflow: TextOverflow.Ellipsis})
  .width('100%')
}

@Extend(Text)
function itemFileDateStyle() {
  .fontSize(12)
  .fontColor(CloudThemeToken.textSecondary)
}

@Component
export struct ObjectItem {
  @Prop index: number
  @Prop item: ObjectInfo
  @Consume thumbImage: Map<string, PixelMap>
  onMenuClick?: (item: ObjectInfo, type: FileMenuType) => void
  @Prop showType: ShowType

  aboutToAppear(): void {
    console.debug(TAG, 'aboutToAppear')
  }

  getThumbData(id: string): PixelMap|undefined {
    if (this.thumbImage.has(id)) {
      return this.thumbImage.get(id)
    }
    return undefined
  }

  getItemIcon(name: string, isDir: boolean) {
    if (isDir) {
      return $r("app.media.ic_folder_fill")
    }
    else {
      return CommonUtil.getFileIconInfo(name).icon
    }
  }

  build() {
    if (this.item.type === Constant.OBJECT_DIR_TYPE) {
      this.dirItem(this.item)
    } else if (this.item.type === 'file') {
      if (this.showType == ShowType.SHOW_ICON) {
        this.fileIconItem(this.item)
      } else {
        this.fileListItem(this.item)
      }
    }
  }

  @Builder dirItem(item: ObjectInfo) {
    Column() {
      Row({ space: 10 }) {
        Image(this.getItemIcon(item.name, true))
          .width(40)
          .height(40)
          .draggable(false)

        Column({ space: 3 }) {
          //TODO: 加入是否下载为本地的图标
          Text(item.name)
            .itemFileNameStyle()

          Text(DateUtil.getFormatDateStr(new Date(item.date), 'yyyy-MM-dd'))
            .itemFileDateStyle()
        }
        .layoutWeight(1)
        .height(40)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)

        if (this.showType == ShowType.SHOW_LIST) {
          Image($r('app.media.ic_chevron_right'))
            .width(12)
            .height(12)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .height(50)
    .padding({left: 10, right: 10})
    .itemStyle()
    .bindContextMenu(this.fileMenu(item), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [1.0, 0.95]
      }
    })
  }

  @Builder fileIconItem(item: ObjectInfo) {
    Column({space: 10}) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.getThumbData(item.id)) {
          Image(this.getThumbData(item.id))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .draggable(false)
        } else {
          Image(CommonUtil.getFileIconInfo(item.name).icon)
            .width(56)
            .height(56)
            .draggable(false)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius({ topLeft: CloudThemeToken.cardRadius, topRight: CloudThemeToken.cardRadius })
      .backgroundColor(this.getThumbData(item.id) ? CloudThemeToken.surfaceSubtle :
        CommonUtil.getFileIconInfo(item.name).backgroundColor)

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

  @Builder fileListItem(item: ObjectInfo) {
    Column() {
      Row({ space: 10 }) {
        Image(this.getItemIcon(item.name, false))
          .width(40)
          .height(40)
          .draggable(false)

        Column({ space: 3 }) {
          //TODO: 加入是否下载为本地的图标
          Text(item.name)
            .itemFileNameStyle()

          Text(DateUtil.getFormatDateStr(new Date(item.date), 'yyyy-MM-dd') + ` · ` + CommonUtil.formatBytes(item.size))
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
    .height(50)
    .padding({left: 10, right: 10})
    .itemStyle()
    .bindContextMenu(this.fileMenu(item), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [1.0, 0.95]
      }
    })
  }

  @Builder fileMenu(item: ObjectInfo) {
    Menu() {
      MenuItemGroup() {
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          this.commonMenuItem($r('app.string.dir_enter'), FileMenuType.DIR_ENTER)
        } else {
          this.commonMenuItem($r('app.string.preview'), FileMenuType.PREVIEW)
        }
        this.commonMenuItem($r('app.string.file_details'), FileMenuType.DETAIL)
        this.commonMenuItem($r('app.string.rename'), FileMenuType.RENAME)
        this.commonMenuItem($r('app.string.copy'), FileMenuType.COPY)
        this.commonMenuItem($r('app.string.move'), FileMenuType.MOVE)
        this.commonMenuItem($r('app.string.cloud_share'), FileMenuType.CREATE_SHARE)
      }

      if (item.type == 'file') {
        MenuItemGroup() {
          this.commonMenuItem($r('app.string.file_download'), FileMenuType.DOWNLOAD)
        }
      }

      MenuItemGroup() {
        MenuItem(this.commonMenuBuilder($r('app.string.delete')))
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
    .backgroundColor(CloudThemeToken.surface)
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

  @Builder commonMenuItem(title: ResourceStr, type: FileMenuType) {
    MenuItem(this.commonMenuBuilder(title))
      .onClick(() => {
        if (this.onMenuClick) {
          this.onMenuClick(this.item, type)
        }
      })
  }

  @Builder commonMenuBuilder(content: ResourceStr, isSelected?: boolean) {
    Row() {
      Text(content)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
        .height(50)
        .layoutWeight(1)

      Image(isSelected ? $r('app.media.ic_selected') : '')
        .width(24)
        .height(24)
    }
    .padding({left: 20, right: 20})
    .width('100%')
    .height(50)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
