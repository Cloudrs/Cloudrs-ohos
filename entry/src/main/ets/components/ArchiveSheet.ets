import Constant from "../model/Constant"
import { CloudThemeToken } from "../model/CloudTheme"
import { CloudMaterial } from "../model/CloudMaterial"
import { ArchiveRules, ZipEncodingOption } from "../utils/ArchiveRules"
import { PathSelectSheet } from "./PathSelectSheet"

export enum ArchiveSheetMode {
  COMPRESS,
  EXTRACT
}

export interface ArchiveCompressInput {
  name: string
  dstFolder: string
}

export interface ArchiveExtractInput {
  dstFolder: string
  encoding: string
  password: string
}

enum ArchiveStep {
  FORM,
  PICK_ENCODING
}

const ARCHIVE_NAME_INPUT_ID: string = 'archive_sheet_name_input'

// 压缩 / 解压面板。选目标文件夹同离线下载：在面板上方另弹路径选择（只有它自己的标题栏，不会出现两层标题）；
// 选编码只是一张短列表，留在面板内切换
@Component
export struct ArchiveSheet {
  @Prop mode: ArchiveSheetMode
  @Prop archiveName: string = ''
  @Prop selectedCount: number = 0
  @Prop defaultName: string = ''
  @Prop initialFolder: string = '/'
  @Prop isV4: boolean = true
  // 宿主在面板 onAppear 后加 1：入场动画结束再聚焦拉键盘（ArkTS 父组件调不到子组件方法，用这个信号）
  @Prop @Watch('onFocusTick') focusTick: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.KEYBOARD_HEIGHT_VP) keyboardHeightVp: number = 0
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0
  @State step: ArchiveStep = ArchiveStep.FORM
  @State showFolderPicker: boolean = false
  @State name: string = ''
  @State dstFolder: string = '/'
  @State encoding: string = ''
  @State password: string = ''
  private nameController: TextInputController = new TextInputController()
  onCompress?: (input: ArchiveCompressInput) => void
  onExtract?: (input: ArchiveExtractInput) => void

  aboutToAppear(): void {
    this.name = this.defaultName
    this.dstFolder = this.initialFolder.length > 0 ? this.initialFolder : '/'
  }

  /** 聚焦文件名并选中主名部分（同重命名） */
  private onFocusTick(): void {
    if (this.mode !== ArchiveSheetMode.COMPRESS) {
      return
    }
    try {
      this.getUIContext().getFocusController().requestFocus(ARCHIVE_NAME_INPUT_ID)
    } catch (err) {
      return
    }
    const dot = this.name.lastIndexOf('.')
    this.nameController.setTextSelection(0, dot > 0 ? dot : this.name.length)
  }

  private encodingLabel(): string {
    const found = ArchiveRules.ZIP_ENCODINGS.find((o: ZipEncodingOption) => o.value === this.encoding)
    return found ? found.label : ArchiveRules.ZIP_ENCODINGS[0].label
  }

  private canSubmit(): boolean {
    return this.mode === ArchiveSheetMode.EXTRACT || ArchiveRules.archiveNameError(this.name).length === 0
  }

  private submit(): void {
    if (!this.canSubmit()) {
      return
    }
    if (this.mode === ArchiveSheetMode.COMPRESS) {
      this.onCompress?.({ name: this.name.trim(), dstFolder: this.dstFolder })
    } else {
      this.onExtract?.({ dstFolder: this.dstFolder, encoding: this.encoding, password: this.password })
    }
  }

  build() {
    Column() {
      if (this.step === ArchiveStep.PICK_ENCODING) {
        this.encodingList()
      } else {
        this.form()
      }
    }
    .width('100%')
    .backgroundColor(CloudMaterial.materialSurface(CloudThemeToken.background))
    // 与离线下载（Aria2Create）的路径选择同一套参数
    .bindSheet($$this.showFolderPicker, this.folderPickerSheet(), {
      showClose: false,
      backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
      systemMaterial: CloudMaterial.sheetMaterial(),
      preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
      width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
      onDisappear: () => {
        this.showFolderPicker = false
      }
    })
  }

  @Builder folderPickerSheet() {
    PathSelectSheet({
      title: this.mode === ArchiveSheetMode.COMPRESS ? '保存到' : '解压到',
      filterDirId: '',
      onClose: (isFinished: boolean, path?: string) => {
        this.showFolderPicker = false
        if (isFinished && path && path.length > 0) {
          this.dstFolder = path
        }
      }
    })
  }

  @Builder form() {
    Column({ space: CloudThemeToken.spacingSheetTop }) {
      if (this.mode === ArchiveSheetMode.COMPRESS) {
        TextInput({ text: this.name, placeholder: '压缩包名称', controller: this.nameController })
          .width('100%')
          .height(CloudThemeToken.rowHeight2xl)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontColor(CloudThemeToken.textPrimary)
          .placeholderColor(CloudThemeToken.textSecondary)
          .backgroundColor(CloudThemeToken.surface)
          .borderRadius(CloudThemeToken.controlRadius)
          .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
          .padding({ left: CloudThemeToken.spacingSection, right: CloudThemeToken.spacingSection })
          .id(ARCHIVE_NAME_INPUT_ID)
          .onChange((value: string) => {
            this.name = value
          })
      } else {
        Text(this.archiveName)
          .width('100%')
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontColor(CloudThemeToken.textPrimary)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Column() {
        // 直接把状态变量交给子组件的 @Prop：经 @Builder 按值中转就不会随选择更新
        ArchiveFormRow({
          label: this.mode === ArchiveSheetMode.COMPRESS ? '保存到' : '解压到',
          value: this.dstFolder,
          divider: false,
          onAction: () => {
            this.showFolderPicker = true
          }
        })
        if (this.mode === ArchiveSheetMode.EXTRACT && ArchiveRules.needsEncoding(this.archiveName, this.isV4)) {
          ArchiveFormRow({
            label: '文件名编码',
            value: this.encodingLabel(),
            divider: true,
            onAction: () => {
              this.step = ArchiveStep.PICK_ENCODING
            }
          })
        }
      }
      .width('100%')
      .borderRadius(CloudThemeToken.settingGroupRadius)
      .clip(true)
      .backgroundColor(CloudMaterial.cardBackground(CloudThemeToken.surface))

      if (this.mode === ArchiveSheetMode.EXTRACT && ArchiveRules.acceptsPassword(this.archiveName, this.isV4)) {
        TextInput({ text: this.password, placeholder: '密码（没有可不填）' })
          .type(InputType.Password)
          .width('100%')
          .height(CloudThemeToken.rowHeight2xl)
          .fontSize(CloudThemeToken.textSizeLarge)
          .backgroundColor(CloudThemeToken.surface)
          .borderRadius(CloudThemeToken.controlRadius)
          .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
          .padding({ left: CloudThemeToken.spacingSection, right: CloudThemeToken.spacingSection })
          .onChange((value: string) => {
            this.password = value
          })
      }

      if (this.mode === ArchiveSheetMode.COMPRESS) {
        Text(ArchiveRules.archiveNameError(this.name).length > 0 ?
          ArchiveRules.archiveNameError(this.name) : `已选 ${this.selectedCount} 项，压缩为 zip 格式`)
          .width('100%')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(ArchiveRules.archiveNameError(this.name).length > 0 ?
            CloudThemeToken.danger : CloudThemeToken.textSecondary)
      }

      Text(this.mode === ArchiveSheetMode.COMPRESS ? '压缩' : '解压')
        .width('100%')
        .height(CloudThemeToken.rowHeightXl)
        .fontSize(CloudThemeToken.textSizeBodyPlus)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.onPrimary)
        .textAlign(TextAlign.Center)
        .borderRadius(CloudThemeToken.controlRadiusLg)
        .backgroundColor(CloudThemeToken.primary)
        .opacity(this.canSubmit() ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
        .onClick(() => {
          this.submit()
        })
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingXs,
      bottom: this.keyboardHeightVp > 0 ? this.keyboardHeightVp + CloudThemeToken.spacingSheetBottom :
        this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
  }

  @Builder encodingList() {
    Column({ space: CloudThemeToken.spacingSection }) {
      Column() {
        ForEach(ArchiveRules.ZIP_ENCODINGS, (option: ZipEncodingOption, index: number) => {
          Column() {
            if (index > 0) {
              Divider()
                .strokeWidth(CloudThemeToken.lineWidth)
                .color(CloudThemeToken.line)
                .margin({ left: CloudThemeToken.spacingPanel })
            }
            Row({ space: CloudThemeToken.spacingSm }) {
              Text(option.label)
                .fontSize(CloudThemeToken.textSizeLarge)
                .fontColor(CloudThemeToken.textPrimary)
              Text(option.hint)
                .fontSize(CloudThemeToken.textSizeSmallPlus)
                .fontColor(CloudThemeToken.textSecondary)
                .layoutWeight(1)
              if (option.value === this.encoding) {
                Image($r('app.media.ic_selected'))
                  .width(CloudThemeToken.objectMenuIconSize)
                  .height(CloudThemeToken.objectMenuIconSize)
              }
            }
            .width('100%')
            .height(CloudThemeToken.rowHeight2xl)
            .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
            .onClick(() => {
              this.encoding = option.value
              this.step = ArchiveStep.FORM
            })
          }
        }, (option: ZipEncodingOption) => option.value)
      }
      .width('100%')
      .borderRadius(CloudThemeToken.settingGroupRadius)
      .clip(true)
      .backgroundColor(CloudMaterial.cardBackground(CloudThemeToken.surface))
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingXs,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
  }
}

// 「保存到 / 解压到」「文件名编码」这类可点的行。值走 @Prop：@Builder 按值传参不会随状态重渲染
@Component
struct ArchiveFormRow {
  @Prop label: string = ''
  @Prop value: string = ''
  @Prop divider: boolean = false
  onAction?: () => void

  build() {
    Column() {
      if (this.divider) {
        Divider()
          .strokeWidth(CloudThemeToken.lineWidth)
          .color(CloudThemeToken.line)
          .margin({ left: CloudThemeToken.spacingPanel })
      }
      Row({ space: CloudThemeToken.spacingSection }) {
        Text(this.label)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontColor(CloudThemeToken.textPrimary)
        Text(this.value)
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textSecondary)
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(EllipsisMode.START)
          .layoutWeight(1)
        Image($r('app.media.ic_chevron_right'))
          .width(CloudThemeToken.iconSm)
          .height(CloudThemeToken.iconSm)
          .fillColor(CloudThemeToken.textSecondary)
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight2xl)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        pressed: { .backgroundColor(CloudThemeToken.surfaceSubtle) },
        normal: { .backgroundColor(CloudThemeToken.transparent) }
      })
      .onClick(() => this.onAction?.())
    }
  }
}
