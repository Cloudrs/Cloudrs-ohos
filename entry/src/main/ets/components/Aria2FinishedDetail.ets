import Constant from "../model/Constant"
import { CloudThemeToken } from "../model/CloudTheme"
import { CloudMaterial } from "../model/CloudMaterial"
import { Aria2Files, Aria2Finished, Aria2Status, TaskError } from "../model/net/ApiTypes"
import { CommonUtil } from "../utils/CommonUtil"
import { DateFormatUtil } from "../utils/DateFormatUtil"
import { ChipTone, SettingChip } from "./settings/SettingRows"

const MS_PER_MINUTE: number = Constant.MILLISECONDS_PER_SECOND * Constant.SECONDS_PER_MINUTE

// 离线下载「下载详情」半模态：标题 + 状态行、失败原因、信息分组、文件分组、删除。
// 图标与「我的」页同一套细线图标，分组样式对齐「我的」页，尽量一屏放下
@Component
export struct Aria2FinishedDetail {
  @Prop @Watch('onDetailChanged') detailData: Aria2Finished
  // Cloudreve v4 没有面向普通用户的「删除已结束任务记录」接口，只有管理员能删；
  // 权限不足时藏起按钮，免得点了必然弹「删除失败」。
  @Prop canDelete: boolean
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  // 文件超过预览数时先折叠，点「查看全部」展开
  @State showAllFiles: boolean = false
  onDeleteClick?: () => void
  onClose?: () => void

  private onDetailChanged(): void {
    this.showAllFiles = false
  }

  private isFinished(): boolean {
    return this.detailData.task_status == Aria2Status.FINISHED
  }

  private getTaskName(): string {
    if (!this.detailData.name || this.detailData.name.trim().length === 0 || this.detailData.name === '.') {
      return this.detailData.gid
    }
    return this.detailData.name
  }

  // 与列表项 TabAria2.getTaskStatus 同一套文案
  private getStatusText(): string {
    if (this.isFinished()) {
      return '下载完成'
    }
    return this.detailData.task_status == Aria2Status.ERROR ? '下载错误' : '下载失败'
  }

