import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupSettings } from '../model/PhotoBackupModel';
import { PhotoBackupSettingsStore } from '../model/PhotoBackupSettingsStore';
import Constant from '../model/Constant';

@Component
export struct PhotoBackupSettingsSheet {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State settings: PhotoBackupSettings = new PhotoBackupSettings();
  onClose: () => void = () => {};
  onPickPath: () => void = () => {};

  aboutToAppear(): void {
    this.settings = PhotoBackupSettingsStore.load();
  }

  private persist(): void {
    PhotoBackupSettingsStore.save(this.settings);
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
      // Header
      Row() {
        Text('相册备份')
          .fontSize(CloudThemeToken.textSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)

        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_xmark_bold'))
            .width(CloudThemeToken.sheetActionIconSize)
            .height(CloudThemeToken.sheetActionIconSize)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
        .width(CloudThemeToken.iconBoxSm)
        .height(CloudThemeToken.iconBoxSm)
        .borderRadius(CloudThemeToken.controlRadius)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // Switch row: 开启自动备份
      this.switchRow(
        '开启自动备份',
        '扫描本地图片并上传到云端',
        this.settings.enabled,
        (v: boolean) => {
          this.settings.enabled = v;
          this.persist();
        }
      )

      // Path row: 备份路径
      Row({ space: CloudThemeToken.spacingSection }) {
        Column({ space: CloudThemeToken.spacingXs }) {
          Text('备份路径')
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
          Text(this.settings.remotePath)
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
          this.settings.wifiOnly = v;
          this.persist();
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
            this.settings.uploadConcurrent =
              PhotoBackupSettingsStore.normalizeConcurrent(this.settings.uploadConcurrent - 1);
            this.persist();
          })

          Text(this.settings.uploadConcurrent.toString())
            .width(CloudThemeToken.rowHeightMd)
            .height(CloudThemeToken.rowHeightSm)
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .textAlign(TextAlign.Center)

          this.concurrentStepButton('+', this.settings.uploadConcurrent >= Constant.UPLOAD_CONCURRENT_MAX, () => {
            this.settings.uploadConcurrent =
              PhotoBackupSettingsStore.normalizeConcurrent(this.settings.uploadConcurrent + 1);
            this.persist();
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
