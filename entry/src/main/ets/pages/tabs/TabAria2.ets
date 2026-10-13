import Constant from "../../model/Constant";
import { Aria2Downloading,
  Aria2Files,
  Aria2Finished, Aria2FinishedList, Aria2Status,
  UserTask, UserTasks } from "../../model/net/ApiTypes";
import { CloudApi } from "../../model/net/CloudApi";
import { ContentItem, LengthMetrics, SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import {
  DividerShowType, HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial
} from "@kit.UIDesignKit";
import LazyDataSource from "../../utils/LazyDataSource";
import { Aria2FinishedDetail } from "../../components/Aria2FinishedDetail";
import { TaskQueueDetail } from "../../components/TaskQueueDetail";
import { TASK_STATUS_COMPLETED, TASK_STATUS_ERROR, TASK_STATUS_PROCESSING, TaskQueueText } from "../../utils/TaskQueueText";
import { CommonUtil } from "../../utils/CommonUtil";
import { Aria2Create } from "../../components/Aria2Create";
import { showToast, showToastTips, ToastType } from "../../utils/ToastUtil";

import { CloudThemeToken } from "../../model/CloudTheme";
import { CloudMaterial } from "../../model/CloudMaterial";
import AppLogger from "../../utils/AppLogger";
import { WindowMover } from "../../utils/WindowMover";
import { EmptyState } from "../../components/EmptyState";

import { DateFormatUtil } from "../../utils/DateFormatUtil";
import { showCloudConfirmDialog } from "../../utils/CloudDialogUtil";
import { ActiveAccount } from "../../utils/ActiveAccount";

const TAG: string = 'TabRemote'

@Component
export struct TabRemoteDown {
  @Link overLap: boolean
  @Watch('onActiveStateChanged')
  @Prop isActive: boolean = false
  // 首页常驻，切换账号不会重建本组件，靠这个信号丢弃上一账号的离线下载/任务队列
  @Watch('onAccountChanged')
  @StorageProp(Constant.ACTIVE_ACCOUNT_SCOPE) accountScope: string = ''
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  // 其它页面请求切到某个分段（如压缩浮条的「查看」→ 任务队列），处理完复位为 -1
  @Watch('onSegmentRequest')
  @StorageLink(Constant.ARIA2_SEGMENT_REQUEST) segmentRequest: number = -1
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0;
  // 2in1 窗口三键区宽度；其它设备为 0
  @StorageProp(Constant.TITLE_BUTTON_INSET_END) titleButtonInsetEnd: number = 0;
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @State selectCapsuleOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: $r('app.string.download_offline') }, { text: $r('app.string.task_queue') }] as SegmentButtonItemTuple,
    multiply: false,
    backgroundBlurStyle: BlurStyle.BACKGROUND_THICK
  })
  @State aria2Downloading: Aria2Downloading[] = []
  private aria2FinishedSource: LazyDataSource<Aria2Finished> = new LazyDataSource()
  private tasksQueueSource: LazyDataSource<UserTask> = new LazyDataSource()
  @State totalFinished: number = 0;
  @State totalTasks: number = 0;
  @State totalDownloading: number = 0;
  @State selectedIndexes: number[] = [CloudThemeToken.primarySegmentIndex]
  @State downloadRefresh: boolean = false
  @State tasksQueueRefresh: boolean = false
  // 下拉距离，驱动标题栏下方的刷新提示（两个分段同一时刻只挂一个 Refresh，共用即可）
  @State refreshPullOffset: number = 0
  // 两个列表都由 native 一次拉全，不再翻页；超过上限时 truncated 为 true，底部提示更早的没拉
  @State finishedTruncated: boolean = false
  @State tasksQueueTruncated: boolean = false
  // 列表请求序号：每次整表拉取 +1（换账号也 +1），回调序号对不上就丢弃，
  // 免得慢回来的旧响应盖掉新结果
  private finishedRequestSeq: number = 0
  private tasksQueueRequestSeq: number = 0
  private scroller: Scroller = new Scroller()
  private tasksQueueScroller: Scroller = new Scroller()
  @State currentFinishedDetail: Aria2Finished|undefined = undefined
  @State currentFinishedIndex: number = -1
  @State showTaskDetailSheet: boolean = false
  // 任务队列点卡片看详情：卡片放不下的长文件名 / 路径 / 失败原因
  @State currentQueueTask: UserTask|undefined = undefined
  @State showQueueTaskSheet: boolean = false
  private timerId?: number = undefined
  @State showCreateSheet: boolean = false
  // v4 只有管理员能删已结束的任务记录（普通用户压根没有这个接口），v3 谁都能删。
  // 权限在这里问一次，决定详情页要不要给删除按钮。
  @State canDeleteFinished: boolean = false
  // 只有真的问出结果才算数；失败不置位，留给下次切回本页重试
  private deletePermissionResolved: boolean = false
  private initialDataRequested: boolean = false
  // 浮条「查看」跳来时任务队列可能是早先拉的，看不到刚提交的任务；等本页变成活动页再拉一次
  private queueRefreshPending: boolean = false
  private loadedAccountScope: string = ''

  aboutToAppear(): void {
    this.loadedAccountScope = ActiveAccount.current()
    // TabContent 首次切到才创建，分段请求可能在创建前就写进了 AppStorage，@Watch 不会对初始值触发
    this.onSegmentRequest()
    this.loadInitialDataIfActive()
    this.refreshDeletePermission()
  }

  aboutToDisappear(): void {
    this.clearDownloadUpdateTask()
  }

  onActiveStateChanged(): void {
    if (!this.isActive) {
      this.clearDownloadUpdateTask()
      return
    }
    this.loadInitialDataIfActive()
    this.refreshQueueIfPending()
    // 和列表不同，权限只要还没问出结果就每次切回本页重试一次：
    // 本组件首页常驻，被 initialDataRequested 挡住的话一次网络抖动
    // 就会让管理员整个会话都看不到删除按钮
    this.refreshDeletePermission()
  }

  /** 账号切换：丢掉上一账号的列表，重新按新账号拉取（非活动时留待切回本页再拉） */
  private onAccountChanged(): void {
    const scope = this.accountScope
    if (scope.length === 0 || scope === this.loadedAccountScope) {
      return
    }
    AppLogger.info(TAG, 'account switched, reset remote download lists')
    this.loadedAccountScope = scope
    this.clearDownloadUpdateTask()
    this.aria2Downloading = []
    this.totalDownloading = 0
    this.aria2FinishedSource.clear()
    this.totalFinished = 0
    this.finishedTruncated = false
    this.finishedRequestSeq++
    this.tasksQueueSource.clear()
    this.totalTasks = 0
    this.tasksQueueTruncated = false
    this.tasksQueueRequestSeq++
    this.showTaskDetailSheet = false
    this.currentFinishedDetail = undefined
    this.currentFinishedIndex = -1
    this.showQueueTaskSheet = false
    this.currentQueueTask = undefined
    this.canDeleteFinished = false
    this.deletePermissionResolved = false
    this.initialDataRequested = false
    this.queueRefreshPending = false
    this.loadInitialDataIfActive()
    this.refreshDeletePermission()
  }

  private onSegmentRequest(): void {
    if (this.segmentRequest < 0) {
      return
    }
    const index = this.segmentRequest
    this.segmentRequest = -1
    this.selectedIndexes = [index]
    // 还没拉过的话首拉就是最新的，不用补
    if (index === Constant.ARIA2_TASK_QUEUE_SEGMENT && this.initialDataRequested) {
      this.queueRefreshPending = true
      this.refreshQueueIfPending()
    }
  }

  private refreshQueueIfPending(): void {
    if (!this.queueRefreshPending || !this.isActive) {
      return
    }
    this.queueRefreshPending = false
    this.getUserTasks()
  }

  private loadInitialDataIfActive(): void {
    if (!this.isActive || this.initialDataRequested) {
      return
    }
    this.initialDataRequested = true
    this.getAria2Downloading()
    this.getAria2Finished()
    this.getUserTasks()
  }

  private refreshDeletePermission(): void {
    if (!this.isActive || this.deletePermissionResolved) {
      return
    }
    // 回调回来时账号可能已经换了，旧账号的慢响应不能回填到新账号的权限上
    const scope = this.loadedAccountScope
    CloudApi.canDeleteFinishedAria2Task({
      onSuccess: (allowed: boolean) => {
        if (scope !== this.loadedAccountScope) {
          AppLogger.info(TAG, 'drop stale delete permission result')
          return
        }
        this.deletePermissionResolved = true
        this.canDeleteFinished = allowed
        AppLogger.info(TAG, 'can delete finished task: ' + allowed)
      },
      onFailure: (msg) => {
        if (scope !== this.loadedAccountScope) {
          return
        }
        // 不置 resolved，切回本页时再试一次
        this.canDeleteFinished = false
        AppLogger.warn(TAG, 'check delete permission failed: ' + msg)
      }
    })
  }

  startDownloadUpdateTask(interval: number) {
    if (!this.isActive) {
      return
    }
    if (this.timerId === undefined) {
      this.timerId = setInterval(() => {
        this.getAria2Downloading(true)
      }, interval)
    }
  }

  clearDownloadUpdateTask() {
    if (this.timerId != undefined) {
      clearInterval(this.timerId)
      this.timerId = undefined
    }
  }

  /**
   * @param refreshFinishedOnEnd 轮询时传 true：有任务从「下载中」消失（结束了）才重拉已完成列表，
   *   不再每轮都整表重拉
   */
  getAria2Downloading(refreshFinishedOnEnd: boolean = false) {
    if (!this.isActive) {
      return
    }
    CloudApi.aria2Downloading({
      onSuccess: (data) => {
        if (!this.isActive) {
          return
        }
        if (refreshFinishedOnEnd && this.hasEndedDownload(this.aria2Downloading, data)) {
          this.getAria2Finished()
        }
        if (data.length > 0) {
          this.aria2Downloading = data
          this.totalDownloading = this.aria2Downloading.length
          const intervalSeconds =
            Math.max(data[Constant.FIRST_ARRAY_INDEX].interval, Constant.ARIA2_MIN_UPDATE_INTERVAL_SECONDS)
          this.startDownloadUpdateTask(intervalSeconds * Constant.MILLISECONDS_PER_SECOND)
          console.debug(TAG, 'downloading number: ' + this.totalDownloading)
        } else {
          AppLogger.warn(TAG, 'no downloading task')
          this.aria2Downloading = []
          this.totalDownloading = 0
          this.clearDownloadUpdateTask()
        }
      },
      onFailure: (msg) => {
        this.aria2Downloading = []
        this.totalDownloading = 0
        this.clearDownloadUpdateTask()
        AppLogger.error(TAG, 'Aria2 downloading get failed, msg: ' + msg)
      }
    })
  }

  /** 上一轮还在下载、这一轮不见了的任务，说明已经结束（进了已完成列表） */
  private hasEndedDownload(previous: Aria2Downloading[], current: Aria2Downloading[]): boolean {
    const currentGids = new Set<string>(current.map((item: Aria2Downloading) => this.getDownloadingGid(item)))
    return previous.some((item: Aria2Downloading) => !currentGids.has(this.getDownloadingGid(item)))
  }

  // 拉取期间旧列表照常显示，回来后整表替换，不会先闪一下空状态。
  // 切走本页时回来的结果也照收：首次加载只发一次，丢了就要等用户手动下拉
  getAria2Finished() {
    if (!this.isActive) {
      return
    }
    this.finishedRequestSeq++
    const requestSeq = this.finishedRequestSeq
    CloudApi.aria2Finished({
      onSuccess: (data: Aria2FinishedList) => {
        if (requestSeq !== this.finishedRequestSeq) {
          AppLogger.info(TAG, 'drop stale finished list')
          return
        }
        this.aria2FinishedSource.replaceAll(data.tasks)
        this.totalFinished = this.aria2FinishedSource.totalCount()
        this.finishedTruncated = data.truncated
        this.downloadRefresh = false
        console.debug(TAG, `finished number: ${this.totalFinished}, truncated: ${data.truncated}`)
      },
      onFailure: (msg) => {
        if (requestSeq !== this.finishedRequestSeq) {
          return
        }
        this.downloadRefresh = false
        AppLogger.error(TAG, 'Aria2 finished get failed, msg: ' + msg)
      }
    })
  }

  getUserTasks() {
    if (!this.isActive) {
      return
    }
    this.tasksQueueRequestSeq++
    const requestSeq = this.tasksQueueRequestSeq
    CloudApi.userTasks({
      onSuccess: (data: UserTasks) => {
        if (requestSeq !== this.tasksQueueRequestSeq) {
          AppLogger.info(TAG, 'drop stale task queue')
          return
        }
        this.tasksQueueSource.replaceAll(data.tasks)
        this.totalTasks = this.tasksQueueSource.totalCount()
        this.tasksQueueTruncated = data.truncated
        this.tasksQueueRefresh = false
        console.debug(TAG, `task number: ${this.totalTasks}, truncated: ${data.truncated}`)
      },
      onFailure: (msg) => {
        if (requestSeq !== this.tasksQueueRequestSeq) {
          return
        }
        this.tasksQueueRefresh = false
        AppLogger.error(TAG, 'user tasks get failed, msg: ' + msg)
      }
    })
  }

  // 内容顶部让出 HDS 标题栏的距离；列表铺满全页、用首项占位让开，滚动时从标题栏底下穿过
  private getContentTopInset(): number {
    return CloudThemeToken.hdsTitleBarHeight(this.topRectHeight) + CloudThemeToken.spacingXs
  }

  // 首项占位高度：rowsGap 会再补一段间距，这里扣掉
  private getGridTopSpacerHeight(): number {
    return Math.max(CloudThemeToken.zero, this.getContentTopInset() - CloudThemeToken.spacingCard)
  }

  private isCurrentRefreshing(): boolean {
    return this.selectedIndexes[CloudThemeToken.primarySegmentIndex] == CloudThemeToken.primarySegmentIndex ?
      this.downloadRefresh : this.tasksQueueRefresh
  }

  private shouldShowRefreshHint(): boolean {
    return this.isCurrentRefreshing() || this.refreshPullOffset > CloudThemeToken.spacingSm
  }

  private getRefreshHintTop(): number {
    const pullDistance = this.isCurrentRefreshing() ? CloudThemeToken.refreshOffset :
      Math.max(CloudThemeToken.zero, this.refreshPullOffset)
    return this.getContentTopInset() + Math.max(CloudThemeToken.zero, pullDistance - CloudThemeToken.iconBoxSm) / 2
  }

  private getRefreshHintOpacity(): number {
    if (this.isCurrentRefreshing()) {
      return CloudThemeToken.fullOpacity
    }
    return Math.min(CloudThemeToken.fullOpacity,
      Math.max(CloudThemeToken.zero, this.refreshPullOffset / CloudThemeToken.refreshOffset))
  }

  // 顶栏走 HdsNavigation 标题栏（与文件页、相册页一致）：分段按钮放 stackBuilder 居中，
  // 「新建离线下载」用 HDS 原生菜单键，都在沉浸光感生效范围内，效果随设备档位由系统自适应。
  // 列表铺满全页，上滑时从标题栏底下穿过、标题栏渐变出沉浸模糊
  build() {
    HdsNavigation() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          if (this.selectedIndexes[CloudThemeToken.primarySegmentIndex] == CloudThemeToken.primarySegmentIndex) {
            this.offlineDownload()
          }
          else {
            this.tasksQueue()
          }
        }
        .width('100%')
        .height('100%')
        .padding({
          left: CloudThemeToken.pagePadding,
          right: CloudThemeToken.pagePadding
        })

        if (this.shouldShowRefreshHint()) {
          this.refreshingHintOverlay()
        }
      }
      .width('100%')
      .height('100%')
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
        menu: {
          value: [this.getCreateMenuItem()],
          maxCount: 1
        },
        stackBuilder: () => {
          this.titleStack()
        },
        divider: {
          showType: DividerShowType.OFF
        }
      },
      style: {
        // 与文件页、相册页同款：内容滚入标题栏底下时渐变出沉浸模糊
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            // 标题是空占位，但这里必须给：开了滚动效果后 HDS 按标题色推状态栏图标深浅，缺省会推成白色
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            },
            menuStyle: {
              // 置透明露出 HDS 标题栏材质（效果随设备档位由系统自适应）；<26 实色
              backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.surfaceSubtle),
              iconColor: CloudThemeToken.textPrimary,
              textColor: CloudThemeToken.textPrimary
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            },
            menuStyle: {
              backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.surfaceSubtle),
              iconColor: CloudThemeToken.textPrimary,
              textColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      padding: {
        end: this.titleButtonInsetEnd > 0 ?
          LengthMetrics.vp(this.titleButtonInsetEnd + CloudThemeToken.spacingCard) : undefined
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    // 两个分段各自的列表都绑上，切到哪个就跟哪个的滚动
    .bindToScrollable([this.scroller, this.tasksQueueScroller])
    .bindSheet($$this.showCreateSheet, this.taskCreateSheet(), {
      showClose: true,
      detents: [SheetSize.FIT_CONTENT],
      // 宽屏居中弹窗不认 detents，高度单独给成按内容，否则固定高、内容下方大片留白
      height: SheetSize.FIT_CONTENT,
      title: {title: $r('app.string.download_offline')},
      backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
      systemMaterial: CloudMaterial.sheetMaterial(),
      preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
      width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
      onDisappear: () => {
        this.showCreateSheet = false
      }
    })
    .backgroundColor(CloudThemeToken.background)
  }

  private getCreateMenuItem(): HdsNavigationMenuItemOptions {
    return {
      content: {
        icon: $r('app.media.ic_title_plus'),
        label: '新建离线下载',
        action: () => {
          this.openCreateSheet()
        }
      }
    }
  }

  deleteTaskConfirm(index: number, item: Aria2Finished) {
    const taskName = item.name && item.name.trim().length > 0 && item.name !== '.' ? item.name : item.gid
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.delete_task_confirm'),
      message: taskName,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        this.closeTaskDetailSheet()
        this.currentFinishedDetail = undefined
        this.currentFinishedIndex = -1
        CloudApi.deleteAria2Task(item.gid, {
          onSuccess: (data) => {
            // 不能用打开详情时记下的 index：轮询定时器会 replaceAll 整个列表，
            // 下标可能已经指向别的行甚至越界（越界时 notifyDataDelete 会把
            // 一个不存在的下标丢给 LazyForEach）。按对象删，找不到就等下面的重拉
            this.aria2FinishedSource.deleteDataByItem(item)
            this.totalFinished = this.aria2FinishedSource.totalCount()
            this.getAria2Downloading()
            this.getAria2Finished()
            this.getUserTasks()
            showToast($r('app.string.delete_task_success'))
          },
          onFailure: (msg) => {
            AppLogger.error(TAG, '删除任务失败 msg: ' + msg)
            showToastTips(`删除任务失败：${msg}`, ToastType.Error)
          }
        })
      }
    })
  }

  /**
   * 只有挂在下载器上（phase == monitor）的任务服务端才真的会取消。
   * 更早的阶段 CancelDownload 撞上 state.Handle == nil 会直接返回成功却什么都不做，
   * 放行的话界面会弹「已取消任务」而任务还在下载。
   * v3 不上报 phase（undefined），没有阶段概念，一律放行；
   * v4 一定带这个字段，空串说明还没挂上下载器，按不可取消处理。
   */
  canCancelDownloading(item: Aria2Downloading): boolean {
    if (item.phase === undefined) {
      return true
    }
    return item.phase === Constant.ARIA2_PHASE_MONITOR
  }

  getDownloadingGid(item: Aria2Downloading): string {
    if (item.gid && item.gid.length > 0) {
      return item.gid
    }
    return item.info?.gid ?? ''
  }

  // 列表 key 用的任务标识：优先 gid，取不到才退回「名字 + 下标」
  private downloadingTaskId(item: Aria2Downloading, index: number): string {
    const gid = this.getDownloadingGid(item)
    return gid.length > 0 ? gid : `${item.name}-${index}`
  }

  cancelTaskConfirm(item: Aria2Downloading) {
    const gid = this.getDownloadingGid(item)
    if (gid.length === 0) {
      AppLogger.warn(TAG, 'cancel skipped: task has no gid')
      showToastTips($r('app.string.cancel_task_failed'), ToastType.Error)
      return
    }
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.cancel_task_confirm'),
      message: this.getTaskName(item.name),
      confirmText: $r('app.string.dialog_cancel_task'),
      onConfirm: () => {
        CloudApi.cancelAria2Task(gid, {
          onSuccess: () => {
            this.getAria2Downloading()
            this.getAria2Finished()
            this.getUserTasks()
            showToast($r('app.string.cancel_task_success'))
          },
          onFailure: (msg) => {
            AppLogger.error(TAG, '取消任务失败 msg: ' + msg)
            // 服务端已经明说这个任务不在跑了，不用再查一遍
            if (msg.startsWith(Constant.ARIA2_CANCEL_ERR_NOT_RUNNING)) {
              this.notifyCancelTargetEnded()
              return
            }
            this.reportCancelFailure(gid, msg)
          }
        })
      }
    })
  }

  /** 任务其实已经跑完了：刷新两个列表，给一句人话而不是服务端原文 */
  private notifyCancelTargetEnded(): void {
    AppLogger.info(TAG, 'cancel target already ended, refreshing lists')
    this.getAria2Downloading()
    this.getAria2Finished()
    showToastTips($r('app.string.cancel_task_already_ended'), ToastType.Info)
  }

  /**
   * 兜底：错误码没被 native 认出来时，重新拉一次列表核实。
   * 任务已经不在「下载中」了就说明取消的目的已经达成，仍在就照实报错。
   */
  private reportCancelFailure(gid: string, failureMsg: string): void {
    CloudApi.aria2Downloading({
      onSuccess: (data) => {
        let stillRunning = false
        for (let index = 0; index < data.length; index++) {
          if (this.getDownloadingGid(data[index]) === gid) {
            stillRunning = true
            break
          }
        }
        if (stillRunning) {
          showToastTips(`取消任务失败：${failureMsg}`, ToastType.Error)
          return
        }
        this.notifyCancelTargetEnded()
      },
      onFailure: () => {
        showToastTips(`取消任务失败：${failureMsg}`, ToastType.Error)
      }
    })
  }

  @Builder taskDetailSheet(index: number, item?: Aria2Finished) {
    if (item && index < this.aria2FinishedSource.totalCount()) {
      Aria2FinishedDetail({
        detailData: item, canDelete: this.canDeleteFinished, onDeleteClick: () => {
          this.deleteTaskConfirm(index, item)
        }, onClose: () => {
          this.closeTaskDetailSheet()
        }
      })
    }
  }

  @Builder taskCreateSheet() {
    Aria2Create({onFinished: () => {
      this.getAria2Downloading()
      this.getAria2Finished()
      this.closeCreateSheet()
    }})
  }

  // 标题栏 stackBuilder：分段按钮居中。左右对称让出 HDS 菜单键（及 2in1 窗口三键）的宽度，
  // 分段按钮仍在页面正中、也不盖住菜单键抢点击；两侧空白作为 2in1 窗口拖动区（不挂整行，免得点分段按钮也拖窗口）
  @Builder titleStack() {
    Row() {
      Blank().layoutWeight(1).height('100%')
        .onTouch((event: TouchEvent) => {
          WindowMover.onTouch(event)
        })
      SegmentButton({ options: this.selectCapsuleOptions, selectedIndexes: $selectedIndexes })
        .width(CloudThemeToken.filesSegmentWidth)
      Blank().layoutWeight(1).height('100%')
        .onTouch((event: TouchEvent) => {
          WindowMover.onTouch(event)
        })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.getTitleStackSidePadding(),
      right: this.getTitleStackSidePadding()
    })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  private getTitleStackSidePadding(): number {
    return CloudThemeToken.filesTitleHorizontalPadding + CloudThemeToken.rowHeight5xl + this.titleButtonInsetEnd
  }

  getDownloadLength(files: Aria2Files[]) {
    let length: number = 0
    files?.forEach((value) => {
      length += parseInt(value.completedLength)
    })
    return length
  }

  getTaskName(name?: string): string {
    if (!name || name === '.' || name.trim().length === 0) {
      return '未命名任务'
    }
    return name
  }

  getProgressText(completed: number, total: number): string {
    if (total <= 0) {
      return '0%'
    }
    return `${Math.floor(completed * CloudThemeToken.percentageFull / total)}%`
  }

  getFileCountText(count: number): string {
    return `${count} 个文件`
  }

  getPathText(path: string): string {
    if (path.length === 0) {
      return '未设置保存路径'
    }
    return path
  }

  @Builder downloadingItem(item: Aria2Downloading) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Stack({alignContent: Alignment.Center}) {
        DataPanel({ values: [item.downloaded], max: item.total, type: DataPanelType.Circle })
          .width(CloudThemeToken.iconBox2xl)
          .height(CloudThemeToken.rowHeight2xl)
          .strokeWidth(CloudThemeToken.strongProgressStrokeWidth)
          .valueColors([CloudThemeToken.primary])

        Text(this.getProgressText(item.downloaded, item.total))
          .fontSize(CloudThemeToken.textSizeTiny)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
      }

      Column({ space: CloudThemeToken.spacingXl }) {
        Text(this.getTaskName(item.name))
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Progress({value: item.downloaded, total: item.total, type: ProgressType.Capsule})
          .width('100%')
          .height(CloudThemeToken.thinProgressHeight)
          .color(CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({ space: CloudThemeToken.spacingXl }) {
          Image($r('app.media.ic_arrowshape_down'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(CloudThemeToken.textPrimary)
          Text(CommonUtil.formatBytes(item.speed, 1)+'/s')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)

          Text(this.getFileCountText(item.info.files ? item.info.files.length : 1))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)

          Image($r('app.media.ic_calendar'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(CloudThemeToken.textSecondary)
          Text(DateFormatUtil.format(new Date(item.update), 'yyyy-MM-dd'))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)

        Row({ space: CloudThemeToken.spacingMd }) {
          Image($r('app.media.ic_folder'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(CloudThemeToken.textSecondary)
          Text(this.getPathText(item.dst))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Row() {
        Image($r('app.media.ic_xmark_bold'))
          .width(CloudThemeToken.aria2CancelIconSize)
          .height(CloudThemeToken.aria2CancelIconSize)
          .fillColor(this.canCancelDownloading(item) ? CloudThemeToken.danger : CloudThemeToken.textSecondary)
      }
      .width(CloudThemeToken.aria2CancelButtonSize)
      .height(CloudThemeToken.aria2CancelButtonSize)
      .borderRadius(CloudThemeToken.aria2CancelButtonRadius)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.canCancelDownloading(item) ?
        CloudThemeToken.dangerSoft : CloudThemeToken.surfaceSubtle)
      .opacity(this.canCancelDownloading(item) ? CloudThemeToken.fullOpacity : CloudThemeToken.disabledOpacity)
      .onClick(() => {
        if (!this.canCancelDownloading(item)) {
          showToastTips($r('app.string.cancel_task_not_ready'), ToastType.Info)
          return
        }
        this.cancelTaskConfirm(item)
      })
    }
    .width('100%')
    .height(CloudThemeToken.cardHeight3xl)
    .borderRadius(CloudThemeToken.cardRadius)
    .padding(CloudThemeToken.spacingSection)
    .backgroundColor(CloudThemeToken.surface)
  }

  getTaskStatus(task_status: number) {
    switch (task_status) {
      case Aria2Status.FINISHED:
       return $r('app.string.download_finished')
      case Aria2Status.FAILED:
        return $r('app.string.download_failed')
      case Aria2Status.ERROR:
        return $r('app.string.download_error')
    }

    return ''
  }

  @Builder finishedItem(index: number, item: Aria2Finished) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Stack({alignContent: Alignment.Center}) {
        DataPanel({
          // Cloudreve reports total=0 for tasks that failed before sizing (e.g. "resource
          // not found"); fall back to a sentinel max so the ring still renders.
          values: [item.task_status == Aria2Status.FINISHED ? this.getDownloadLength(item.files) : 1],
          max: item.total > 0 ? item.total : 1,
          type: DataPanelType.Circle
        })
          .width(CloudThemeToken.iconBox2xl)
          .height(CloudThemeToken.rowHeight2xl)
          .strokeWidth(CloudThemeToken.strongProgressStrokeWidth)
          .closeEffect(true)
          .valueColors([item.task_status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger])

        Text(item.files?.length ? item.files.length.toString() : '0')
          .fontSize(CloudThemeToken.textSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
      }

      Column({ space: CloudThemeToken.spacingLg }) {
        Text(this.getTaskName(item.name))
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Row({ space: CloudThemeToken.spacingXl }) {
          Image(item.task_status == Aria2Status.FINISHED ?
            $r('app.media.ic_checkmark_circle_fill') : $r('app.media.ic_xmark_circle_fill'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(item.task_status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)
          Text(this.getTaskStatus(item.task_status))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)

          Text(this.getFileCountText(item.files ? item.files.length : 0))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)

          Image($r('app.media.ic_calendar'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(CloudThemeToken.textSecondary)
          Text(DateFormatUtil.format(new Date(item.update), 'yyyy-MM-dd'))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)

        Row({ space: CloudThemeToken.spacingMd }) {
          Image($r('app.media.ic_folder'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(CloudThemeToken.textSecondary)
          Text(this.getPathText(item.dst))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Image($r('app.media.ic_dot_grid_1x2'))
        .width(CloudThemeToken.icon3xl)
        .height(CloudThemeToken.icon3xl)
    }
    .width('100%')
    .height(CloudThemeToken.cardHeightXl)
    .borderRadius(CloudThemeToken.cardRadius)
    .padding(CloudThemeToken.spacingSection)
    .backgroundColor(CloudThemeToken.surface)
    .onClick(() => {
      console.debug(TAG, 'onClick')
      this.currentFinishedDetail = item
      this.currentFinishedIndex = index
      this.openTaskDetailSheet()
    })
  }

  @Builder noTask(title: ResourceStr) {
    EmptyState({
      icon: $r('app.media.ic_icloud_slash_fill'),
      title: title,
      description: '任务状态会在这里自动刷新。'
    })
  }

  @Builder downloading() {
    if (this.aria2Downloading.length == 0) {
      GridItem() {
        this.noTask($r('app.string.no_download_task'))
      }
    } else {
      // key 要唯一且随进度变化：普通对象的条目 key 不变就不会重绘，进度会停在第一次的值；
      // 只用「名字 + 下标」时，同名任务在前面插入 / 移除后还会串到别的任务上
      ForEach(this.aria2Downloading, (item: Aria2Downloading, index) => {
        GridItem(){
          this.downloadingItem(item)
        }
      }, (item: Aria2Downloading, index: number) =>
        `${this.downloadingTaskId(item, index)}-${item.status}-${item.downloaded}-${item.total}-${item.speed}`)
    }
  }

  @Builder finished() {
    if (this.totalFinished == 0) {
      GridItem() {
        this.noTask($r('app.string.no_finished_task'))
      }
    } else {
      // 用任务 id 做 key：「名字 + 下标」在同名任务前面插入新任务后会撞上旧 key，
      // 条目被原样复用，显示成别的任务的保存路径
      LazyForEach(this.aria2FinishedSource, (item: Aria2Finished, index) => {
        GridItem() {
          this.finishedItem(index, item)
        }
      }, (item: Aria2Finished, index: number) => item.gid.length > 0 ? item.gid : `${item.name}-${index}`)
      this.listEndFooter(false)
    }
  }

  // 到底提示的文案：一共多少条；超过上限时说明更早的没拉。
  // 条数在方法里直接读状态——当成 @Builder 参数按值传进去不会随刷新更新
  private getListEndText(isTaskQueue: boolean): string {
    const truncated = isTaskQueue ? this.tasksQueueTruncated : this.finishedTruncated
    if (truncated) {
      return `仅显示最近 ${Constant.TASK_LIST_MAX_ITEMS} 条`
    }
    return `已显示全部 ${isTaskQueue ? this.totalTasks : this.totalFinished} 条`
  }

  @Builder listEndLine() {
    Row()
      .width(CloudThemeToken.aria2ListEndLineWidth)
      .height(CloudThemeToken.lineWidth)
      .backgroundColor(CloudThemeToken.line)
  }

  // 列表一次拉全，末尾告诉用户已经到底
  @Builder listEndFooter(isTaskQueue: boolean) {
    GridItem() {
      Row({ space: CloudThemeToken.spacingXl }) {
        this.listEndLine()
        Text(this.getListEndText(isTaskQueue))
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
        this.listEndLine()
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .padding({ top: CloudThemeToken.spacingSm, bottom: CloudThemeToken.spacingSm })
    }
    .selectable(false)
  }

  // 首项占位：让列表从标题栏下方开始，滚动时可从标题栏底下穿过
  @Builder gridTopSpacer() {
    GridItem() {
      Row().height(this.getGridTopSpacerHeight())
    }
    .selectable(false)
  }

  // 末尾占位：给悬浮 Tab 栏让位（同文件页）。不能用 Grid 的 bottom padding：
  // Grid 只把 padding 以内当可见区，卡片要整张越过那条线才画出来，滚动时一张张蹦出来
  @Builder gridBottomSpacer() {
    GridItem() {
      Row().height(Math.max(CloudThemeToken.zero,
        this.tabBarHeight + CloudThemeToken.tabContentBottomGap - CloudThemeToken.spacingCard))
    }
    .selectable(false)
  }

  // 系统刷新指示器画在 Refresh 顶部、会被标题栏挡住，隐藏掉，改在标题栏下方单独画（同文件页）
  @Builder hiddenRefreshHint() {
    Column()
      .width(CloudThemeToken.zero)
      .height(CloudThemeToken.zero)
      .opacity(CloudThemeToken.zero)
  }

  @Builder refreshingHintOverlay() {
    Column() {
      Row({ space: CloudThemeToken.spacingXl }) {
        LoadingProgress()
          .width(CloudThemeToken.iconLg)
          .height(CloudThemeToken.iconLg)
          .color(CloudThemeToken.primary)
        Text('正在刷新')
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textPrimary)
      }
      .height(CloudThemeToken.iconBoxSm)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPage })
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .backgroundColor(CloudMaterial.cardBackground(CloudThemeToken.surface))
      .shadow({
        radius: CloudThemeToken.refreshShadowRadius,
        color: CloudThemeToken.refreshShadow,
        offsetY: CloudThemeToken.refreshShadowOffsetY
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getRefreshHintTop() })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .opacity(this.getRefreshHintOpacity())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder offlineDownload() {
    Refresh({ refreshing: $$this.downloadRefresh, builder: this.hiddenRefreshHint }) {
      Grid(this.scroller) {
        this.gridTopSpacer()
        this.downloading()
        GridItem() {
          Row().height(CloudThemeToken.spacingCard)
        }
        this.finished()
        this.gridBottomSpacer()
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
      .columnsTemplate(CloudThemeToken.singleColumnTemplate)
      .maxCount(CloudThemeToken.singleColumnMaxCount)
      .cachedCount(CloudThemeToken.compactListCachedCount)
      .columnsGap(CloudThemeToken.spacingCard)
      .rowsGap(CloudThemeToken.spacingCard)
      .animation({duration: CloudThemeToken.defaultAnimationDuration})
      .bindSheet($$this.showTaskDetailSheet, this.taskDetailSheet(this.currentFinishedIndex, this.currentFinishedDetail), {
        detents: [SheetSize.FIT_CONTENT],
        // 宽屏居中弹窗不认 detents，高度单独给成按内容
        height: SheetSize.FIT_CONTENT,
        title: { title: '下载详情' },
        showClose: true,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onDisappear: () => {
          this.showTaskDetailSheet = false
        }
      })
    }
    .layoutWeight(1)
    .refreshOffset(CloudThemeToken.refreshOffset)
    .pullToRefresh(true)
    .onOffsetChange((offset: number) => {
      this.refreshPullOffset = Math.max(CloudThemeToken.zero, offset)
    })
    .onRefreshing(() => {
      this.getAria2Downloading();
      this.getAria2Finished();
    })
  }

  @Builder tasksQueue() {
    Refresh({ refreshing: $$this.tasksQueueRefresh, builder: this.hiddenRefreshHint }) {
      Grid(this.tasksQueueScroller) {
        this.gridTopSpacer()
        if (this.totalTasks == 0) {
          GridItem() {
            this.noTask($r('app.string.no_task_queue'))
          }
        } else {
          LazyForEach(this.tasksQueueSource, (item: UserTask, index) => {
            GridItem() {
              this.taskQueueItem(item)
            }
          }, (item: UserTask, index:number) => (item.id.length > 0 ? item.id : item.create_date) + index)
          this.listEndFooter(true)
        }
        this.gridBottomSpacer()
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
      .columnsTemplate(CloudThemeToken.singleColumnTemplate)
      .maxCount(CloudThemeToken.singleColumnMaxCount)
      .cachedCount(CloudThemeToken.compactListCachedCount)
      .columnsGap(CloudThemeToken.spacingCard)
      .rowsGap(CloudThemeToken.spacingCard)
      .bindSheet($$this.showQueueTaskSheet, this.queueTaskDetailSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        // 宽屏居中弹窗不认 detents，高度单独给成按内容
        height: SheetSize.FIT_CONTENT,
        title: { title: '任务详情' },
        showClose: true,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onDisappear: () => {
          this.showQueueTaskSheet = false
        }
      })
    }
    .layoutWeight(1)
    .refreshOffset(CloudThemeToken.refreshOffset)
    .pullToRefresh(true)
    .onOffsetChange((offset: number) => {
      this.refreshPullOffset = Math.max(CloudThemeToken.zero, offset)
    })
    .onRefreshing(() => {
      this.getUserTasks();
    })
  }

  @Builder queueTaskDetailSheet() {
    if (this.currentQueueTask) {
      TaskQueueDetail({ task: this.currentQueueTask })
    }
  }

  @Builder taskQueueItem(task: UserTask) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Stack() {
        SymbolGlyph(this.getTaskIcon(task.kind))
          .fontSize(CloudThemeToken.icon2xl)
          .fontColor([CloudThemeToken.textPrimary])
      }
      .width(CloudThemeToken.iconBoxLg)
      .height(CloudThemeToken.iconBoxLg)
      .borderRadius(CloudThemeToken.controlRadiusMd)
      .backgroundColor(CloudThemeToken.surfaceSubtle)

      Column({ space: CloudThemeToken.spacingSm }) {
        Row({ space: CloudThemeToken.spacingXl }) {
          Text(TaskQueueText.kind(task.kind))
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(TaskQueueText.status(task))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getTaskStatusColor(task.status))
            .backgroundColor(this.getTaskStatusBackground(task.status))
            .height(CloudThemeToken.aria2TaskChipHeight)
            .padding({ left: CloudThemeToken.spacingXl, right: CloudThemeToken.spacingXl })
            .borderRadius(CloudThemeToken.controlRadiusMd)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (task.src.length > 0 || task.dst.length > 0) {
          Text() {
            Span(TaskQueueText.source(task))
            if (task.src.length > 0 && task.dst.length > 0) {
              Span(' → ').fontColor(CloudThemeToken.textSecondary)
            }
            Span(task.dst)
          }
          .fontSize(CloudThemeToken.textSizeSmallPlus)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else if (TaskQueueText.progress(task).length > 0) {
          Text(TaskQueueText.progress(task))
            .fontSize(CloudThemeToken.textSizeSmallPlus)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
        }

        Text(this.getTaskMetaText(task))
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)

        if (task.failed > 0) {
          Text(TaskQueueText.failedObjects(task))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.warning)
        }

        if (task.status === TASK_STATUS_ERROR) {
          Text(TaskQueueText.error(task))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.danger)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .borderRadius(CloudThemeToken.cardRadius)
    .padding(CloudThemeToken.spacingSection)
    .backgroundColor(CloudThemeToken.surface)
    .onClick(() => {
      this.currentQueueTask = task
      this.showQueueTaskSheet = true
    })
  }

  private getTaskIcon(kind: string): Resource {
    switch (kind) {
      case 'compress':
        return $r('sys.symbol.doc_zipper')
      case 'extract':
        return $r('sys.symbol.decompress')
      case 'import':
      case 'transfer':
        return $r('sys.symbol.square_and_arrow_down')
      case 'relocate':
        return $r('sys.symbol.externaldrive')
      case 'recycle':
        return $r('sys.symbol.trash')
      default:
        return $r('sys.symbol.archivebox')
    }
  }

  private getTaskStatusColor(status: string): ResourceColor {
    switch (status) {
      case TASK_STATUS_PROCESSING:
        return CloudThemeToken.primary
      case TASK_STATUS_COMPLETED:
        return CloudThemeToken.success
      case TASK_STATUS_ERROR:
        return CloudThemeToken.danger
      default:
        return CloudThemeToken.textSecondary
    }
  }

  private getTaskStatusBackground(status: string): ResourceColor {
    switch (status) {
      case TASK_STATUS_PROCESSING:
        return CloudThemeToken.primarySoft
      case TASK_STATUS_COMPLETED:
        return CloudThemeToken.successSoft
      case TASK_STATUS_ERROR:
        return CloudThemeToken.dangerSoft
      default:
        return CloudThemeToken.surfaceSubtle
    }
  }

  private getTaskMetaText(task: UserTask): string {
    const created = new Date(task.create_date)
    const now = new Date()
    const isToday = created.getFullYear() === now.getFullYear() && created.getMonth() === now.getMonth() &&
      created.getDate() === now.getDate()
    const time = isToday ? `今天 ${DateFormatUtil.format(created, 'HH:mm')}` :
      DateFormatUtil.format(created, 'yyyy-MM-dd HH:mm')
    return task.duration > 0 ? `${time} · 耗时 ${TaskQueueText.duration(task.duration)}` : time
  }

  private openCreateSheet(): void {
    this.showCreateSheet = true
  }

  private closeCreateSheet(): void {
    this.showCreateSheet = false
  }

  private openTaskDetailSheet(): void {
    this.showTaskDetailSheet = true
  }

  private closeTaskDetailSheet(): void {
    this.showTaskDetailSheet = false
  }
}
