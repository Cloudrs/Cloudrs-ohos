import { CloudThemeToken } from '../model/CloudTheme'

/** 动作名与 web-editor/src/main.js 的 MARKDOWN_ACTIONS 一一对应 */
export enum MarkdownAction {
  UNDO = 'undo',
  REDO = 'redo',
  H1 = 'h1',
  H2 = 'h2',
  H3 = 'h3',
  BOLD = 'bold',
  ITALIC = 'italic',
  STRIKE = 'strike',
  CODE = 'code',
  CODE_BLOCK = 'codeblock',
  QUOTE = 'quote',
  LIST_UL = 'ul',
  LIST_OL = 'ol',
  TASK = 'task',
  INDENT = 'indent',
  OUTDENT = 'outdent',
  LINK = 'link',
  IMAGE = 'image',
  TABLE = 'table',
  HR = 'hr'
}

class ToolbarItem {
  action: MarkdownAction
  icon: Resource
  label: string
  /** 该项是否为一组的开头，是则在它前面画一条分隔线 */
  groupStart: boolean

  constructor(action: MarkdownAction, icon: Resource, label: string, groupStart: boolean = false) {
    this.action = action
    this.icon = icon
    this.label = label
    this.groupStart = groupStart
  }
}

/**
 * Markdown 快捷工具条，挂在标题栏下方。
 * 只做排版标记的插入/切换，正文改动一律经编辑器自己的事务，这里不碰文本。
 */
@Component
export struct MarkdownToolbar {
  @Prop previewMode: boolean = false
  @Prop editMode: boolean = false
  onTogglePreview?: () => void
  onAction?: (action: string) => void

  private items: ToolbarItem[] = [
    new ToolbarItem(MarkdownAction.UNDO, $r('app.media.ic_md_undo'), '撤销'),
    new ToolbarItem(MarkdownAction.REDO, $r('app.media.ic_md_redo'), '重做'),
    new ToolbarItem(MarkdownAction.H1, $r('app.media.ic_md_h1'), '一级标题', true),
    new ToolbarItem(MarkdownAction.H2, $r('app.media.ic_md_h2'), '二级标题'),
    new ToolbarItem(MarkdownAction.H3, $r('app.media.ic_md_h3'), '三级标题'),
    new ToolbarItem(MarkdownAction.BOLD, $r('app.media.ic_md_bold'), '加粗', true),
    new ToolbarItem(MarkdownAction.ITALIC, $r('app.media.ic_md_italic'), '斜体'),
    new ToolbarItem(MarkdownAction.STRIKE, $r('app.media.ic_md_strike'), '删除线'),
    new ToolbarItem(MarkdownAction.CODE, $r('app.media.ic_md_code'), '行内代码', true),
    new ToolbarItem(MarkdownAction.CODE_BLOCK, $r('app.media.ic_md_codeblock'), '代码块'),
    new ToolbarItem(MarkdownAction.QUOTE, $r('app.media.ic_md_quote'), '引用', true),
    new ToolbarItem(MarkdownAction.LIST_UL, $r('app.media.ic_md_list_ul'), '无序列表'),
    new ToolbarItem(MarkdownAction.LIST_OL, $r('app.media.ic_md_list_ol'), '有序列表'),
    new ToolbarItem(MarkdownAction.TASK, $r('app.media.ic_md_task'), '任务列表'),
    new ToolbarItem(MarkdownAction.INDENT, $r('app.media.ic_md_indent'), '增加缩进', true),
    new ToolbarItem(MarkdownAction.OUTDENT, $r('app.media.ic_md_outdent'), '减少缩进'),
    new ToolbarItem(MarkdownAction.LINK, $r('app.media.ic_md_link'), '链接', true),
    new ToolbarItem(MarkdownAction.IMAGE, $r('app.media.ic_md_image'), '图片'),
    new ToolbarItem(MarkdownAction.TABLE, $r('app.media.ic_md_table'), '表格'),
    new ToolbarItem(MarkdownAction.HR, $r('app.media.ic_md_hr'), '分割线')
  ]

  build() {
    Row({ space: CloudThemeToken.spacingXs }) {
      this.previewToggle()

      if (!this.previewMode) {
        Divider()
          .vertical(true)
          .height(CloudThemeToken.mdToolbarDividerHeight)
          .strokeWidth(CloudThemeToken.lineWidth)
          .color(CloudThemeToken.line)
          .margin({ left: CloudThemeToken.spacingXs, right: CloudThemeToken.spacingXs })

        // 按钮多于一屏，横向滚动而不是挤成一团
        Scroll() {
          Row({ space: CloudThemeToken.spacingXs }) {
            ForEach(this.items, (item: ToolbarItem) => {
              if (item.groupStart) {
                Divider()
                  .vertical(true)
                  .height(CloudThemeToken.mdToolbarDividerHeight)
                  .strokeWidth(CloudThemeToken.lineWidth)
                  .color(CloudThemeToken.line)
                  .margin({ left: CloudThemeToken.spacingTiny, right: CloudThemeToken.spacingTiny })
              }
              this.actionButton(item)
            }, (item: ToolbarItem) => item.action)
          }
          .padding({ right: CloudThemeToken.spacingCard })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
        .layoutWeight(1)
      } else {
        Text('预览模式')
          .fontSize(CloudThemeToken.mdToolbarLabelSize)
          .fontColor(CloudThemeToken.textSecondary)
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height(CloudThemeToken.mdToolbarHeight)
    .padding({ left: CloudThemeToken.spacingSection, right: CloudThemeToken.spacingSection })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CloudThemeToken.background)
    .border({ width: { bottom: CloudThemeToken.lineWidth }, color: CloudThemeToken.line })
  }

  @Builder previewToggle() {
    Row({ space: CloudThemeToken.spacingXs }) {
      Image(this.previewMode ? $r('app.media.ic_pencil') : $r('app.media.ic_eye'))
        .width(CloudThemeToken.mdToolbarIconSize)
        .height(CloudThemeToken.mdToolbarIconSize)
        .fillColor(CloudThemeToken.primary)
        .draggable(false)
      Text(this.previewMode ? '编辑' : '预览')
        .fontSize(CloudThemeToken.mdToolbarLabelSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.primary)
    }
    .height(CloudThemeToken.mdToolbarButtonSize)
    .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
    .borderRadius(CloudThemeToken.controlRadiusSm)
    .backgroundColor(CloudThemeToken.primarySoft)
    .alignItems(VerticalAlign.Center)
    .bindTips(this.previewMode ? '切换到源码编辑' : '渲染后预览')
    .onClick(() => {
      this.onTogglePreview?.()
    })
  }

  @Builder actionButton(item: ToolbarItem) {
    Button({ type: ButtonType.Normal }) {
      Image(item.icon)
        .width(CloudThemeToken.mdToolbarIconSize)
        .height(CloudThemeToken.mdToolbarIconSize)
        .fillColor(this.editMode ? CloudThemeToken.textPrimary : CloudThemeToken.textSecondary)
        .draggable(false)
    }
    .width(CloudThemeToken.mdToolbarButtonSize)
    .height(CloudThemeToken.mdToolbarButtonSize)
    .borderRadius(CloudThemeToken.controlRadiusSm)
    .backgroundColor(CloudThemeToken.transparent)
    .enabled(this.editMode)
    .opacity(this.editMode ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
    // 图标本身认不出来时鼠标悬停要有说明；置灰状态下 bindTips 依然会弹
    .bindTips(item.label)
    .onClick(() => {
      this.onAction?.(item.action)
    })
  }
}
