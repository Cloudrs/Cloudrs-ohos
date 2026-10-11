import Constant from "../model/Constant"
import { CloudThemeToken } from "../model/CloudTheme"
import { CloudMaterial } from "../model/CloudMaterial"
import { TabId } from "../model/TabData"

// 压缩 / 解压浮条：提交中 / 进行中蓝色转圈、排队中灰色转圈、完成绿点、失败红点；
// 「查看」跳到 下载 → 任务队列（提交中还没有任务、完成不用看，都不给）。只有「查看」可点
@Component
export struct ArchiveTaskBanner {
  @StorageProp(Constant.ARCHIVE_BANNER_MODE) mode: string = 'hidden'
  @StorageProp(Constant.ARCHIVE_BANNER_TEXT) text: string = ''

  private openTaskQueue(): void {
    AppStorage.setOrCreate(Constant.ARIA2_SEGMENT_REQUEST, Constant.ARIA2_TASK_QUEUE_SEGMENT)
    AppStorage.setOrCreate(Constant.HOME_TAB_REQUEST, TabId.REMOTE_DOWN)
  }

  private isInProgress(): boolean {
    return this.mode === 'submitting' || this.mode === 'queued' || this.mode === 'running'
  }

  build() {
    if (this.mode !== 'hidden') {
      Row({ space: CloudThemeToken.spacingXl }) {
        if (this.isInProgress()) {
          LoadingProgress()
            .width(CloudThemeToken.iconLg)
            .height(CloudThemeToken.iconLg)
            .color(this.mode === 'queued' ? CloudThemeToken.textSecondary : CloudThemeToken.primary)
        } else {
          // 圆点用圆角 Row 画：Circle.fill 这个重载要 API 26，本分支兼容到 23
          Row()
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .borderRadius(CloudThemeToken.iconXs / 2)
            .backgroundColor(this.mode === 'done' ? CloudThemeToken.success : CloudThemeToken.danger)
        }
        Text(this.text)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.mode !== 'done' && this.mode !== 'submitting') {
          Text('查看')
            .fontSize(CloudThemeToken.textSizeSmallPlus)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.primary)
            .height(CloudThemeToken.archiveBannerActionHeight)
            .padding({ left: CloudThemeToken.spacingSection, right: CloudThemeToken.spacingSection })
            .borderRadius(CloudThemeToken.archiveBannerActionHeight / 2)
            .backgroundColor(CloudThemeToken.primarySoft)
            .onClick(() => this.openTaskQueue())
        }
      }
      .width('100%')
      .height(CloudThemeToken.archiveBannerHeight)
      .padding({ left: CloudThemeToken.spacingPage, right: CloudThemeToken.spacingXl })
      .borderRadius(CloudThemeToken.archiveBannerRadius)
      .backgroundColor(CloudMaterial.cardBackground(CloudThemeToken.surface))
      .shadow({
        radius: CloudThemeToken.refreshShadowRadius,
        color: CloudThemeToken.refreshShadow,
        offsetY: CloudThemeToken.refreshShadowOffsetY
      })
      .alignItems(VerticalAlign.Center)
    }
  }
}
