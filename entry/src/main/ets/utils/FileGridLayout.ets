import { CloudThemeToken } from "../model/CloudTheme"
import { ShowType } from "../model/MenuModel"

export class FileGridLayout {
  static getColumns(width: number, showType: ShowType): number {
    if (showType !== ShowType.SHOW_ICON) {
      return CloudThemeToken.singleColumnMaxCount
    }
    if (width >= CloudThemeToken.content4xlBreakpoint) {
      return CloudThemeToken.fileGrid4xlColumns
    }
    if (width >= CloudThemeToken.content3xlBreakpoint) {
      return CloudThemeToken.fileGrid3xlColumns
    }
    if (width >= CloudThemeToken.contentXxlBreakpoint) {
      return CloudThemeToken.fileGridXxlColumns
    }
    if (width >= CloudThemeToken.contentXlBreakpoint) {
      return CloudThemeToken.fileGridXlColumns
    }
    if (width >= CloudThemeToken.wideBreakpoint) {
      return CloudThemeToken.fileGridWideColumns
    }
    if (width >= CloudThemeToken.tabletBreakpoint) {
      return CloudThemeToken.fileGridTabletColumns
    }
    if (width >= CloudThemeToken.twoColumnBreakpoint) {
      return CloudThemeToken.fileGridMediumColumns
    }
    return CloudThemeToken.fileGridPhoneColumns
  }

  static getColumnsTemplate(width: number, showType: ShowType): string {
    const columns = FileGridLayout.getColumns(width, showType)
    const templates: string[] = []
    for (let index = 0; index < columns; index++) {
      templates.push(CloudThemeToken.singleColumnTemplate)
    }
    return templates.join(' ')
  }

  static getPaddingCount(itemCount: number, width: number, showType: ShowType): number {
    if (showType !== ShowType.SHOW_ICON) {
      return CloudThemeToken.zero
    }
    const columns = FileGridLayout.getColumns(width, showType)
    const remainder = itemCount % columns
    return remainder === 0 ? 0 : columns - remainder
  }
}
