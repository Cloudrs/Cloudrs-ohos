import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';
import AppLogger from '../utils/AppLogger';
import { showToast } from '../utils/ToastUtil';

const TAG: string = 'LogViewerSheet';

@Component
export struct LogViewerSheet {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State logText: string = '';
  @State logEmpty: boolean = false;
  private scroller: Scroller = new Scroller();
  onClose?: () => void;
  onCopyDiagnostic?: () => void;

  aboutToAppear(): void {
    this.refreshLogText();
    setTimeout(() => {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (_) {
      }
    }, 80);
  }

  build() {
    Column({ space: CloudThemeToken.spacingPage }) {
      this.header()
      this.actionRow()
      this.logBody()
      this.footer()
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

  @Builder header() {
    Row() {
      Column({ space: CloudThemeToken.spacingXs }) {
        Text('日志与诊断')
          .fontSize(CloudThemeToken.textSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
        Text('已脱敏 · 复制诊断会一并带上日志尾部')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

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
        this.onClose?.();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder actionRow() {
    Row({ space: CloudThemeToken.spacingCard }) {
      this.toolButton('复制诊断', $r('app.media.ic_copy'), !this.onCopyDiagnostic, () => {
        this.onCopyDiagnostic?.();
      })
      this.toolButton('导出日志', $r('app.media.ic_share'), this.logEmpty, () => {
        this.exportFile();
      })
      this.toolButton('清空', $r('app.media.ic_xmark_bold'), this.logEmpty, () => {
        this.clearLogs();
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder toolButton(title: string, icon: Resource, disabled: boolean, onTap: () => void) {
    Row({ space: CloudThemeToken.spacingXs }) {
      Image(icon)
        .width(CloudThemeToken.iconMd)
        .height(CloudThemeToken.iconMd)
        .fillColor(disabled ? CloudThemeToken.textSecondary : CloudThemeToken.textPrimary)
        .draggable(false)
      Text(title)
        .fontSize(CloudThemeToken.textSizeBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(disabled ? CloudThemeToken.textSecondary : CloudThemeToken.textPrimary)
    }
    .layoutWeight(1)
    .height(CloudThemeToken.rowHeight3xl)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .opacity(disabled ? CloudThemeToken.disabledOpacity : CloudThemeToken.fullOpacity)
    .onClick(() => {
      if (!disabled) {
        onTap();
      }
    })
  }

  @Builder logBody() {
    Stack() {
      if (this.logEmpty) {
        Column({ space: CloudThemeToken.spacingCard }) {
          Text('暂无日志')
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
          Text('启动 App、执行上传或浏览文件后日志会自动累积')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(CloudThemeToken.spacingPanel)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll(this.scroller) {
          Text(this.logText)
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textPrimary)
            .fontFamily('HarmonyOS Sans, monospace')
            .textAlign(TextAlign.Start)
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
        }
        .width('100%')
        .scrollBar(BarState.Auto)
        .padding(CloudThemeToken.spacingPanel)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height(CloudThemeToken.logViewerBodyHeight)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
  }

  @Builder footer() {
    Row({ space: CloudThemeToken.spacingXs }) {
      Image($r('app.media.ic_info_circle'))
        .width(CloudThemeToken.iconMd)
        .height(CloudThemeToken.iconMd)
        .fillColor(CloudThemeToken.textSecondary)
        .draggable(false)
      Text(`本机保存路径：${AppLogger.getFilePath()}`)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
        .layoutWeight(1)
        .copyOption(CopyOptions.LocalDevice)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private refreshLogText(): void {
    const text = AppLogger.getAllText();
    this.logText = text;
    this.logEmpty = text.length === 0;
  }

  private clearLogs(): void {
    AppLogger.clear();
    this.refreshLogText();
    showToast('日志已清空');
  }

  private exportFile(): void {
    if (this.logEmpty) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (!context) {
      showToast('无法访问存储');
      return;
    }
    try {
      const options = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      options.newFileNames = [this.suggestExportName()];
      const documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.save(options).then((result: Array<string>) => {
        if (!result || result.length === 0) {
          return;
        }
        this.writeLogToUri(result[Constant.FIRST_ARRAY_INDEX]);
      }).catch((err: BusinessError) => {
        AppLogger.error(TAG, `export picker failed: code=${err.code}, msg=${err.message}`);
        showToast('导出取消或失败');
      });
    } catch (err) {
      AppLogger.error(TAG, `export logs threw: ${(err as Error)?.message ?? err}`);
      showToast('导出失败');
    }
  }

  private writeLogToUri(uri: string): void {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, this.logText);
      showToast('日志已导出到所选位置');
    } catch (err) {
      AppLogger.error(TAG, `write export file failed: ${(err as Error)?.message ?? err}`);
      showToast('导出写入失败');
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private suggestExportName(): string {
    const d = new Date();
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `cloudrs-log-${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}.txt`;
  }
}