  private getErrorInfo(): string {
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

  private getFiles(): Aria2Files[] {
    return this.detailData.files ?? []
  }

  private hasHiddenFiles(): boolean {
    return !this.showAllFiles && this.getFiles().length > CloudThemeToken.aria2DetailFilePreviewCount
  }

  private getVisibleFiles(): Aria2Files[] {
    let files = this.getFiles()
    return this.hasHiddenFiles() ? files.slice(0, CloudThemeToken.aria2DetailFilePreviewCount) : files
  }

  // 标题下的一行摘要：总大小（仅完成时）· 文件数 · 用时
  private getMetaText(): string {
    let parts: string[] = []
    if (this.isFinished() && this.detailData.total > 0) {
      parts.push(CommonUtil.formatBytes(this.detailData.total, 1))
    }
    parts.push(`${this.getFiles().length} 个文件`)
    let duration = this.getDurationText()
    if (duration.length > 0) {
      parts.push(`用时 ${duration}`)
    }
    return parts.join(' · ')
  }

  private getDurationText(): string {
    let start = new Date(this.detailData.create).getTime()
    let end = new Date(this.detailData.update).getTime()
    if (Number.isNaN(start) || Number.isNaN(end) || end <= start) {
      return ''
    }
    let minutes = Math.floor((end - start) / MS_PER_MINUTE)
    if (minutes < 1) {
      return '不到 1 分钟'
    }
    if (minutes < Constant.MINUTES_PER_HOUR) {
      return `${minutes} 分钟`
    }
    let hours = Math.floor(minutes / Constant.MINUTES_PER_HOUR)
    if (hours < Constant.HOURS_PER_DAY) {
      let restMinutes = minutes % Constant.MINUTES_PER_HOUR
      return restMinutes > 0 ? `${hours} 小时 ${restMinutes} 分钟` : `${hours} 小时`
    }
    let days = Math.floor(hours / Constant.HOURS_PER_DAY)
    let restHours = hours % Constant.HOURS_PER_DAY
    return restHours > 0 ? `${days} 天 ${restHours} 小时` : `${days} 天`
  }

  private formatTime(value: string): string {
    return DateFormatUtil.format(new Date(value), 'yyyy-MM-dd HH:mm')
  }

  private getPathText(): string {
    return this.detailData.dst && this.detailData.dst.length > 0 ? this.detailData.dst : '未设置保存路径'
  }

  // 文件路径 = 保存位置/文件名（v4 由 native 拼出），去掉与「保存位置」重复的前缀；
  // 对不上（v3 给的是服务器本地临时路径）时退回取最后一段
  private getFileName(path: string): string {
    let dst = this.detailData.dst ?? ''
    if (dst.length > 0) {
      let prefix = dst.endsWith('/') ? dst : `${dst}/`
      if (path.startsWith(prefix) && path.length > prefix.length) {
        return path.substring(prefix.length)
      }
    }
    let slash = path.lastIndexOf('/')
    return slash >= 0 && slash < path.length - 1 ? path.substring(slash + 1) : path
  }

  // 失败任务的 length 是预期大小、并没下下来，只在完成时显示
  private getFileSizeText(item: Aria2Files): string {
    let length = parseInt(item.length)
    return this.isFinished() && !Number.isNaN(length) && length > 0 ? CommonUtil.formatBytes(length, 1) : ''
  }

  build() {
    Scroll() {
      Column({ space: CloudThemeToken.sectionGap }) {
        Column({ space: CloudThemeToken.spacingSection }) {
          this.header()
          if (!this.isFinished()) {
            this.errorBlock()
          }
        }
        .width('100%')

        this.infoGroup()

        if (this.getFiles().length > 0) {
          this.fileSection()
        }

        this.deleteAction()
      }
      .width('100%')
      .padding({
        left: CloudThemeToken.pagePadding,
        right: CloudThemeToken.pagePadding,
        top: CloudThemeToken.spacingXs,
        bottom: this.bottomRectHeight + CloudThemeToken.spacingPage
      })
    }
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor(CloudMaterial.materialSurface(CloudThemeToken.background))
  }

  @Styles groupStyle() {
    .width('100%')
    .borderRadius(CloudThemeToken.settingGroupRadius)
    .clip(true)
    .backgroundColor(CloudMaterial.cardBackground(CloudThemeToken.surface))
  }

  @Builder header() {
    Column({ space: CloudThemeToken.spacingXl }) {
      Text(this.getTaskName())
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: CloudThemeToken.spacingXl }) {
        SettingChip({ text: this.getStatusText(), tone: this.isFinished() ? ChipTone.SUCCESS : ChipTone.DANGER })
        Text(this.getMetaText())
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder errorBlock() {
    Text(this.getErrorInfo())
      .width('100%')
      .fontSize(CloudThemeToken.textSizeSmallPlus)
      .lineHeight(CloudThemeToken.aria2DetailErrorLineHeight)
      .fontColor(CloudThemeToken.danger)
      .wordBreak(WordBreak.BREAK_ALL)
      .maxLines(CloudThemeToken.aria2DetailErrorMaxLines)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({
        left: CloudThemeToken.spacingSection,
        right: CloudThemeToken.spacingSection,
        top: CloudThemeToken.spacingCard,
        bottom: CloudThemeToken.spacingCard
      })
      .borderRadius(CloudThemeToken.controlRadiusLg)
      .backgroundColor(CloudThemeToken.dangerSoft)
  }

  @Builder infoGroup() {
    Column() {
      // 路径过长时省略开头，保留末级目录
      this.infoRow($r('app.media.ic_aria2_detail_folder'), '保存位置', this.getPathText(), false, true)
      this.infoRow($r('app.media.ic_aria2_detail_calendar'), '创建时间', this.formatTime(this.detailData.create),
        true, false)
      this.infoRow($r('app.media.ic_aria2_detail_clock'), this.isFinished() ? '完成时间' : '结束时间',
        this.formatTime(this.detailData.update), true, false)
      if (this.detailData.node && this.detailData.node.length > 0) {
        this.infoRow($r('app.media.ic_aria2_detail_server'), '下载节点', this.detailData.node, true, false)
      }
    }
    .groupStyle()
  }

  @Builder infoRow(icon: Resource, label: string, value: string, divider: boolean, keepTail: boolean) {
    Column() {
      if (divider) {
        this.rowDivider()
      }
      Row({ space: CloudThemeToken.spacingSection }) {
        this.lineIcon(icon)
        Text(label)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
        Text(value)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textSecondary)
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(keepTail ? EllipsisMode.START : EllipsisMode.END)
          .layoutWeight(1)
      }
      .width('100%')
      .constraintSize({ minHeight: CloudThemeToken.rowHeight2xl })
      .padding({
        left: CloudThemeToken.spacingPanel,
        right: CloudThemeToken.spacingPanel,
        top: CloudThemeToken.spacingMd,
        bottom: CloudThemeToken.spacingMd
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder fileSection() {
    Column({ space: CloudThemeToken.spacingXl }) {
      Text(`文件 · ${this.getFiles().length}`)
        .fontSize(CloudThemeToken.settingSectionTitleSize)
        .fontColor(CloudThemeToken.textSecondary)
        .padding({ left: CloudThemeToken.spacingSection })

      Column() {
        ForEach(this.getVisibleFiles(), (item: Aria2Files, index: number) => {
          this.fileRow(item, index > 0)
        }, (item: Aria2Files, index: number) => `${index}_${item.path}`)

        if (this.hasHiddenFiles()) {
          this.moreFilesRow()
        }
      }
      .groupStyle()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder fileRow(item: Aria2Files, divider: boolean) {
    Column() {
      if (divider) {
        this.rowDivider()
      }
      Row({ space: CloudThemeToken.spacingSection }) {
        this.lineIcon($r('app.media.ic_aria2_detail_file'))
        Text(this.getFileName(item.path))
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .lineHeight(CloudThemeToken.aria2DetailFileNameLineHeight)
          .fontColor(CloudThemeToken.textPrimary)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(CloudThemeToken.aria2DetailFileNameMaxLines)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.getFileSizeText(item).length > 0) {
          Text(this.getFileSizeText(item))
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: CloudThemeToken.rowHeight2xl })
      .padding({
        left: CloudThemeToken.spacingPanel,
        right: CloudThemeToken.spacingPanel,
        top: CloudThemeToken.spacingMd,
        bottom: CloudThemeToken.spacingMd
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder moreFilesRow() {
    Column() {
      Divider()
        .strokeWidth(CloudThemeToken.lineWidth)
        .color(CloudThemeToken.line)
      Row({ space: CloudThemeToken.spacingXs }) {
        Text(`查看全部 ${this.getFiles().length} 个文件`)
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontColor(CloudThemeToken.primary)
        Image($r('app.media.ic_chevron_down'))
          .width(CloudThemeToken.iconSm)
          .height(CloudThemeToken.iconSm)
          .fillColor(CloudThemeToken.primary)
          .draggable(false)
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight2xl)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .stateStyles({
      pressed: { .backgroundColor(CloudThemeToken.surfaceSubtle) },
      normal: { .backgroundColor(CloudThemeToken.transparent) }
    })
    .onClick(() => {
      this.showAllFiles = true
    })
  }

  @Builder deleteAction() {
    if (this.canDelete) {
      // 同「我的」页「退出登录」：整行红字
      Row() {
        Text('删除任务记录')
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.danger)
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight2xl)
      .justifyContent(FlexAlign.Center)
      .borderRadius(CloudThemeToken.settingGroupRadius)
      .stateStyles({
        pressed: { .backgroundColor(CloudThemeToken.surfaceSubtle) },
        normal: { .backgroundColor(CloudMaterial.cardBackground(CloudThemeToken.surface)) }
      })
      .onClick(() => {
        if (this.onDeleteClick) {
          this.onDeleteClick()
        }
      })
    } else {
      Text($r('app.string.finished_task_admin_only'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
    }
  }

  @Builder lineIcon(icon: Resource) {
    Image(icon)
      .width(CloudThemeToken.settingLineIconSize)
      .height(CloudThemeToken.settingLineIconSize)
      .fillColor(CloudThemeToken.textPrimary)
      .draggable(false)
  }

  @Builder rowDivider() {
    Divider()
      .strokeWidth(CloudThemeToken.lineWidth)
      .color(CloudThemeToken.line)
      .margin({ left: CloudThemeToken.settingDividerInsetIcon })
  }
}
