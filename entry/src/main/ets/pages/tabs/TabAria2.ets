import Constant from "../../model/Constant";
import { Aria2Downloading,
  Aria2Files,
  Aria2Finished, Aria2Status,
  TaskError,
  UserTask, UserTasks } from "../../model/net/ApiTypes";
import { CloudApi } from "../../model/net/CloudApi";
import { ContentItem, SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import LazyDataSource from "../../utils/LazyDataSource";
import { Aria2FinishedDetail } from "../../components/Aria2FinishedDetail";
import { CommonUtil } from "../../utils/CommonUtil";
import { Aria2Create } from "../../components/Aria2Create";
import { showToast, showToastTips, ToastType } from "../../utils/ToastUtil";
import { CloudScaffold } from "../../components/CloudScaffold";
import { CloudThemeToken } from "../../model/CloudTheme";
import { CloudMaterial } from "../../model/CloudMaterial";
import AppLogger from "../../utils/AppLogger";
import { WindowMover } from "../../utils/WindowMover";
import { EmptyState } from "../../components/EmptyState";
import { TitleControlButton } from "../../components/TitleControlButton";
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
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0;
  // 2in1 窗口三键区宽度；其它设备为 0
  @StorageProp(Constant.TITLE_BUTTON_INSET_END) titleButtonInsetEnd: number = 0;
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
  private finishedPage: number = 1
  private isLastFinishedPage: boolean = false
  private tasksQueuePage: number = 1
  private isLastTasksQueuePage: boolean = false
  private scroller: Scroller = new Scroller()
  private tasksQueueScroller: Scroller = new Scroller()
  @State currentFinishedDetail: Aria2Finished|undefined = undefined
  @State currentFinishedIndex: number = -1
  @State showTaskDetailSheet: boolean = false
  private timerId?: number = undefined
  @State showCreateSheet: boolean = false
  // v4 只有管理员能删已结束的任务记录（普通用户压根没有这个接口），v3 谁都能删。
  // 权限在这里问一次，决定详情页要不要给删除按钮。
  @State canDeleteFinished: boolean = false
  // 只有真的问出结果才算数；失败不置位，留给下次切回本页重试
  private deletePermissionResolved: boolean = false
  private initialDataRequested: boolean = false
  private loadedAccountScope: string = ''

  aboutToAppear(): void {
    this.loadedAccountScope = ActiveAccount.current()
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
    this.finishedPage = 1
    this.isLastFinishedPage = false
    this.tasksQueueSource.clear()
    this.totalTasks = 0
    this.tasksQueuePage = 1
    this.isLastTasksQueuePage = false
    this.showTaskDetailSheet = false
    this.currentFinishedDetail = undefined
    this.currentFinishedIndex = -1
    this.canDeleteFinished = false
    this.deletePermissionResolved = false
    this.initialDataRequested = false
    this.loadInitialDataIfActive()
    this.refreshDeletePermission()
  }

  private loadInitialDataIfActive(): void {
    if (!this.isActive || this.initialDataRequested) {
      return
    }
    this.initialDataRequested = true
    this.getAria2Downloading()
    this.getAria2Finished(true)
    this.getUserTasks(true)
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
        this.getAria2Downloading()
        this.getAria2Finished(true, true)
      }, interval)
    }
  }

  clearDownloadUpdateTask() {
    if (this.timerId != undefined) {
      clearInterval(this.timerId)
      this.timerId = undefined
    }
  }

  getAria2Downloading() {
    if (!this.isActive) {
      return
    }
    CloudApi.aria2Downloading({
      onSuccess: (data) => {
        if (!this.isActive) {
          return
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

  getAria2Finished(isFresh: boolean, softRefresh: boolean = false) {
    if (!this.isActive) {
      return
    }
    if (isFresh && !softRefresh) {
      this.aria2FinishedSource.clear()
      this.finishedPage = 1
      this.isLastFinishedPage = false
    }

    const targetPage = isFresh ? 1 : this.finishedPage
    CloudApi.aria2Finished(targetPage, {
      onSuccess: (data) => {
        if (!this.isActive) {
          return
        }
        if (isFresh && softRefresh) {
          this.aria2FinishedSource.replaceAll(data)
          this.finishedPage = data.length > 0 ? 2 : 1
          this.isLastFinishedPage = data.length === 0
        } else if (data.length > 0) {
          this.aria2FinishedSource.pushArrayData(data)
          this.finishedPage++
          console.debug(TAG, 'finished number: ' + this.totalFinished)
        } else {
          this.isLastFinishedPage = true
          AppLogger.warn(TAG, 'finished no found in this page ' + this.finishedPage)
        }
        this.downloadRefresh = false
        this.totalFinished = this.aria2FinishedSource.totalCount()
      },
      onFailure: (msg) => {
        this.downloadRefresh = false
        AppLogger.error(TAG, 'Aria2 finished get failed, msg: ' + msg)
      }
    })
  }

  getUserTasks(isFresh: boolean) {
    if (!this.isActive) {
      return
    }
    if (isFresh) {
      this.tasksQueueSource.clear()
      this.tasksQueuePage = 1
      this.isLastTasksQueuePage = false
    }

    CloudApi.userTasks(this.tasksQueuePage, {
      onSuccess: (data: UserTasks) => {
        if (!this.isActive) {
          return
        }
        if (data.tasks.length > 0) {
          this.tasksQueueSource.pushArrayData(data.tasks)
          this.tasksQueuePage++
          this.totalTasks = this.tasksQueueSource.totalCount()
          if (this.totalTasks >= data.total) {
            this.isLastTasksQueuePage = true
          }
          this.tasksQueueRefresh = false
        } else {
          AppLogger.warn(TAG, 'tasks no found in this page ' + this.tasksQueuePage)
          this.isLastTasksQueuePage = true
        }
        console.debug(TAG, 'task total number: ' + data.total)
      },
      onFailure: (msg) => {
        this.tasksQueueRefresh = false
        AppLogger.error(TAG, 'user tasks get failed, msg: ' + msg)
      }
    })
  }

  build() {
    CloudScaffold({
      scrollable: false,
      avoidTabBar: false,
      // 2in1 隐藏系统标题栏后，标题行与窗口三键区（rowHeight5xl 高）垂直居中对齐
      topPadding: this.titleButtonInsetEnd > 0 ?
        (CloudThemeToken.rowHeight5xl - CloudThemeToken.iconBoxLg) / CloudThemeToken.halfDivisor :
        CloudThemeToken.pageTopPadding,
      bottomPadding: CloudThemeToken.zero,
      horizontalPadding: CloudThemeToken.pagePadding
    }) {
      this.title()
      if (this.selectedIndexes[CloudThemeToken.primarySegmentIndex] == CloudThemeToken.primarySegmentIndex) {
        this.offlineDownload()
      }
      else {
        this.tasksQueue()
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
            this.getAria2Finished(true)
            this.getUserTasks(true)
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
            this.getAria2Finished(true)
            this.getUserTasks(true)
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
    this.getAria2Finished(true)
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
      this.getAria2Finished(true)
      this.closeCreateSheet()
    }})
  }

  @Builder title() {
    Stack({alignContent: Alignment.End}) {
      Row() {
        // 分段按钮两侧空白作为 2in1 窗口拖动区（不挂整行，免得点分段按钮也拖窗口）
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
      .justifyContent(FlexAlign.Center)

      // 与 HDS 标题栏菜单键同款（TitleControlButton），和其它页标题栏按钮观感一致
      Column() {
        TitleControlButton({
          icon: $r('app.media.ic_title_plus'),
          label: '新建离线下载',
          onAction: () => {
            this.openCreateSheet()
          }
        })
      }
      .bindSheet($$this.showCreateSheet, this.taskCreateSheet(), {
        showClose: true,
        detents: [SheetSize.FIT_CONTENT],
        title: {title: $r('app.string.download_offline')},
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onDisappear: () => {
          this.showCreateSheet = false
        }
      })
      // 2in1 窗口三键浮在右上角，新建按钮左移让位；分段按钮仍在页面居中
      .margin({ right: this.titleButtonInsetEnd })
    }
    .width('100%')
    .height(CloudThemeToken.iconBoxLg)
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
      ForEach(this.aria2Downloading, (item: Aria2Downloading, index) => {
        GridItem(){
          this.downloadingItem(item)
        }
      }, (item: Aria2Downloading, index:number) => item.name + index)
    }
  }

  @Builder finished() {
    if (this.totalFinished == 0) {
      GridItem() {
        this.noTask($r('app.string.no_finished_task'))
      }
    } else {
      LazyForEach(this.aria2FinishedSource, (item: Aria2Finished, index) => {
        GridItem() {
          this.finishedItem(index, item)
        }
      }, (item: Aria2Finished, index:number) => item.name + index)
    }
  }

  @Builder offlineDownload() {
    Refresh({refreshing: $$this.downloadRefresh}) {
      Grid(this.scroller) {
        this.downloading()
        GridItem() {
          Row().height(CloudThemeToken.spacingCard)
        }
        this.finished()
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.tabBarHeight + CloudThemeToken.tabContentBottomGap })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
      .columnsTemplate(CloudThemeToken.singleColumnTemplate)
      .maxCount(CloudThemeToken.singleColumnMaxCount)
      .cachedCount(CloudThemeToken.compactListCachedCount)
      .columnsGap(CloudThemeToken.spacingCard)
      .rowsGap(CloudThemeToken.spacingCard)
      .animation({duration: CloudThemeToken.defaultAnimationDuration})
      .onReachEnd(() => {
        if (!this.isLastFinishedPage) {
          this.getAria2Finished(false)
        } else {
          AppLogger.warn(TAG, 'last finished page！！！')
        }
      })
      .bindSheet($$this.showTaskDetailSheet, this.taskDetailSheet(this.currentFinishedIndex, this.currentFinishedDetail), {
        detents: CloudThemeToken.sheetDetentsForWidth(this.sheetLayoutWidth, SheetSize.FIT_CONTENT),
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
    .onRefreshing(() => {
      this.getAria2Downloading();
      this.getAria2Finished(true);
    })
  }

  @Builder tasksQueue() {
    Refresh({refreshing: $$this.tasksQueueRefresh}) {
      Grid(this.tasksQueueScroller) {
        if (this.totalTasks == 0) {
          GridItem() {
            this.noTask($r('app.string.no_task_queue'))
          }
        } else {
          LazyForEach(this.tasksQueueSource, (item: UserTask, index) => {
            GridItem() {
              this.taskQueueItem(item)
            }
          }, (item: UserTask, index:number) => (item.id ?? item.create_date) + index)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.tabBarHeight + CloudThemeToken.tabContentBottomGap })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
      .columnsTemplate(CloudThemeToken.singleColumnTemplate)
      .maxCount(CloudThemeToken.singleColumnMaxCount)
      .cachedCount(CloudThemeToken.compactListCachedCount)
      .columnsGap(CloudThemeToken.spacingCard)
      .rowsGap(CloudThemeToken.spacingCard)
      .onReachEnd(() => {
        if (!this.isLastTasksQueuePage) {
          this.getUserTasks(false)
        } else {
          AppLogger.warn(TAG, 'last task queue page！！！')
        }
      })
    }
    .layoutWeight(1)
    .refreshOffset(CloudThemeToken.refreshOffset)
    .pullToRefresh(true)
    .onRefreshing(() => {
      this.getUserTasks(true);
    })
  }

  @Builder taskQueueItem(task: UserTask) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Column({ space: CloudThemeToken.spacingXl }) {
        Row({ space: CloudThemeToken.spacingXl }) {
          Image($r('app.media.ic_calendar'))
            .width(CloudThemeToken.iconXs)
            .height(CloudThemeToken.iconXs)
            .fillColor(CloudThemeToken.textSecondary)
          Text(DateFormatUtil.format(new Date(task.create_date), 'yyyy-MM-dd'))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
        }

        Text(this.getTaskName(task.name))
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Progress({value: task.progress, total: CloudThemeToken.percentageFull, type: ProgressType.Capsule})
          .width('100%')
          .height(CloudThemeToken.thinProgressHeight)
          .color(task.status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({ space: CloudThemeToken.spacingXl }) {
          Image(task.status == Aria2Status.FINISHED ?
            $r('app.media.ic_checkmark_circle_fill') : $r('app.media.ic_xmark_circle_fill'))
              .width(CloudThemeToken.iconXs)
              .height(CloudThemeToken.iconXs)
              .fillColor(task.status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)

          Text($r('app.string.last_progress'))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)

          Text(`${task.progress}%`)
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)

          Text(task.status == Aria2Status.FINISHED ?
            $r("app.string.finished") : $r("app.string.failed"))
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
        }

        if (task.status != Aria2Status.FINISHED) {
          Row({ space: CloudThemeToken.spacingSm }) {
            Image($r('app.media.ic_info_circle'))
              .width(CloudThemeToken.iconXs)
              .height(CloudThemeToken.iconXs)
              .fillColor(CloudThemeToken.textSecondary)

            Text(this.getErrorInfo(task.error))
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.danger)
              .maxLines(2)
              .textOverflow({overflow: TextOverflow.Ellipsis})
              .layoutWeight(1)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)

      Image($r('app.media.ic_task_circle'))
        .width(CloudThemeToken.iconBoxLg)
        .height(CloudThemeToken.iconBoxLg)
        .fillColor(task.status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)
    }
    .width('100%')
    .constraintSize({ minHeight: CloudThemeToken.cardHeight3xl })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .borderRadius(CloudThemeToken.cardRadius)
    .padding(CloudThemeToken.spacingSection)
    .backgroundColor(CloudThemeToken.surface)
  }

  getErrorInfo(errorJson: string) {
    if (!errorJson || errorJson.trim().length === 0) {
      return '任务执行失败'
    }

    try {
      let error: TaskError = JSON.parse(errorJson)
      return `${error.msg}:${error.error}`
    } catch (e) {
      return errorJson
    }
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
