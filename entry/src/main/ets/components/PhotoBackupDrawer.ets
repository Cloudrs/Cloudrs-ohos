import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct PhotoBackupDrawer {
  @Prop backupEnabled: boolean = false;
  @Prop running: boolean = false;
  @Prop paused: boolean = false;
  @Prop completedCount: number = 0;
  @Prop localCount: number = 0;
  @Prop uploadingCount: number = 0;
  @Prop waitingCount: number = 0;
  @Prop failedCount: number = 0;
  @Prop statusText: string = '';
  onPrimary: () => void = () => {};
  onPauseResume: () => void = () => {};
  onRetryFailed: () => void = () => {};
  onGoEnable: () => void = () => {};

  @Builder metric(value: number, label: string, color: ResourceColor, onTap?: () => void) {
    Column({ space: CloudThemeToken.spacingXs }) {
      Text(value.toString())
        .fontSize(CloudThemeToken.textSizeTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
    }
    .onClick(() => { if (onTap) { onTap(); } })
  }

  build() {
    Column({ space: CloudThemeToken.spacingSection }) {
      if (!this.backupEnabled) {
        Row() {
          Text('备份已关闭')
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
            .layoutWeight(1)
          Button('去开启')
            .fontSize(CloudThemeToken.textSizeSmallPlus)
            .height(CloudThemeToken.rowHeightSm)
            .onClick(() => { this.onGoEnable(); })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Row() {
          Column({ space: CloudThemeToken.spacingXs }) {
            Text(this.statusText)
              .fontSize(CloudThemeToken.textSizeBody)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary)
            Text(`已备份 ${this.completedCount} / ${this.localCount}`)
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.running || this.paused) {
            Button(this.paused ? '继续' : '暂停')
              .fontSize(CloudThemeToken.textSizeSmallPlus)
              .height(CloudThemeToken.rowHeightSm)
              .backgroundColor(CloudThemeToken.surface)
              .fontColor(CloudThemeToken.primary)
              .onClick(() => { this.onPauseResume(); })
          } else {
            Button('立即备份')
              .fontSize(CloudThemeToken.textSizeSmallPlus)
              .height(CloudThemeToken.rowHeightSm)
              .onClick(() => { this.onPrimary(); })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Progress({ value: this.completedCount, total: Math.max(this.localCount, 1), type: ProgressType.Capsule })
          .width('100%')
          .height(CloudThemeToken.storageProgressHeight)
          .color(CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({ space: CloudThemeToken.spacingPage }) {
          this.metric(this.uploadingCount, '上传中', CloudThemeToken.primary)
          this.metric(this.waitingCount, '待备份', CloudThemeToken.textPrimary)
          this.metric(this.failedCount, '失败 · 重试', CloudThemeToken.danger, () => {
            if (this.failedCount > 0) { this.onRetryFailed(); }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
    }
    .width('100%')
    .padding(CloudThemeToken.spacingPage)
    .borderRadius({
      bottomLeft: CloudThemeToken.surfaceRadius,
      bottomRight: CloudThemeToken.surfaceRadius
    })
    .backgroundColor(CloudThemeToken.surfaceTranslucent)
    .backdropBlur(18)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
  }
}
