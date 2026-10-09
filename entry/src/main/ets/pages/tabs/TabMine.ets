import { DbUserInfo } from "../../model/net/ApiTypes";
import {
  DividerShowType, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial
} from "@kit.UIDesignKit";
import Constant from "../../model/Constant";
import UserPreferences from "../../model/UserPreferences";
import { CloudThemeToken } from "../../model/CloudTheme";
import { WindowMover } from "../../utils/WindowMover";
import { CloudMaterial } from "../../model/CloudMaterial";
import { CloudScaffold } from "../../components/CloudScaffold";
import { UserSwitchSheet } from "../../components/UserSwitchSheet";
import { FeedbackSheet } from "../../components/FeedbackSheet";
import { LogViewerSheet } from "../../components/LogViewerSheet";
import { common } from "@kit.AbilityKit";
import { showCloudConfirmDialog } from "../../utils/CloudDialogUtil";
import { CloudRouter } from "../../utils/CloudRouter";
import { ActiveAccount } from "../../utils/ActiveAccount";
import { CloudApi } from "../../model/net/CloudApi";
import FeedbackUtil from "../../utils/FeedbackUtil";
import AppLogger from "../../utils/AppLogger";
import { showToast } from "../../utils/ToastUtil";
import { BusinessError, pasteboard } from "@kit.BasicServicesKit";
import { PhotoBackupSettingsStore, PHOTO_BACKUP_ENABLED_KEY } from '../../model/PhotoBackupSettingsStore';
import { ACCOUNT_PROFILE_STORE_KEY, AccountProfileStore } from '../../model/AccountProfileStore';
import { SheetPhaseController } from '../../utils/SheetPhaseController';
import { SettingGroup, SettingRow } from '../../components/settings/SettingRows';
import { MineProfileCard, MineStorageCard } from '../../components/settings/MineCards';
import { SettingsPage } from '../SettingsPage';
import { AccountSecurityPage } from '../AccountSecurityPage';
import { AboutPage } from '../AboutPage';
import { PhotoBackupPage } from '../PhotoBackupPage';

const TAG:string = 'TabMine'
// 切到「我的」时延后一点再拉数据，避开 Tab 切换动画
const MINE_REFRESH_DELAY_MS: number = 360

@Component
export struct TabMine {
  @Link overLap: boolean
  @Watch('onActiveChanged')
  @Prop isActive: boolean = false
  // 宽屏（HomePage 侧栏布局）为 true：二级页在本 Tab 内容区内原地切换，左侧导航栏保留；手机为 false，走 CloudRouter 整页推入
  @Prop inlineSubPages: boolean = false
  @StorageProp(Constant.APP_VERSION) appVersion: string = '';
  @StorageProp(Constant.WINDOW_WIDTH_VP) @Watch('onLayoutMetricChanged') sheetLayoutWidth: number = 0
  // 宽屏侧栏收起时，HomePage 的悬浮折叠键会压在页面左上角，用来给内容让位避免和头像重叠
  @StorageProp(Constant.SIDEBAR_VISIBLE) @Watch('onLayoutMetricChanged') sidebarVisible: boolean = true
  // 2in1 隐藏系统标题栏后窗口三键区宽度（其它设备为 0）；>0 时顶部加一行固定标题，卡片从其下开始
  @StorageProp(Constant.TITLE_BUTTON_INSET_END) @Watch('onLayoutMetricChanged') titleButtonInsetEnd: number = 0
  @StorageProp(PHOTO_BACKUP_ENABLED_KEY) photoBackupEnabled: boolean = false
  // 我的页顶部让位（避开折叠键）；@StorageProp 只在方法里读不会被 build 追踪，故用 @Watch 驱动 @State
  @State mineTopPadding: number = 0
  @State mineTitleLeftPadding: number = CloudThemeToken.pagePadding
  // 内容区内二级页（SETTINGS_PAGE / ACCOUNT_SECURITY_PAGE / PHOTO_BACKUP_PAGE），空串为我的页本身
  @State subPage: string = ''
  // 二级页标题栏左内边距：侧栏收起时让出悬浮折叠键
  @State subTitleStartPadding: number = CloudThemeToken.pagePadding
  @State currentUser: string = ''
  @State currentUrl: string = ''
  @State showUserSwitchSheet: boolean = false
  @State showFeedbackSheet: boolean = false
  @State showAboutSheet: boolean = false
  @State showLogViewerSheet: boolean = false
  // @Observed 单例经 AppStorage 共享；@StorageLink 订阅后字段重新赋值才会刷新 V1 组件
  @StorageLink(ACCOUNT_PROFILE_STORE_KEY) store: AccountProfileStore = AccountProfileStore.instance
  private userSwitchCtrl: SheetPhaseController = new SheetPhaseController()
  private scroller: Scroller = new Scroller()
  private refreshTimer: number = -1

