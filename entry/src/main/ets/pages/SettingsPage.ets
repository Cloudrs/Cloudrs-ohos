import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { AppSettings } from '../model/AppSettings'
import { PrivacyConsentStore } from '../model/PrivacyConsentStore'
import { CloudApi } from '../model/net/CloudApi'
import { HoldingHandUtil } from '../utils/HoldingHandUtil'
import { ActiveAccount } from '../utils/ActiveAccount'
import { CloudRouter } from '../utils/CloudRouter'
import { showCloudConfirmDialog } from '../utils/CloudDialogUtil'
import { showToast } from '../utils/ToastUtil'
import AppLogger from '../utils/AppLogger'
import { SubPageScaffold } from '../components/SubPageScaffold'
import {
  SettingGroup, SettingRow, SettingSectionTitle, SettingSegmentRow, SettingStepperRow, SettingSwitchRow
} from '../components/settings/SettingRows'

const TAG: string = 'SettingsPage'

const THEME_MODES: string[] = [Constant.APP_THEME_LIGHT, Constant.APP_THEME_DARK, Constant.APP_THEME_SYSTEM]
const THEME_LABELS: string[] = ['浅色', '深色', '跟随系统']
const KNOCK_EXPIRE_DAYS: number[] = [1, 7, 30, 0]
const KNOCK_EXPIRE_LABELS: string[] = ['1 天', '7 天', '30 天', '永久']

/** 本机设置：所有项行内即改即存，不再弹窗 */
@Component
export struct SettingsPage {
  // 宽屏在「我的」内容区内打开时由 TabMine 传入：标题栏左内边距（让出悬浮折叠键）与返回回调；
  // 未传时 -1 / undefined，走默认 pagePadding 与 CloudRouter.pop()
  @Prop titleStartPadding: number = -1
  onBack?: () => void
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  private scroller: Scroller = new Scroller()
  @State themeIndex: number = 0
  @State uploadConcurrent: number = Constant.UPLOAD_CONCURRENT_DEFAULT
  @State imageDraggable: boolean = false
  @State imageAiAnalyzer: boolean = true
  @State knockUseShareLink: boolean = false
  @State knockExpireIndex: number = 0
  @State knockPassword: boolean = false
  @State smartGrip: boolean = true
  // 进页面时探测一次（订阅+立即退订，结论缓存），不支持的机型开关置灰
  @State smartGripSupported: boolean = true

  aboutToAppear(): void {
    this.themeIndex = Math.max(0, THEME_MODES.indexOf(AppSettings.getThemeMode()))
    this.uploadConcurrent = AppSettings.getUploadConcurrent()
    this.imageDraggable = AppSettings.getBool(Constant.IMAGE_DRAGGABLE_ENABLED, false)
    this.imageAiAnalyzer = AppSettings.getBool(Constant.IMAGE_AI_ANALYZER_ENABLED, true)
    this.knockUseShareLink = AppSettings.getBool(Constant.KNOCK_SHARE_USE_SHARE_LINK, false)
    this.knockExpireIndex = Math.max(0, KNOCK_EXPIRE_DAYS.indexOf(AppSettings.getKnockExpireDays()))
    this.knockPassword = AppSettings.getBool(Constant.KNOCK_SHARE_PASSWORD_ENABLED, false)
    this.smartGrip = HoldingHandUtil.isEnabled()
    this.smartGripSupported = HoldingHandUtil.isSupported()
  }

  build() {
    SubPageScaffold({
      title: '设置', startPadding: this.titleStartPadding, scroller: this.scroller, onBackClick: this.onBack
    }) {
      // 内容铺满全页、从标题栏底下滚过（顶部留出标题栏高度），上滑时标题栏出模糊材质
      Scroll(this.scroller) {
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
            SettingSectionTitle({ title: '单手操作' })
            this.gripGroup()
          }
          .width('100%')
          Column({ space: CloudThemeToken.spacingXl }) {
            SettingSectionTitle({ title: '碰一碰分享' })
            this.knockGroup()
          }
          .width('100%')
          Column({ space: CloudThemeToken.spacingXl }) {
            SettingSectionTitle({ title: '隐私' })
            this.privacyGroup()
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
          top: CloudThemeToken.hdsTitleBarHeight(this.topRectHeight) + CloudThemeToken.spacingXs,
          bottom: this.bottomRectHeight + CloudThemeToken.pageBottomPadding
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
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

  @Builder gripGroup() {
    SettingGroup() {
      if (this.smartGripSupported) {
        SettingSwitchRow({
          title: '智感握姿',
          desc: '文件页上传按钮、相册切换按钮跟随握持手靠左或靠右',
          isOn: this.smartGrip,
          onChange: (isOn: boolean) => {
            this.smartGrip = isOn
            // 同时镜像进 AppStorage，文件页、相册页即时增减订阅
            HoldingHandUtil.setEnabled(isOn)
          }
        })
      } else {
        Column() {
          SettingSwitchRow({ title: '智感握姿', desc: '当前设备不支持', isOn: false, busy: true })
        }
        .opacity(CloudThemeToken.disabledOpacity)
      }
    }
  }

  // 规范要求应用内能查看隐私政策、能撤回同意；登录后原本只有登录页才有隐私政策链接
  @Builder privacyGroup() {
    SettingGroup() {
      SettingRow({
        title: '隐私政策',
        onTap: () => {
          this.openPrivacyPolicy()
        }
      })
      SettingRow({
        title: '撤回隐私政策同意',
        desc: '撤回后退出当前账号，再次使用需重新同意',
        danger: true,
        divider: true,
        onTap: () => {
          this.confirmRevokePrivacy()
        }
      })
    }
  }

  private openPrivacyPolicy(): void {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      showToast('无法打开链接')
      return
    }
    (hostContext as common.UIAbilityContext).startAbility({
      action: 'ohos.want.action.viewData',
      uri: PrivacyConsentStore.policyUrl(),
      entities: ['entity.system.browsable']
    }).catch((err: BusinessError) => {
      AppLogger.error(TAG, `open privacy policy failed: ${err.code}, ${err.message}`)
      showToast('无法打开浏览器')
    })
  }

  private confirmRevokePrivacy(): void {
    showCloudConfirmDialog(this.getUIContext(), {
      title: '撤回隐私政策同意？',
      message: '撤回后将退出当前账号，下次打开应用需重新阅读并同意隐私政策才能继续使用。\n' +
        '本机保存的账号记录不会删除，可在登录页「已保存账号」中删除。',
      confirmText: '撤回',
      onConfirm: () => {
        AppLogger.info(TAG, 'revoke privacy consent')
        PrivacyConsentStore.revoke()
        // 与「我的 → 退出登录」同一套：先丢掉 native 里的 refresh token，免得登录页的请求续期轮换掉已保存的凭据
        CloudApi.clearSession()
        ActiveAccount.clear()
        CloudRouter.resetToLogin()
      }
    })
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
