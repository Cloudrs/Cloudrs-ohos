import { CloudThemeToken } from '../../model/CloudTheme'

export enum ChipTone {
  NEUTRAL,
  PRIMARY,
  SUCCESS,
  DANGER,
  WARNING
}

// 设置类行的主标题：16 号中粗，与系统设置列表主标题、文件菜单项一致（常规体在浅色底上显得发虚）
@Extend(Text)
function settingRowTitle(color: ResourceColor) {
  .fontSize(CloudThemeToken.textSizeLarge)
  .fontWeight(FontWeight.Medium)
  .fontColor(color)
}

@Component
export struct SettingSectionTitle {
  @Prop title: ResourceStr = ''

  build() {
    Text(this.title)
      .fontSize(CloudThemeToken.settingSectionTitleSize)
      .fontColor(CloudThemeToken.textSecondary)
      .padding({ left: CloudThemeToken.spacingSection })
      .width('100%')
  }
}

@Component
export struct SettingGroup {
  @BuilderParam content: () => void = emptyContent

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .borderRadius(CloudThemeToken.settingGroupRadius)
    .clip(true)
    .backgroundColor(CloudThemeToken.surface)
  }
}

@Builder
function emptyContent() {
}

@Component
export struct SettingChip {
  @Prop text: string = ''
  @Prop tone: ChipTone = ChipTone.NEUTRAL

  build() {
    Text(this.text)
      .fontSize(CloudThemeToken.textSizeSmall)
      .fontColor(this.chipForeground())
      .backgroundColor(this.chipBackground())
      .padding({
        left: CloudThemeToken.spacingXl,
        right: CloudThemeToken.spacingXl,
        top: CloudThemeToken.spacingTiny,
        bottom: CloudThemeToken.spacingTiny
      })
      .borderRadius(CloudThemeToken.settingChipRadius)
      .maxLines(1)
  }

  private chipForeground(): ResourceColor {
    switch (this.tone) {
      case ChipTone.PRIMARY: return CloudThemeToken.primary
      case ChipTone.SUCCESS: return CloudThemeToken.success
      case ChipTone.DANGER: return CloudThemeToken.danger
      case ChipTone.WARNING: return CloudThemeToken.warning
      default: return CloudThemeToken.textSecondary
    }
  }

  private chipBackground(): ResourceColor {
    switch (this.tone) {
      case ChipTone.PRIMARY: return CloudThemeToken.primarySoft
      case ChipTone.SUCCESS: return CloudThemeToken.successSoft
      case ChipTone.DANGER: return CloudThemeToken.dangerSoft
      case ChipTone.WARNING: return CloudThemeToken.primarySoft
      default: return CloudThemeToken.surfaceSubtle
    }
  }
}

/** 分组里的一行：可选图标 / 标题 / 描述 / 右侧值或标签 / 箭头。divider=true 时在顶部画分隔线。 */
@Component
export struct SettingRow {
  @Prop title: ResourceStr = ''
  @Prop desc: string = ''
  @Prop value: string = ''
  @Prop chipText: string = ''
  @Prop chipTone: ChipTone = ChipTone.NEUTRAL
  @Prop divider: boolean = false
  @Prop danger: boolean = false
  @Prop showChevron: boolean = true
  @Prop tappable: boolean = true
  @Prop rowEnabled: boolean = true
  // 线性图标（与底部导航栏 ic_tabbar_* 同款：描边转填充轮廓），随文字色着色，不带底色块
  icon?: ResourceStr = undefined
  onTap?: () => void

