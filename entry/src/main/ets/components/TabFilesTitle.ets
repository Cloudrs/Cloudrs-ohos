import { LengthMetrics, LengthUnit } from "@kit.ArkUI";
import Constant from "../model/Constant";
import { MoreMenuType, ShowType, SortType } from "../model/MenuModel";
import { CloudThemeToken } from "../model/CloudTheme";

PersistentStorage.persistProp(Constant.CURRENT_SHOW_TYPE, ShowType.SHOW_ICON)
PersistentStorage.persistProp(Constant.CURRENT_SORT_TYPE, SortType.SORT_BY_NAME)
PersistentStorage.persistProp(Constant.CURRENT_SORT_TYPE_RESERVE, new Map<SortType, boolean>([
  [SortType.SORT_BY_NAME, false], [SortType.SORT_BY_TYPE, false],
  [SortType.SORT_BY_TIME, false], [SortType.SORT_BY_SIZE, false],
]))

const TAG = 'TabFilesTitle'

@Component
export struct TabFilesTitle {
  @StorageLink(Constant.CURRENT_SHOW_TYPE) showType: ShowType = ShowType.SHOW_ICON
  @StorageLink(Constant.CURRENT_SORT_TYPE) sortType: SortType = SortType.SORT_BY_NAME
  @StorageLink(Constant.CURRENT_SORT_TYPE_RESERVE) sortTypeReverse: Map<SortType, boolean> = new Map<SortType, boolean>([
    [SortType.SORT_BY_NAME, false], [SortType.SORT_BY_TYPE, false],
    [SortType.SORT_BY_TIME, false], [SortType.SORT_BY_SIZE, false],
  ])
  @Prop mainTitle: string | Resource;
  @Prop subTitle: string | Resource;
  onMoreClick?: (menuType: MoreMenuType, isReverse?: boolean) => void;
  @State showMenu: boolean = false;

  isSortTypeReverse(type: SortType): boolean {
    if (this.sortTypeReverse.has(type)) {
      return this.sortTypeReverse.get(type)!
    }
    return false
  }

  setSortTypeReverse(type: SortType, isReverse: boolean) {
    this.sortTypeReverse.set(type, isReverse)
  }