  aboutToAppear(): void {
    this.onLayoutMetricChanged()
    PhotoBackupSettingsStore.mirror(PhotoBackupSettingsStore.load())
    if (this.isActive) {
      this.syncActiveAccount()
    }
  }

  aboutToDisappear(): void {
    this.cancelRefresh()
    CloudRouter.clearHomeBackHandler(this.subPageBackHandler)
    this.overLap = true
  }

  private onActiveChanged(): void {
    if (this.isActive) {
      this.syncActiveAccount()
    } else {
      this.cancelRefresh()
    }
  }

  private syncActiveAccount(): void {
    this.currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY, '') as string
    this.currentUrl = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY, '') as string
    this.store.activate(this.currentUser, this.currentUrl)
    this.cancelRefresh()
    this.refreshTimer = setTimeout(() => { this.refreshTimer = -1; this.store.refreshIfStale() }, MINE_REFRESH_DELAY_MS)
  }

  private cancelRefresh(): void {
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer)
      this.refreshTimer = -1
    }
  }

  // 宽屏且侧栏收起时，给内容顶部让出 HomePage 悬浮折叠键的高度，避免头像被压住
  private onLayoutMetricChanged(): void {
    const bp = CloudThemeToken.getBreakpoint(this.sheetLayoutWidth)
    const toggleFloating = CloudThemeToken.isWideBreakpoint(bp) && !this.sidebarVisible
    const toggleSpace = CloudThemeToken.spacingCard + CloudThemeToken.sideBarToggleSize + CloudThemeToken.spacingCard
    // 有标题行时折叠键落在标题行里，由标题行左内边距让位；否则整页下移让开折叠键
    this.mineTopPadding = (toggleFloating && this.titleButtonInsetEnd <= 0) ? toggleSpace : CloudThemeToken.zero
    // 其它 Tab 的 HdsTitleBar 标题文字距内容左缘约 20vp（MateBook 实测），这里对齐它而不是 pagePadding
    this.mineTitleLeftPadding = toggleFloating ? toggleSpace : CloudThemeToken.pagePadding + CloudThemeToken.spacingXs
    this.subTitleStartPadding = toggleFloating ? toggleSpace : CloudThemeToken.pagePadding
  }

  // 二级页打开期间的返回处理器；保留引用以便只清自己注册的那个
  private subPageBackHandler: () => boolean = (): boolean => {
    if (this.subPage.length === 0) {
      return false
    }
    this.closeSubPage()
    return true
  }

  private openSubPage(page: string): void {
    if (!this.inlineSubPages) {
      CloudRouter.push(page)
      return
    }
    this.subPage = page
    // 返回键（平板手势 / 2in1 Esc）先退回我的页；HomePage 宽屏下文件页已销毁，不会抢这个处理器
    CloudRouter.setHomeBackHandler(this.subPageBackHandler)
  }

  private closeSubPage(): void {
    this.subPage = ''
    CloudRouter.clearHomeBackHandler(this.subPageBackHandler)
  }

  @Builder subPageView() {
    if (this.subPage === Constant.SETTINGS_PAGE) {
      SettingsPage({ titleStartPadding: this.subTitleStartPadding, onBack: () => this.closeSubPage() })
    } else if (this.subPage === Constant.ACCOUNT_SECURITY_PAGE) {
      AccountSecurityPage({ titleStartPadding: this.subTitleStartPadding, onBack: () => this.closeSubPage() })
    } else if (this.subPage === Constant.PHOTO_BACKUP_PAGE) {
      PhotoBackupPage({ titleStartPadding: this.subTitleStartPadding, onBack: () => this.closeSubPage() })
    }
  }

  // 2in1：与文件页「存储」、相册页「相册」同一行位置的标题，放在 HDS 标题栏里，兼作窗口拖动区（行内无按钮）
  @Builder mineTitleRow() {
    Row() {
      Text('我的')
        .fontSize(CloudThemeToken.textSizeHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
        .maxLines(1)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.mineTitleLeftPadding,
      right: CloudThemeToken.pagePadding + this.titleButtonInsetEnd
    })
    .alignItems(VerticalAlign.Center)
    .onTouch((event: TouchEvent) => {
      WindowMover.onTouch(event)
    })
  }

  // 内容顶部让位：2in1 让出 HDS 标题栏（内容从标题栏底下滚过）；其余设备按折叠键让位
  private getContentTopPadding(): number {
    return this.titleButtonInsetEnd > 0 ? CloudThemeToken.rowHeight5xl + CloudThemeToken.spacingXs : this.mineTopPadding
  }

  @Builder mineContent() {
    // 自定义组件尾随闭包后不能再链属性，故外包一层
    Column() {
      CloudScaffold({
        scroller: this.scroller,
        topPadding: this.getContentTopPadding(),
        bottomPadding: CloudThemeToken.pageBottomPadding
      }) {
        Column({ space: CloudThemeToken.sectionGap }) {
          MineProfileCard({ onOpen: () => this.openSubPage(Constant.ACCOUNT_SECURITY_PAGE) })
          MineStorageCard()
          this.entryGroups()
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  // 2in1：与文件页、相册页、下载页一样走 HDS 标题栏，上滑时内容从标题栏底下穿过、标题栏渐变出沉浸模糊
  @Builder mineWithTitleBar() {
    HdsNavigation() {
      this.mineContent()
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: ' '
        },
        stackBuilder: () => {
          this.mineTitleRow()
        },
        divider: {
          showType: DividerShowType.OFF
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        // 标题是空占位，但两态都得给标题色：开了滚动效果后 HDS 按它推状态栏图标深浅，缺省会推成白色
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.scroller])
    .backgroundColor(CloudThemeToken.background)
  }

  build() {
    Stack() {
      if (this.subPage.length > 0) {
        this.subPageView()
      } else if (this.titleButtonInsetEnd > 0) {
        this.mineWithTitleBar()
      } else {
        this.mineContent()
      }

      this.sheetHosts()
    }
    .width('100%')
    .height('100%')
  }

  @Builder entryGroups() {
    SettingGroup() {
      SettingRow({
        title: '相册备份', value: this.photoBackupEnabled ? '已开启' : '未开启',
        icon: $r('app.media.ic_mine_backup'),
        onTap: () => this.openSubPage(Constant.PHOTO_BACKUP_PAGE)
      })
      SettingRow({
        title: '账号与安全', value: this.securityValue(), divider: true,
        icon: $r('app.media.ic_mine_security'),
        onTap: () => this.openSubPage(Constant.ACCOUNT_SECURITY_PAGE)
      })
      SettingRow({
        title: '设置', divider: true,
        icon: $r('app.media.ic_mine_settings'),
        onTap: () => this.openSubPage(Constant.SETTINGS_PAGE)
      })
    }

    SettingGroup() {
      SettingRow({
        title: $r('app.string.feedback'),
        icon: $r('app.media.ic_mine_feedback'),
        onTap: () => {
          this.showFeedbackSheet = true
        }
      })
      SettingRow({
        title: $r('app.string.about'), value: this.appVersion, divider: true,
        icon: $r('app.media.ic_mine_about'),
        // 与反馈一样用半模态（宽屏为居中弹窗）：反馈、关于是信息 / 操作类，不进二级页
        onTap: () => {
          this.showAboutSheet = true
        }
      })
    }

    SettingGroup() {
      SettingRow({
        title: '切换账号',
        icon: $r('app.media.ic_mine_switch_account'),
        onTap: () => this.userSwitchCtrl.requestOpen(() => this.showUserSwitchSheet, (v: boolean) => {
          this.showUserSwitchSheet = v
        })
      })
      Row() {
        Text($r('app.string.logout'))
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.danger)
      }
      .width('100%')
      .height(CloudThemeToken.rowHeight4xl)
      .justifyContent(FlexAlign.Center)
      .border({ width: { top: CloudThemeToken.lineWidth }, color: CloudThemeToken.line })
      .stateStyles({
        pressed: { .backgroundColor(CloudThemeToken.surfaceSubtle) },
        normal: { .backgroundColor(CloudThemeToken.transparent) }
      })
      .onClick(() => this.confirmLogout())
    }
  }

  @Builder sheetHosts() {
    Column().width(0).height(0)
      .bindSheet($$this.showUserSwitchSheet, this.userSwitchSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        // 宽屏居中弹窗不认 detents，高度单独给成按内容
        height: SheetSize.FIT_CONTENT,
        title: { title: '选择账号' },
        showClose: true,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onWillAppear: () => this.userSwitchCtrl.onWillAppear(),
        onAppear: () => this.userSwitchCtrl.onAppear(),
        onWillDisappear: () => this.userSwitchCtrl.onWillDisappear(),
        onDisappear: () => this.userSwitchCtrl.onDisappear((v: boolean) => { this.showUserSwitchSheet = v }, () => {})
      })

    Column().width(0).height(0)
      .bindSheet($$this.showFeedbackSheet, this.feedbackSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        // 宽屏居中弹窗不认 detents，高度单独给成按内容
        height: SheetSize.FIT_CONTENT,
        title: { title: '问题反馈', subtitle: '优先邮件反馈，附带日志和诊断信息方便快速定位' },
        showClose: true,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth)
      })

    Column().width(0).height(0)
      .bindSheet($$this.showAboutSheet, this.aboutSheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        title: { title: $r('app.string.about') },
        showClose: true,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onDisappear: () => {
          this.showAboutSheet = false
        }
      })

    Column().width(0).height(0)
      .bindSheet($$this.showLogViewerSheet, this.logViewerSheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        title: { title: '日志与诊断', subtitle: '已脱敏 · 复制诊断会一并带上日志尾部' },
        showClose: true,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth)
      })
  }

  @Builder userSwitchSheet() {
    UserSwitchSheet({
      currentUser: this.currentUser,
      currentUrl: this.currentUrl,
      onSelect: (user: DbUserInfo) => {
        // 过期账号会跳登录页，得先把 sheet 关掉再跳
        if (CloudRouter.switchToUser(user.username, user.url, () => { this.closeUserSwitch() })) {
          this.closeUserSwitch()
          this.syncActiveAccount()
        }
      },
      onClose: () => this.closeUserSwitch()
    })
  }

  private closeUserSwitch(): void {
    this.userSwitchCtrl.requestClose((v: boolean) => { this.showUserSwitchSheet = v })
  }

  private confirmLogout(): void {
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.logout_confim'),
      message: '账号会保留在「切换账号」列表里，下次可直接切回',
      confirmText: $r('app.string.dialog_logout'),
      onConfirm: () => {
        // 先丢掉 native 里这个账号的 refresh token：否则登录页对同一服务器的请求可能续期轮换它，
        // 新 token 无活动账号可落库，「切换账号」里保存的凭据就作废了
        CloudApi.clearSession()
        ActiveAccount.clear()
        CloudRouter.resetToLogin()
      }
    })
  }

  private securityValue(): string {
    const account = this.store.account
    return (this.store.isV3() || !account) ? '' : (account.two_fa_enabled ? '两步验证已开启' : '两步验证未开启')
  }

  private closeFeedbackSheet(): void {
    this.showFeedbackSheet = false
  }

  private openExternalUrl(url: string): void {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      showToast('无法打开链接')
      return
    }

    const context = hostContext as common.UIAbilityContext
    context.startAbility({
      action: 'ohos.want.action.viewData',
      uri: url,
      entities: ['entity.system.browsable']
    }).catch((err: BusinessError) => {
      AppLogger.error(TAG, `open external url failed: ${err.code}, ${err.message}`)
      showToast('无法打开浏览器')
    })
  }

  private buildFeedbackDiagnostic(): string {
    return FeedbackUtil.buildDiagnosticMarkdown({
      appVersion: this.appVersion,
      serverUrl: this.currentUrl,
      account: this.currentUser,
      user: this.store.user,
      recentLogs: AppLogger.getRecentText(60),
      logFilePath: AppLogger.getFilePath()
    })
  }

  private copyFeedbackDiagnostic(): void {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.buildFeedbackDiagnostic())
      pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
        showToast($r('app.string.copy_success'))
      }).catch((err: Error) => {
        AppLogger.error(TAG, 'copy feedback diagnostic failed: ' + err.message)
        showToast($r('app.string.copy_failed'))
      })
    } catch (err) {
      AppLogger.error(TAG, 'copy feedback diagnostic failed: ' + JSON.stringify(err))
      showToast($r('app.string.copy_failed'))
    }
  }

  private openFeedbackIssue(): void {
    this.copyFeedbackDiagnostic()
    this.openExternalUrl(FeedbackUtil.buildIssueUrl({
      appVersion: this.appVersion,
      serverUrl: this.currentUrl,
      account: this.currentUser,
      user: this.store.user
    }))
    this.closeFeedbackSheet()
  }

  private openFeedbackMail(): void {
    this.copyFeedbackDiagnostic()
    this.openExternalUrl(FeedbackUtil.buildMailUrl({
      appVersion: this.appVersion,
      serverUrl: this.currentUrl,
      account: this.currentUser,
      user: this.store.user
    }))
    this.closeFeedbackSheet()
  }

  private openLogViewer(): void {
    this.closeFeedbackSheet()
    this.showLogViewerSheet = true
  }

  @Builder aboutSheet() {
    AboutPage()
  }

  @Builder logViewerSheet() {
    LogViewerSheet({
      onCopyDiagnostic: () => {
        this.copyFeedbackDiagnostic()
      },
      onClose: () => {
        this.showLogViewerSheet = false
      }
    })
  }

  @Builder feedbackSheet() {
    FeedbackSheet({
      onMail: () => {
        this.openFeedbackMail()
      },
      onIssue: () => {
        this.openFeedbackIssue()
      },
      onViewLogs: () => {
        this.openLogViewer()
      },
      onClose: () => {
        this.closeFeedbackSheet()
      }
    })
  }
}