  build() {
    Column() {
      if (this.divider) {
        Divider()
          .strokeWidth(CloudThemeToken.lineWidth)
          .color(CloudThemeToken.line)
          .margin({ left: this.icon ? CloudThemeToken.settingDividerInsetIcon : CloudThemeToken.spacingPanel })
      }
      Row({ space: CloudThemeToken.spacingSection }) {
        if (this.icon) {
          Image(this.icon)
            .width(CloudThemeToken.settingLineIconSize)
            .height(CloudThemeToken.settingLineIconSize)
            .fillColor(this.danger ? CloudThemeToken.danger : CloudThemeToken.textPrimary)
            .draggable(false)
        }
        Column({ space: CloudThemeToken.spacingTiny }) {
          Text(this.title)
            .settingRowTitle(this.danger ? CloudThemeToken.danger : CloudThemeToken.textPrimary)
          if (this.desc.length > 0) {
            Text(this.desc)
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.value.length > 0) {
          Text(this.value)
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: CloudThemeToken.settingValueMaxWidth })
        }
        if (this.chipText.length > 0) {
          SettingChip({ text: this.chipText, tone: this.chipTone })
        }
        if (this.showChevron && this.tappable) {
          Image($r('app.media.ic_chevron_right'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: CloudThemeToken.rowHeight4xl })
      .padding({
        left: CloudThemeToken.spacingPanel,
        right: CloudThemeToken.spacingPanel,
        top: CloudThemeToken.spacingXl,
        bottom: CloudThemeToken.spacingXl
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .opacity(this.rowEnabled ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
    .stateStyles({
      pressed: {
        .backgroundColor(this.tappable && this.rowEnabled ? CloudThemeToken.surfaceSubtle : CloudThemeToken.transparent)
      },
      normal: {
        .backgroundColor(CloudThemeToken.transparent)
      }
    })
    .onClick(() => {
      if (this.tappable && this.rowEnabled && this.onTap) {
        this.onTap()
      }
    })
  }
}

@Component
export struct SettingSwitchRow {
  @Prop title: ResourceStr = ''
  @Prop desc: string = ''
  @Prop isOn: boolean = false
  @Prop divider: boolean = false
  @Prop busy: boolean = false
  onChange?: (isOn: boolean) => void

  build() {
    Column() {
      if (this.divider) {
        Divider().strokeWidth(CloudThemeToken.lineWidth).color(CloudThemeToken.line)
          .margin({ left: CloudThemeToken.spacingPanel })
      }
      Row({ space: CloudThemeToken.spacingSection }) {
        Column({ space: CloudThemeToken.spacingTiny }) {
          Text(this.title).settingRowTitle(CloudThemeToken.textPrimary)
          if (this.desc.length > 0) {
            Text(this.desc).fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.textSecondary)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .selectedColor(CloudThemeToken.primary)
          .enabled(!this.busy)
          .onChange((isOn: boolean) => {
            // 本地同步 @Prop：父页面若同帧内 false→true→false 拒绝了这次切换，父值回落时能把 Toggle 拉回来
            this.isOn = isOn
            this.onChange?.(isOn)
          })
      }
      .width('100%')
      .constraintSize({ minHeight: CloudThemeToken.rowHeight4xl })
      .padding({
        left: CloudThemeToken.spacingPanel,
        right: CloudThemeToken.spacingPanel,
        top: CloudThemeToken.spacingXl,
        bottom: CloudThemeToken.spacingXl
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}

/** 胶囊分段选择；label 非空时显示在分段上方 */
@Component
export struct SettingSegmentRow {
  @Prop label: string = ''
  @Prop options: string[] = []
  @Prop selectedIndex: number = 0
  @Prop divider: boolean = false
  onSelect?: (index: number) => void

  build() {
    Column({ space: CloudThemeToken.spacingCard }) {
      if (this.label.length > 0) {
        Text(this.label)
          .settingRowTitle(CloudThemeToken.textPrimary)
          .width('100%')
      }
      Row({ space: CloudThemeToken.lineWidth }) {
        ForEach(this.options, (option: string, index: number) => {
          Text(option)
            .layoutWeight(1)
            .height(CloudThemeToken.settingSegmentHeight)
            .textAlign(TextAlign.Center)
            .fontSize(CloudThemeToken.textSizeBody)
            .fontWeight(index === this.selectedIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(index === this.selectedIndex ? CloudThemeToken.textPrimary : CloudThemeToken.textSecondary)
            .borderRadius(CloudThemeToken.settingSegmentRadius)
            .backgroundColor(index === this.selectedIndex ? CloudThemeToken.segmentSelected : CloudThemeToken.transparent)
            .shadow(index === this.selectedIndex
              ? { radius: CloudThemeToken.spacingXs, color: '#1F000000', offsetY: CloudThemeToken.lineWidth }
              : { radius: 0, color: CloudThemeToken.transparent })
            .onClick(() => {
              if (index !== this.selectedIndex) {
                this.onSelect?.(index)
              }
            })
        }, (option: string) => option)
      }
      .width('100%')
      .padding(CloudThemeToken.spacingTiny)
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .backgroundColor(CloudThemeToken.surfaceSubtle)
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingPanel,
      right: CloudThemeToken.spacingPanel,
      top: CloudThemeToken.spacingSection,
      bottom: CloudThemeToken.spacingSection
    })
    .border(this.divider
      ? { width: { top: CloudThemeToken.lineWidth }, color: CloudThemeToken.line }
      : { width: 0 })
  }
}

@Component
export struct SettingStepperRow {
  @Prop title: ResourceStr = ''
  @Prop desc: string = ''
  @Prop value: number = 0
  @Prop min: number = 0
  @Prop max: number = 0
  @Prop divider: boolean = false
  onChange?: (next: number) => void

  build() {
    Column() {
      if (this.divider) {
        Divider().strokeWidth(CloudThemeToken.lineWidth).color(CloudThemeToken.line)
          .margin({ left: CloudThemeToken.spacingPanel })
      }
      Row({ space: CloudThemeToken.spacingSection }) {
        Column({ space: CloudThemeToken.spacingTiny }) {
          Text(this.title).settingRowTitle(CloudThemeToken.textPrimary)
          if (this.desc.length > 0) {
            Text(this.desc).fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.textSecondary)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          this.stepButton('−', this.value <= this.min, -1)
          Text(this.value.toString())
            .width(CloudThemeToken.icon4xl)
            .textAlign(TextAlign.Center)
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
          this.stepButton('+', this.value >= this.max, 1)
        }
        .height(CloudThemeToken.rowHeightMd)
        .borderRadius(CloudThemeToken.controlRadiusRoundMd)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
      }
      .width('100%')
      .constraintSize({ minHeight: CloudThemeToken.rowHeight4xl })
      .padding({
        left: CloudThemeToken.spacingPanel,
        right: CloudThemeToken.spacingPanel,
        top: CloudThemeToken.spacingXl,
        bottom: CloudThemeToken.spacingXl
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder stepButton(text: string, disabled: boolean, delta: number) {
    Text(text)
      .width(CloudThemeToken.rowHeightMd)
      .height(CloudThemeToken.rowHeightMd)
      .textAlign(TextAlign.Center)
      .fontSize(CloudThemeToken.textSizeTitle)
      .fontWeight(FontWeight.Bold)
      .fontColor(CloudThemeToken.textPrimary)
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .opacity(disabled ? CloudThemeToken.disabledOpacity : CloudThemeToken.fullOpacity)
      .stateStyles({
        pressed: { .backgroundColor(disabled ? CloudThemeToken.transparent : CloudThemeToken.primarySoft) },
        normal: { .backgroundColor(CloudThemeToken.transparent) }
      })
      .onClick(() => {
        if (!disabled) {
          this.onChange?.(this.value + delta)
        }
      })
  }
}