  toggleShowType() {
    if (this.showType === ShowType.SHOW_ICON) {
      this.showType = ShowType.SHOW_LIST
      if (this.onMoreClick) {
        this.onMoreClick(MoreMenuType.SHOW_LIST)
      }
    } else {
      this.showType = ShowType.SHOW_ICON
      if (this.onMoreClick) {
        this.onMoreClick(MoreMenuType.SHOW_ICON)
      }
    }
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.mainTitle)
            .fontSize(CloudThemeToken.filesTitleMainSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })

          Text(this.subTitle)
            .fontSize(CloudThemeToken.filesTitleSubtitleSize)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .height(CloudThemeToken.filesTitleTextHeight)
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)

        Row({ space: CloudThemeToken.filesTitleActionGap }) {
          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.ic_folder_badge_plus'))
              .width(CloudThemeToken.filesTitleActionIconSize)
              .height(CloudThemeToken.filesTitleActionIconSize)
              .fillColor(CloudThemeToken.textPrimary)
          }
          .width(CloudThemeToken.iconButtonSize)
          .height(CloudThemeToken.iconButtonSize)
          .borderRadius(CloudThemeToken.controlRadius)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .onClick(() => {
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.NEW_DIR)
            }
          })

          Button({ type: ButtonType.Normal }) {
            Image(this.showType === ShowType.SHOW_ICON ? $r('app.media.ic_list_bullet_circle') : $r('app.media.ic_grid'))
              .width(CloudThemeToken.filesTitleActionIconSize)
              .height(CloudThemeToken.filesTitleActionIconSize)
              .fillColor(CloudThemeToken.textPrimary)
          }
          .width(CloudThemeToken.iconButtonSize)
          .height(CloudThemeToken.iconButtonSize)
          .borderRadius(CloudThemeToken.controlRadius)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .onClick(() => {
            this.toggleShowType()
          })

          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.ic_square_more'))
              .width(CloudThemeToken.filesTitleActionIconSize)
              .height(CloudThemeToken.filesTitleActionIconSize)
              .fillColor(this.showMenu ? CloudThemeToken.primary : CloudThemeToken.textPrimary)
          }
          .width(CloudThemeToken.iconButtonSize)
          .height(CloudThemeToken.iconButtonSize)
          .borderRadius(CloudThemeToken.controlRadius)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .bindMenu(this.moreMenu(), {onAppear: () => {
            this.showMenu = true
          }, onDisappear: () => {
            this.showMenu = false
          }})
        }
      }
      .padding({ left: CloudThemeToken.filesTitleHorizontalPadding, right: CloudThemeToken.filesTitleHorizontalPadding })
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(CloudThemeToken.filesTitleHeight)
    .align(Alignment.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder moreMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem(this.commonMenu($r('app.string.more_multi_select')))
          .onClick(() => {
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.MULTI_SELECT)
            }
          })
      }

      MenuItemGroup() {
        MenuItem(this.commonMenu($r('app.string.more_show_icon'), this.showType == ShowType.SHOW_ICON))
          .onClick(() => {
            this.showType = ShowType.SHOW_ICON
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.SHOW_ICON)
            }
          })
        MenuItem(this.commonMenu($r('app.string.more_show_list'), this.showType == ShowType.SHOW_LIST))
          .onClick(() => {
            this.showType = ShowType.SHOW_LIST
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.SHOW_LIST)
            }
          })
      }

      MenuItemGroup() {
        MenuItem(this.sortMenu($r('app.string.more_sort_by_name'), this.sortType === SortType.SORT_BY_NAME, this.isSortTypeReverse(SortType.SORT_BY_NAME)))
          .onClick(() => {
            let isReverse = this.isSortTypeReverse(SortType.SORT_BY_NAME)
            if (this.sortType != SortType.SORT_BY_NAME) {
              this.sortType = SortType.SORT_BY_NAME
            } else {
              isReverse = !isReverse
              this.setSortTypeReverse(SortType.SORT_BY_NAME, isReverse)
            }
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.SORT_BY_NAME, isReverse)
            }
          })
        // MenuItem(this.sortMenuBuilder($r('app.string.more_sort_by_type'), this.sortType === SortType.SORT_BY_TYPE, this.isSortTypeReverse(SortType.SORT_BY_TYPE)))
        //   .onClick(() => {
        //     let isReverse = this.isSortTypeReverse(SortType.SORT_BY_TYPE)
        //     if (this.sortType != SortType.SORT_BY_TYPE) {
        //       this.sortType = SortType.SORT_BY_TYPE
        //     } else {
        //       isReverse = !isReverse
        //       this.setSortTypeReverse(SortType.SORT_BY_TYPE, isReverse)
        //     }
        //     if (this.onMoreClick) {
        //       this.onMoreClick(MoreMenuType.SORT_BY_TYPE, isReverse)
        //     }
        //   })
        MenuItem(this.sortMenu($r('app.string.more_sort_by_time'), this.sortType === SortType.SORT_BY_TIME, this.isSortTypeReverse(SortType.SORT_BY_TIME)))
          .onClick(() => {
            let isReverse = this.isSortTypeReverse(SortType.SORT_BY_TIME)
            if (this.sortType != SortType.SORT_BY_TIME) {
              this.sortType = SortType.SORT_BY_TIME
            } else {
              isReverse = !isReverse
              this.setSortTypeReverse(SortType.SORT_BY_TIME, isReverse)
            }
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.SORT_BY_TIME, isReverse)
            }
          })
        MenuItem(this.sortMenu($r('app.string.more_sort_by_size'), this.sortType === SortType.SORT_BY_SIZE, this.isSortTypeReverse(SortType.SORT_BY_SIZE)))
          .onClick(() => {
            let isReverse = this.isSortTypeReverse(SortType.SORT_BY_SIZE)
            if (this.sortType != SortType.SORT_BY_SIZE) {
              this.sortType = SortType.SORT_BY_SIZE
            } else {
              isReverse = !isReverse
              this.setSortTypeReverse(SortType.SORT_BY_SIZE, isReverse)
            }
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.SORT_BY_SIZE, isReverse)
            }
          })
      }

      MenuItemGroup() {
        MenuItem(this.commonMenu($r('app.string.more_new_dir')))
          .onClick(() => {
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.NEW_DIR)
            }
          })
        MenuItem(this.commonMenu($r('app.string.more_new_file')))
          .onClick(() => {
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.NEW_FILE)
            }
          })
      }

      MenuItemGroup() {
        MenuItem(this.commonMenu($r('app.string.more_upload_file')))
          .onClick(() => {
            if (this.onMoreClick) {
              this.onMoreClick(MoreMenuType.UPLOAD_FILE)
            }
          })
      }
    }
    .width(CloudThemeToken.menuWidth)
    .padding(CloudThemeToken.zero)
    .margin(0)
    .backgroundColor(CloudThemeToken.surface)
    .menuItemDivider({
      color: CloudThemeToken.line,
      strokeWidth: { value: 2, unit: LengthUnit.PX }
    })
    .menuItemGroupDivider({
      color: CloudThemeToken.surfaceSubtle,
      strokeWidth: LengthMetrics.vp(5),
      startMargin: LengthMetrics.vp(0),
      endMargin: LengthMetrics.vp(0)
    })
  }

  @Builder commonMenu(content: ResourceStr, isSelected?: boolean) {
    Row() {
      Text(content)
        .fontSize(CloudThemeToken.objectMenuTextSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)
        .height(CloudThemeToken.menuItemLabelHeight)

        Image(isSelected ? $r('app.media.ic_selected') : '')
          .width(CloudThemeToken.objectMenuIconSize)
          .height(CloudThemeToken.objectMenuIconSize)
    }
    .padding({
      left: CloudThemeToken.objectMenuHorizontalPadding,
      right: CloudThemeToken.objectMenuHorizontalPadding
    })
    .width('100%')
    .height(CloudThemeToken.menuItemHeight)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder sortMenu(content: ResourceStr, isSelected: boolean, isReverse: boolean) {
    Row() {
      Text(content)
        .fontSize(CloudThemeToken.objectMenuTextSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.textPrimary)
        .layoutWeight(1)
        .height(CloudThemeToken.menuItemLabelHeight)

      Row({ space: CloudThemeToken.filesSortIconGroupGap }) {
        Image(isSelected ? isReverse ? $r('app.media.ic_sort_arrow_down') : $r('app.media.ic_sort_arrow_up') : '')
          .width(CloudThemeToken.objectMenuIconSize)
          .height(CloudThemeToken.objectMenuIconSize)
        Image(isSelected ? $r('app.media.ic_selected') : '')
          .width(CloudThemeToken.objectMenuIconSize)
          .height(CloudThemeToken.objectMenuIconSize)
      }
      .width(CloudThemeToken.filesSortIconGroupWidthPercent)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding({
      left: CloudThemeToken.objectMenuHorizontalPadding,
      right: CloudThemeToken.objectMenuHorizontalPadding
    })
    .width('100%')
    .height(CloudThemeToken.menuItemHeight)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

}
