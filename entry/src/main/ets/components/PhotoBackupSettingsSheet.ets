import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupSettings } from '../model/PhotoBackupModel';
import { PhotoBackupSettingsStore, PHOTO_BACKUP_PATH_KEY } from '../model/PhotoBackupSettingsStore';
import Constant from '../model/Constant';

@Component
export struct PhotoBackupSettingsSheet {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(PHOTO_BACKUP_PATH_KEY) mirroredPath: string = '';
  @State settings: PhotoBackupSettings = new PhotoBackupSettings();
  onClose: () => void = () => {};
  onPickPath: () => void = () => {};

  aboutToAppear(): void {
    this.settings = PhotoBackupSettingsStore.load();
  }

  private updateSettings(mutate: (s: PhotoBackupSettings) => void): void {
    if (this.mirroredPath && this.mirroredPath.length > 0) {
      this.settings.remotePath = this.mirroredPath;
    }
    const next = new PhotoBackupSettings();
    next.enabled = this.settings.enabled;
    next.remotePath = this.settings.remotePath;
    next.wifiOnly = this.settings.wifiOnly;
    next.autoBackup = this.settings.autoBackup;
    next.uploadConcurrent = this.settings.uploadConcurrent;
    next.lastScanAt = this.settings.lastScanAt;
    mutate(next);
    this.settings = next;        // new reference → guaranteed re-render
    PhotoBackupSettingsStore.save(next);
  }

  @Builder switchRow(title: string, desc: string, value: boolean, onToggle: (v: boolean) => void) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Column({ space: CloudThemeToken.spacingXs }) {
        Text(title)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
        Text(desc)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(CloudThemeToken.primary)
        .onChange((isOn: boolean) => {
          onToggle(isOn);
        })
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight4xl)
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
    .alignItems(VerticalAlign.Center)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .clip(true)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
  }

  @Builder concurrentStepButton(text: string, disabled: boolean, onClick: () => void) {
    Text(text)
      .width(CloudThemeToken.rowHeightSm)
      .height(CloudThemeToken.rowHeightSm)
      .fontSize(CloudThemeToken.textSizeLarge)
      .fontWeight(FontWeight.Bold)
      .fontColor(disabled ? CloudThemeToken.textSecondary : CloudThemeToken.textPrimary)
      .textAlign(TextAlign.Center)
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .opacity(disabled ? CloudThemeToken.disabledOpacity : CloudThemeToken.fullOpacity)
      .onClick(() => {
        if (!disabled) {
          onClick();
        }
      })
  }

  build() {
    Column({ space: CloudThemeToken.spacingPage }) {
      // Switch row: 开启自动备份
      this.switchRow(
        '开启自动备份',
        '扫描本地图片并上传到云端',
        this.settings.enabled,
        (v: boolean) => {
          this.updateSettings((s) => { s.enabled = v; });
        }
      )

      // Path row: 备份路径
      Row({ space: CloudThemeToken.spacingSection }) {
        Column({ space: CloudThemeToken.spacingXs }) {
          Text('备份路径')
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
          Text(this.mirroredPath && this.mirroredPath.length > 0 ? this.mirroredPath : this.settings.remotePath)
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Image($r('app.media.ic_chevron_right'))
          .width(CloudThemeToken.iconXs)
          .height(CloudThemeToken.iconXs)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight4xl)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .alignItems(VerticalAlign.Center)
      .borderRadius(CloudThemeToken.controlRadiusLg)
      .clip(true)
      .backgroundColor(CloudThemeToken.surface)
      .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
      .onClick(() => {
        this.onPickPath();
      })

      // Switch row: 仅 Wi-Fi 下备份
      this.switchRow(
        '仅 Wi-Fi 下备份',
        '关闭后将使用移动网络备份',
        this.settings.wifiOnly,
        (v: boolean) => {
          this.updateSettings((s) => { s.wifiOnly = v; });
        }
      )

      // Stepper row: 同时上传数量
      Row({ space: CloudThemeToken.spacingSection }) {
        Column({ space: CloudThemeToken.spacingXs }) {
          Text('同时上传数量')
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
          Text('当前 ' + this.settings.uploadConcurrent.toString() + ' 个任务同时上传')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          this.concurrentStepButton('-', this.settings.uploadConcurrent <= Constant.UPLOAD_CONCURRENT_MIN, () => {
            this.updateSettings((s) => {
              s.uploadConcurrent = PhotoBackupSettingsStore.normalizeConcurrent(s.uploadConcurrent - 1);
            });
          })

          Text(this.settings.uploadConcurrent.toString())
            .width(CloudThemeToken.rowHeightMd)
            .height(CloudThemeToken.rowHeightSm)
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .textAlign(TextAlign.Center)

          this.concurrentStepButton('+', this.settings.uploadConcurrent >= Constant.UPLOAD_CONCURRENT_MAX, () => {
            this.updateSettings((s) => {
              s.uploadConcurrent = PhotoBackupSettingsStore.normalizeConcurrent(s.uploadConcurrent + 1);
            });
          })
        }
        .height(CloudThemeToken.rowHeight2xl)
        .padding({ left: CloudThemeToken.spacingSm, right: CloudThemeToken.spacingSm })
        .borderRadius(CloudThemeToken.controlRadiusRoundMd)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight4xl)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .alignItems(VerticalAlign.Center)
      .borderRadius(CloudThemeToken.controlRadiusLg)
      .clip(true)
      .backgroundColor(CloudThemeToken.surface)
      .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
    .constraintSize({ minHeight: CloudThemeToken.detailSheetMinHeight })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }
}
