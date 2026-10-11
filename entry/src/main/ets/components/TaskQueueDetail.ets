import Constant from "../model/Constant"
import { CloudThemeToken } from "../model/CloudTheme"
import { CloudMaterial } from "../model/CloudMaterial"
import { UserTask } from "../model/net/ApiTypes"
import { DateFormatUtil } from "../utils/DateFormatUtil"
import {
  TASK_STATUS_CANCELED, TASK_STATUS_COMPLETED, TASK_STATUS_ERROR, TASK_STATUS_PROCESSING, TASK_STATUS_QUEUED,
  TaskQueueText
} from "../utils/TaskQueueText"
import { ChipTone, SettingChip } from "./settings/SettingRows"

// 任务队列「任务详情」半模态：卡片放不下的完整文件名、路径、失败原因都在这里。
// 布局沿用离线下载「下载详情」（Aria2FinishedDetail）：标题 + 状态行、提示块、信息分组、源文件分组。
// 任务队列没有删除接口，所以没有底部操作
@Component
export struct TaskQueueDetail {
  @Prop @Watch('onTaskChanged') task: UserTask
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  // 源文件超过预览数时先折叠，点「查看全部」展开
  @State showAllSources: boolean = false

  private onTaskChanged(): void {
    this.showAllSources = false
  }

  /** v3 只有类型和状态，没有文件名和路径 */
  private hasPaths(): boolean {
    return this.task.src_list.length > 0 || this.task.dst.length > 0
  }

  private lastSegment(path: string): string {
    const trimmed = path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path
    const slash = trimmed.lastIndexOf('/')
    return slash >= 0 && slash < trimmed.length - 1 ? trimmed.substring(slash + 1) : trimmed
  }

  // 标题：压缩写生成的压缩包名，解压写压缩包名，导入写源目录；v3 没有名字就写类型
  private getTitle(): string {
    if (this.task.kind === 'compress' && this.task.dst.length > 0) {
      return this.lastSegment(this.task.dst)
    }
    if (this.task.src.length > 0) {
      return TaskQueueText.source(this.task)
    }
    return TaskQueueText.kind(this.task.kind)
  }

  // 状态标签后的一行摘要：类型 · 几项 · 耗时；v3 换成进度说明
  private getMetaText(): string {
    if (!this.hasPaths()) {
      return TaskQueueText.progress(this.task)
    }
    const parts: string[] = [TaskQueueText.kind(this.task.kind)]
    if (this.isMultiSource()) {
      parts.push(`${this.task.src_list.length} 项`)
    }
    if (this.task.duration > 0) {
      parts.push(`耗时 ${TaskQueueText.duration(this.task.duration)}`)
    }
    return parts.join(' · ')
  }

  private getChipTone(): ChipTone {
    switch (this.task.status) {
      case TASK_STATUS_PROCESSING:
        return ChipTone.PRIMARY
      case TASK_STATUS_COMPLETED:
        return ChipTone.SUCCESS
      case TASK_STATUS_ERROR:
        return ChipTone.DANGER
      case TASK_STATUS_QUEUED:
      case TASK_STATUS_CANCELED:
      default:
        return ChipTone.NEUTRAL
    }
  }

  /** 压缩、迁移的输入是一组文件，单独成组列出 */
  private isMultiSource(): boolean {
    return (this.task.kind === 'compress' || this.task.kind === 'relocate') && this.task.src_list.length > 0
  }

  /** 信息组里有没有画路径行（单个源 / 目标），决定「创建时间」上面要不要分隔线 */
  private hasPathRows(): boolean {
    return (!this.isMultiSource() && this.task.src_list.length > 0) || this.task.dst.length > 0
  }

  private hasHiddenSources(): boolean {
    return !this.showAllSources && this.task.src_list.length > CloudThemeToken.aria2DetailFilePreviewCount
  }

  private getVisibleSources(): string[] {
    const sources = this.task.src_list
    return this.hasHiddenSources() ? sources.slice(0, CloudThemeToken.aria2DetailFilePreviewCount) : sources
  }

  private getSourceLabel(): string {
    return this.task.kind === 'import' ? '源目录' : '压缩包'
  }

  private getDestinationLabel(): string {
    switch (this.task.kind) {
      case 'extract':
        return '解压到'
      case 'import':
        return '导入到'
      default:
        return '保存位置'
    }
  }

  private formatTime(value: string): string {
    return DateFormatUtil.format(new Date(value), 'yyyy-MM-dd HH:mm')
  }

