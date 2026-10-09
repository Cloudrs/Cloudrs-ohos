import { common } from '@kit.AbilityKit'
import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { AppSettings } from '../model/AppSettings'
import { CommonTitle } from '../components/CommonTitle'
import {
  SettingGroup, SettingSectionTitle, SettingSegmentRow, SettingStepperRow, SettingSwitchRow
} from '../components/settings/SettingRows'

const THEME_MODES: string[] = [Constant.APP_THEME_LIGHT, Constant.APP_THEME_DARK, Constant.APP_THEME_SYSTEM]
const THEME_LABELS: string[] = ['浅色', '深色', '跟随系统']
const KNOCK_EXPIRE_DAYS: number[] = [1, 7, 30, 0]
const KNOCK_EXPIRE_LABELS: string[] = ['1 天', '7 天', '30 天', '永久']

/** 本机设置：所有项行内即改即存，不再弹窗 */
@Component
export struct SettingsPage {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @State themeIndex: number = 0
  @State uploadConcurrent: number = Constant.UPLOAD_CONCURRENT_DEFAULT
  @State imageDraggable: boolean = false
  @State imageAiAnalyzer: boolean = true
  @State knockUseShareLink: boolean = false
  @State knockExpireIndex: number = 0
  @State knockPassword: boolean = false

  aboutToAppear(): void {
    this.themeIndex = Math.max(0, THEME_MODES.indexOf(AppSettings.getThemeMode()))
    this.uploadConcurrent = AppSettings.getUploadConcurrent()
    this.imageDraggable = AppSettings.getBool(Constant.IMAGE_DRAGGABLE_ENABLED, false)
    this.imageAiAnalyzer = AppSettings.getBool(Constant.IMAGE_AI_ANALYZER_ENABLED, true)
    this.knockUseShareLink = AppSettings.getBool(Constant.KNOCK_SHARE_USE_SHARE_LINK, false)
    this.knockExpireIndex = Math.max(0, KNOCK_EXPIRE_DAYS.indexOf(AppSettings.getKnockExpireDays()))
    this.knockPassword = AppSettings.getBool(Constant.KNOCK_SHARE_PASSWORD_ENABLED, false)
  }

  build() {
    Column() {
      CommonTitle({ title: '设置' })
      Scroll() {
        Column({ space: CloudThemeToken.sectionGap }) {
          Column({ space: CloudThemeToken.spacingXl }) {
            SettingSectionTitle({ title: '外观' })
            this.themeGroup()
          }
          .width('100%')
          Column({ space: CloudThemeToken.spacingXl }) {
            SettingSectionTitle({ title: '传输' })
            this.transferGroup()
          }
          .width('100%')
          Column({ space: CloudThemeToken.spacingXl }) {
            SettingSectionTitle({ title: '图片预览' })
            this.imageGroup()
          }
          .width('100%')
          Column({ space: CloudThemeToken.spacingXl }) {
            SettingSectionTitle({ title: '碰一碰分享' })
            this.knockGroup()
          }
          .width('100%')
          Text('以上设置只保存在本机，不同步到服务器')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({
          left: CloudThemeToken.pagePadding,
          right: CloudThemeToken.pagePadding,
          top: CloudThemeToken.spacingXs,
          bottom: this.bottomRectHeight + CloudThemeToken.pageBottomPadding
        })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder themeGroup() {
    SettingGroup() {
      SettingSegmentRow({
        options: THEME_LABELS,
        selectedIndex: this.themeIndex,
        onSelect: (index: number) => {
          this.themeIndex = index
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext
          AppSettings.setThemeMode(context, THEME_MODES[index])
        }
      })
    }
  }

  @Builder transferGroup() {
    SettingGroup() {
      SettingStepperRow({
        title: '同时上传任务数',
        desc: '数量越多越占带宽，弱网时建议调低',
        value: this.uploadConcurrent,
        min: Constant.UPLOAD_CONCURRENT_MIN,
        max: Constant.UPLOAD_CONCURRENT_MAX,
        onChange: (next: number) => {
          this.uploadConcurrent = AppSettings.setUploadConcurrent(next)
        }
      })
    }
  }

  @Builder imageGroup() {
    SettingGroup() {
      SettingSwitchRow({
        title: '图片拖拽',
        desc: '预览时长按可把图片拖到其他应用',
        isOn: this.imageDraggable,
        onChange: (isOn: boolean) => {
          this.imageDraggable = isOn
          AppSettings.setBool(Constant.IMAGE_DRAGGABLE_ENABLED, isOn)
        }
      })
      SettingSwitchRow({
        title: '长按智能识图',
        desc: '预览时长按提取主体或文字',
        isOn: this.imageAiAnalyzer,
        divider: true,
        onChange: (isOn: boolean) => {
          this.imageAiAnalyzer = isOn
          AppSettings.setBool(Constant.IMAGE_AI_ANALYZER_ENABLED, isOn)
        }
      })
    }
  }

  @Builder knockGroup() {
    SettingGroup() {
      SettingSwitchRow({
        title: '发送分享链接',
        desc: '未下载到本机的文件改为发送分享链接',
        isOn: this.knockUseShareLink,
        onChange: (isOn: boolean) => {
          this.knockUseShareLink = isOn
          AppSettings.setBool(Constant.KNOCK_SHARE_USE_SHARE_LINK, isOn)
        }
      })
      if (this.knockUseShareLink) {
        SettingSegmentRow({
          label: '链接有效期',
          options: KNOCK_EXPIRE_LABELS,
          selectedIndex: this.knockExpireIndex,
          divider: true,
          onSelect: (index: number) => {
            this.knockExpireIndex = index
            AppSettings.setKnockExpireDays(KNOCK_EXPIRE_DAYS[index])
          }
        })
        SettingSwitchRow({
          title: '附带提取码',
          desc: '生成随机提取码，碰完后提示',
          isOn: this.knockPassword,
          divider: true,
          onChange: (isOn: boolean) => {
            this.knockPassword = isOn
            AppSettings.setBool(Constant.KNOCK_SHARE_PASSWORD_ENABLED, isOn)
          }
        })
      }
    }
  }
}
