import { ObjectInfo } from "../model/net/ApiTypes";
import { LengthMetrics, LengthUnit } from "@kit.ArkUI";
import { FileMenuType, ShowType } from "../model/MenuModel";
import Constant from "../model/Constant";
import { CommonUtil } from "../utils/CommonUtil";
import { CloudThemeToken } from "../model/CloudTheme";
import { DateFormatUtil } from "../utils/DateFormatUtil";

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
  .fontSize(CloudThemeToken.textSizeLarge)
  .fontWeight(FontWeight.Medium)
  .fontColor(CloudThemeToken.textPrimary)
  .maxLines(1)
  .textOverflow({overflow: TextOverflow.Ellipsis})
  .width('100%')
}

@Extend(Text)
function itemFileDateStyle() {
  .fontSize(CloudThemeToken.textSizeSmall)
  .fontColor(CloudThemeToken.textSecondary)
  .maxLines(1)
  .textOverflow({overflow: TextOverflow.Ellipsis})
  .width('100%')
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

  getDisplayName(name: string, maxLength: number = CloudThemeToken.fileNameDisplayMaxLength): string {
    if (name.length <= maxLength) {
      return name
    }
    const dotIndex = name.lastIndexOf('.')
    const extension = dotIndex > 0 ? name.substring(dotIndex) : ''
    const baseName = dotIndex > 0 ? name.substring(0, dotIndex) : name
    const suffixLength = Math.min(CloudThemeToken.fileNameEdgeSegmentLength, baseName.length)
    const prefixLength = Math.max(CloudThemeToken.fileNameEdgeSegmentLength,
      maxLength - suffixLength - extension.length - CloudThemeToken.lineWidth)
    return `${baseName.substring(0, prefixLength)}…${baseName.substring(baseName.length - suffixLength)}${extension}`
  }

  getDateText(date: string): string {
    return DateFormatUtil.format(new Date(date), 'yyyy-MM-dd')
  }

  getFileMetaText(item: ObjectInfo): string {
    return `${this.getDateText(item.date)} · ${CommonUtil.formatBytes(item.size)}`
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
      Row({ space: CloudThemeToken.objectItemGap }) {
        Image(this.getItemIcon(item.name, true))
          .width(this.showType == ShowType.SHOW_LIST ? CloudThemeToken.objectListIconSize :
          CloudThemeToken.objectGridFolderIconSize)
          .height(this.showType == ShowType.SHOW_LIST ? CloudThemeToken.objectListIconSize :
          CloudThemeToken.objectGridFolderIconSize)
          .draggable(false)

        Column({ space: CloudThemeToken.objectMetaGap }) {
          Text(this.getDisplayName(item.name, this.showType == ShowType.SHOW_LIST ? 42 : 26))
            .itemFileNameStyle()

          Text(this.getDateText(item.date))
            .itemFileDateStyle()
        }
        .layoutWeight(1)
        .height(CloudThemeToken.objectTextBlockHeight)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)

        if (this.showType == ShowType.SHOW_LIST) {
          Image($r('app.media.ic_chevron_right'))
            .width(CloudThemeToken.objectChevronSize)
            .height(CloudThemeToken.objectChevronSize)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .height(this.showType == ShowType.SHOW_LIST ? CloudThemeToken.objectListRowHeight :
    CloudThemeToken.objectGridFolderHeight)
    .padding({ left: CloudThemeToken.objectHorizontalPadding, right: CloudThemeToken.objectHorizontalPadding })
    .itemStyle()
    .bindContextMenu(this.fileMenu(item), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [CloudThemeToken.fullOpacity, CloudThemeToken.pressedScale]
      }
    })
  }

  @Builder fileIconItem(item: ObjectInfo) {
    Column({ space: CloudThemeToken.objectGridGap }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.getThumbData(item.id)) {
          Image(this.getThumbData(item.id))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .draggable(false)
        } else {
          Image(CommonUtil.getFileIconInfo(item.name).icon)
            .width(CloudThemeToken.objectGridFileIconSize)
            .height(CloudThemeToken.objectGridFileIconSize)
            .draggable(false)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius({ topLeft: CloudThemeToken.cardRadius, topRight: CloudThemeToken.cardRadius })
      .backgroundColor(this.getThumbData(item.id) ? CloudThemeToken.surfaceSubtle :
        CommonUtil.getFileIconInfo(item.name).backgroundColor)

      Column({ space: CloudThemeToken.objectMetaGap }) {
        Text(this.getDisplayName(item.name, CloudThemeToken.fileNameDisplayMaxLength))
          .itemFileNameStyle()

        Text(this.getDateText(item.date))
          .itemFileDateStyle()
      }
      .height(CloudThemeToken.objectGridTextHeight)
      .padding({
        left: CloudThemeToken.objectGridTextHorizontalPadding,
        right: CloudThemeToken.objectGridTextHorizontalPadding,
        bottom: CloudThemeToken.objectGridTextBottomPadding
      })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .bindContextMenu(this.fileMenu(item), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [CloudThemeToken.fullOpacity, CloudThemeToken.fullOpacity]
      }
    })
    .height(CloudThemeToken.objectGridFileHeight)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .itemStyle()
  }

  @Builder fileListItem(item: ObjectInfo) {
    Column() {
      Row({ space: CloudThemeToken.objectItemGap }) {
        Image(this.getItemIcon(item.name, false))
          .width(CloudThemeToken.objectListIconSize)
          .height(CloudThemeToken.objectListIconSize)
          .draggable(false)

        Column({ space: CloudThemeToken.objectMetaGap }) {
          Text(this.getDisplayName(item.name, 42))
            .itemFileNameStyle()

          Text(this.getFileMetaText(item))
            .itemFileDateStyle()
        }
        .layoutWeight(1)
        .height(CloudThemeToken.objectTextBlockHeight)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .height(CloudThemeToken.objectListRowHeight)
    .padding({ left: CloudThemeToken.objectHorizontalPadding, right: CloudThemeToken.objectHorizontalPadding })
    .itemStyle()
    .bindContextMenu(this.fileMenu(item), ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewAnimationOptions: {
        hoverScale: [CloudThemeToken.fullOpacity, CloudThemeToken.pressedScale]
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
          .contentFontColor(CloudThemeToken.danger)
          .onClick(() => {
            if (this.onMenuClick) {
              this.onMenuClick(item, FileMenuType.DELETE)
            }
          })
      }
    }
    .width(CloudThemeToken.menuWidth)
    .padding(CloudThemeToken.zero)
    .margin(CloudThemeToken.zero)
    .backgroundColor(CloudThemeToken.surface)
    .menuItemDivider({
      color: CloudThemeToken.line,
      strokeWidth: {value: CloudThemeToken.strongLineWidth, unit: LengthUnit.PX}
    })
    .menuItemGroupDivider({
      color: CloudThemeToken.surfaceSubtle,
      strokeWidth: LengthMetrics.vp(CloudThemeToken.spacingSm),
      startMargin: LengthMetrics.vp(CloudThemeToken.zero),
      endMargin: LengthMetrics.vp(CloudThemeToken.zero)
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
        .fontSize(CloudThemeToken.objectMenuTextSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
        .height(CloudThemeToken.menuItemLabelHeight)
        .layoutWeight(1)

      Image(isSelected ? $r('app.media.ic_selected') : '')
        .width(CloudThemeToken.objectMenuIconSize)
        .height(CloudThemeToken.objectMenuIconSize)
    }
    .padding({
      left: CloudThemeToken.objectMenuHorizontalPadding,
      right: CloudThemeToken.objectMenuHorizontalPadding
    })
    .width('100%')
    .height(CloudThemeToken.menuItemLabelHeight)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