  build() {
    Scroll() {
      Column({ space: CloudThemeToken.sectionGap }) {
        Column({ space: CloudThemeToken.spacingSection }) {
          this.header()
          if (this.task.status === TASK_STATUS_ERROR) {
            this.noticeBlock(TaskQueueText.error(this.task), CloudThemeToken.danger, CloudThemeToken.dangerSoft)
          }
          if (this.task.failed > 0) {
            this.noticeBlock(TaskQueueText.failedObjects(this.task), CloudThemeToken.warning,
              CloudThemeToken.warningSoft)
          }
        }
        .width('100%')

        this.infoGroup()

        if (this.isMultiSource()) {
          this.sourceSection()
        }
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
      Text(this.getTitle())
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: CloudThemeToken.spacingXl }) {
        SettingChip({ text: TaskQueueText.status(this.task), tone: this.getChipTone() })
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

  @Builder noticeBlock(text: string, color: ResourceColor, background: ResourceColor) {
    Text(text)
      .width('100%')
      .fontSize(CloudThemeToken.textSizeSmallPlus)
      .lineHeight(CloudThemeToken.aria2DetailErrorLineHeight)
      .fontColor(color)
      // 失败原因多是英文，按单词换行，别把单词拦腰截断
      .wordBreak(WordBreak.BREAK_WORD)
      .padding({
        left: CloudThemeToken.spacingSection,
        right: CloudThemeToken.spacingSection,
        top: CloudThemeToken.spacingCard,
        bottom: CloudThemeToken.spacingCard
      })
      .borderRadius(CloudThemeToken.controlRadiusLg)
      .backgroundColor(background)
  }

  @Builder infoGroup() {
    Column() {
      // 单个源（解压的压缩包、导入的源目录）放在信息组里；多个源另起一组
      if (!this.isMultiSource() && this.task.src_list.length > 0) {
        this.infoRow(this.task.kind === 'import' ? $r('app.media.ic_aria2_detail_folder') :
          $r('app.media.ic_aria2_detail_file'), this.getSourceLabel(), this.task.src_list[0], false, true)
      }
      if (this.task.dst.length > 0) {
        this.infoRow($r('app.media.ic_aria2_detail_folder'), this.getDestinationLabel(), this.task.dst,
          this.task.src_list.length > 0 && !this.isMultiSource(), true)
      }
      this.infoRow($r('app.media.ic_aria2_detail_calendar'), '创建时间', this.formatTime(this.task.create_date),
        this.hasPathRows(), false)
      if (this.task.duration > 0) {
        this.infoRow($r('app.media.ic_aria2_detail_clock'), '执行耗时', TaskQueueText.duration(this.task.duration),
          true, false)
      }
      if (this.task.node.length > 0) {
        this.infoRow($r('app.media.ic_aria2_detail_server'), '处理节点', this.task.node, true, false)
      }
      if (!this.hasPaths() && TaskQueueText.progress(this.task).length > 0) {
        this.infoRow($r('app.media.ic_aria2_detail_clock'), '最后进度', TaskQueueText.progress(this.task), true, false)
      }
    }
    .groupStyle()
  }

  @Builder infoRow(icon: Resource, label: string, value: string, divider: boolean, isPath: boolean) {
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
        // 路径行折行显示全：卡片里被省略的长名字，用户点进来就是要看这个
        Text(value)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textSecondary)
          .textAlign(TextAlign.End)
          .wordBreak(isPath ? WordBreak.BREAK_ALL : WordBreak.NORMAL)
          .maxLines(isPath ? CloudThemeToken.aria2TaskDetailPathMaxLines : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
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

  @Builder sourceSection() {
    Column({ space: CloudThemeToken.spacingXl }) {
      Text(`源文件 · ${this.task.src_list.length}`)
        .fontSize(CloudThemeToken.settingSectionTitleSize)
        .fontColor(CloudThemeToken.textSecondary)
        .padding({ left: CloudThemeToken.spacingSection })

      Column() {
        ForEach(this.getVisibleSources(), (path: string, index: number) => {
          this.sourceRow(path, index > 0)
        }, (path: string, index: number) => `${index}_${path}`)

        if (this.hasHiddenSources()) {
          this.moreSourcesRow()
        }
      }
      .groupStyle()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder sourceRow(path: string, divider: boolean) {
    Column() {
      if (divider) {
        this.rowDivider()
      }
      Row({ space: CloudThemeToken.spacingSection }) {
        this.lineIcon($r('app.media.ic_aria2_detail_file'))
        Text(path)
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .lineHeight(CloudThemeToken.aria2DetailFileNameLineHeight)
          .fontColor(CloudThemeToken.textPrimary)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(CloudThemeToken.aria2DetailFileNameMaxLines)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
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

  @Builder moreSourcesRow() {
    Column() {
      Divider()
        .strokeWidth(CloudThemeToken.lineWidth)
        .color(CloudThemeToken.line)
      Row({ space: CloudThemeToken.spacingXs }) {
        Text(`查看全部 ${this.task.src_list.length} 项`)
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
      this.showAllSources = true
    })
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
