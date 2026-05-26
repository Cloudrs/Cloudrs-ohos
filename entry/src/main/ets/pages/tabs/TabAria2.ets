import Constant from "../../model/Constant";
import { Aria2Downloading,
  Aria2Files,
  Aria2Finished, Aria2Status,
  TaskError,
  UserTask, UserTasks } from "../../model/net/ApiTypes";
import { CloudApi } from "../../model/net/CloudApi";
import { ContentItem, SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import { DateUtil } from "@pura/harmony-utils";
import LazyDataSource from "../../utils/LazyDataSource";
import { Aria2FinishedDetail } from "../../components/Aria2FinishedDetail";
import { CommonUtil } from "../../utils/CommonUtil";
import { Aria2Create } from "../../components/Aria2Create";
import { DialogAction, DialogHelper } from "@pura/harmony-dialog";
import { showToast, showToastTips, ToastType } from "../../utils/ToastUtil";
import { CloudScaffold } from "../../components/CloudScaffold";
import { CloudThemeToken } from "../../model/CloudTheme";
import { EmptyState } from "../../components/EmptyState";
import { CloudActionButton } from "../../components/CloudActionButton";

const TAG: string = 'TabRemote'

@Component
export struct TabRemoteDown {
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
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
  @State selectedIndexes: number[] = [0]
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
  private timerId?: number = 0
  @State showCreateSheet: boolean = false

  aboutToAppear(): void {
    this.getAria2Downloading()
    this.getAria2Finished(true)
    this.getUserTasks(true)
  }

  startDownloadUpdateTask(interval: number) {
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
    CloudApi.aria2Downloading({
      onSuccess: (data) => {
        if (data.length > 0) {
          this.aria2Downloading = data
          this.totalDownloading = this.aria2Downloading.length
          this.startDownloadUpdateTask(data[0].interval < 3 ? 3000 : data[0].interval*1000)
          console.debug(TAG, 'downloading number: ' + this.totalDownloading)
        } else {
          console.warn(TAG, 'no downloading task')
          this.aria2Downloading = []
          this.totalDownloading = 0
          this.clearDownloadUpdateTask()
        }
      },
      onFailure: (msg) => {
        this.aria2Downloading = []
        this.totalDownloading = 0
        this.clearDownloadUpdateTask()
        console.error(TAG, 'Aria2 downloading get failed, msg: ' + msg)
      }
    })
  }

  getAria2Finished(isFresh: boolean, softRefresh: boolean = false) {
    if (isFresh && !softRefresh) {
      this.aria2FinishedSource.clear()
      this.finishedPage = 1
      this.isLastFinishedPage = false
    }

    const targetPage = isFresh ? 1 : this.finishedPage
    CloudApi.aria2Finished(targetPage, {
      onSuccess: (data) => {
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
          console.warn(TAG, 'finished no found in this page ' + this.finishedPage)
        }
        this.downloadRefresh = false
        this.totalFinished = this.aria2FinishedSource.totalCount()
      },
      onFailure: (msg) => {
        this.downloadRefresh = false
        console.error(TAG, 'Aria2 finished get failed, msg: ' + msg)
      }
    })
  }

  getUserTasks(isFresh: boolean) {
    if (isFresh) {
      this.tasksQueueSource.clear()
      this.tasksQueuePage = 1
      this.isLastTasksQueuePage = false
    }

    CloudApi.userTasks(this.tasksQueuePage, {
      onSuccess: (data: UserTasks) => {
        if (data.tasks.length > 0) {
          this.tasksQueueSource.pushArrayData(data.tasks)
          this.tasksQueuePage++
          this.totalTasks = this.tasksQueueSource.totalCount()
          if (this.totalTasks >= data.total) {
            this.isLastTasksQueuePage = true
          }
          this.tasksQueueRefresh = false
        } else {
          console.warn(TAG, 'tasks no found in this page ' + this.tasksQueuePage)
          this.isLastTasksQueuePage = true
        }
        console.debug(TAG, 'task total number: ' + data.total)
      },
      onFailure: (msg) => {
        this.tasksQueueRefresh = false
        console.error(TAG, 'user tasks get failed, msg: ' + msg)
      }
    })
  }

  build() {
    CloudScaffold({
      scrollable: false,
      avoidTabBar: false,
      topPadding: 20,
      bottomPadding: 0,
      horizontalPadding: CloudThemeToken.pagePadding
    }) {
      this.title()
      if (this.selectedIndexes[0] == 0) {
        this.offlineDownload()
      }
      else {
        this.tasksQueue()
      }
    }
  }

  deleteTaskConfirm(index: number, item: Aria2Finished) {
    const taskName = item.name && item.name.trim().length > 0 && item.name !== '.' ? item.name : item.gid
    DialogHelper.showAlertDialog({
      primaryTitle:  $r('app.string.delete_task_confirm'),
      content: taskName,
      primaryButton: {value: $r('app.string.dialog_cancel')},
      secondaryButton: {value: $r('app.string.dialog_delete'), role: ButtonRole.ERROR},
      onAction: (action: number, dialogId: string) => {
        if (action == DialogAction.TWO) {
          this.showTaskDetailSheet = false
          this.currentFinishedDetail = undefined
          this.currentFinishedIndex = -1
          CloudApi.deleteAria2Task(item.gid, {
              onSuccess: (data) => {
                this.aria2FinishedSource.deleteData(index)
                this.totalFinished = this.aria2FinishedSource.totalCount()
                this.getAria2Downloading()
                this.getAria2Finished(true)
                this.getUserTasks(true)
                showToast($r('app.string.delete_task_success'))
              },
              onFailure: (msg) => {
                console.error(TAG, '删除任务失败 msg: ' + msg)
                showToastTips(`删除任务失败：${msg}`, ToastType.Error)
              }
            })
        }
      }
    })
  }

  @Builder taskDetailSheet(index: number, item?: Aria2Finished) {
    if (item && index < this.aria2FinishedSource.totalCount()) {
      Aria2FinishedDetail({
        detailData: item, onDeleteClick: () => {
          this.deleteTaskConfirm(index, item)
        }
      })
    }
  }

  @Builder taskCreateSheet() {
    Aria2Create({onFinished: () => {
      this.getAria2Downloading()
      this.getAria2Finished(true)
      this.showCreateSheet = false
    }})
  }

  @Builder title() {
    Stack({alignContent: Alignment.End}) {
      Row() {
        SegmentButton({ options: this.selectCapsuleOptions, selectedIndexes: $selectedIndexes })
          .width(160)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      CloudActionButton({
        icon: $r('app.media.ic_plus'),
        onAction: () => {
          this.showCreateSheet = true
        }
      })
      .bindSheet($$this.showCreateSheet, this.taskCreateSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        title: {title: $r('app.string.download_offline')},
        backgroundColor: CloudThemeToken.background,
      })
    }
    .width('100%')
    .height(40)
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
    return `${Math.floor(completed * 100 / total)}%`
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
    Row({space: 12}) {
      Stack({alignContent: Alignment.Center}) {
        DataPanel({ values: [item.downloaded], max: item.total, type: DataPanelType.Circle })
          .width(48)
          .height(48)
          .strokeWidth(4)
          .valueColors([CloudThemeToken.primary])

        Text(this.getProgressText(item.downloaded, item.total))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
      }

      Column({space: 8}) {
        Text(this.getTaskName(item.name))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Progress({value: item.downloaded, total: item.total, type: ProgressType.Capsule})
          .width('100%')
          .height(6)
          .color(CloudThemeToken.primary)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({space: 8}) {
          Image($r('app.media.ic_arrowshape_down'))
            .width(12)
            .height(12)
            .fillColor(CloudThemeToken.textPrimary)
          Text(CommonUtil.formatBytes(item.speed, 1)+'/s')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)

          Text(this.getFileCountText(item.info.files ? item.info.files.length : 1))
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)

          Image($r('app.media.ic_calendar'))
            .width(12)
            .height(12)
            .fillColor(CloudThemeToken.textSecondary)
          Text(DateUtil.getFormatDateStr(new Date(item.update), 'yyyy-MM-dd'))
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)

        Row({space: 6}) {
          Image($r('app.media.ic_folder'))
            .width(12)
            .height(12)
            .fillColor(CloudThemeToken.textSecondary)
          Text(this.getPathText(item.dst))
            .fontSize(12)
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
    }
    .width('100%')
    .height(104)
    .borderRadius(CloudThemeToken.cardRadius)
    .padding(12)
    .backgroundColor(CloudThemeToken.surface)
    .onClick(() => {
      console.debug(TAG, 'onClick')
    })
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
    Row({space: 12}) {
      Stack({alignContent: Alignment.Center}) {
        DataPanel({ values: [this.getDownloadLength(item.files)], max: item.total, type: DataPanelType.Circle })
          .width(48)
          .height(48)
          .strokeWidth(4)
          .closeEffect(true)
          .valueColors([item.task_status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger])

        Text(item.files?.length ? item.files.length.toString() : '0')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
      }

      Column({space: 7}) {
        Text(this.getTaskName(item.name))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Row({space: 8}) {
          Image(item.task_status == Aria2Status.FINISHED ?
            $r('app.media.ic_checkmark_circle_fill') : $r('app.media.ic_xmark_circle_fill'))
            .width(12)
            .height(12)
            .fillColor(item.task_status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)
          Text(this.getTaskStatus(item.task_status))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)

          Text(this.getFileCountText(item.files ? item.files.length : 0))
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)

          Image($r('app.media.ic_calendar'))
            .width(12)
            .height(12)
            .fillColor(CloudThemeToken.textSecondary)
          Text(DateUtil.getFormatDateStr(new Date(item.update), 'yyyy-MM-dd'))
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)

        Row({space: 6}) {
          Image($r('app.media.ic_folder'))
            .width(12)
            .height(12)
            .fillColor(CloudThemeToken.textSecondary)
          Text(this.getPathText(item.dst))
            .fontSize(12)
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
        .width(24)
        .height(24)
    }
    .width('100%')
    .height(92)
    .borderRadius(CloudThemeToken.cardRadius)
    .padding(12)
    .backgroundColor(CloudThemeToken.surface)
    .onClick(() => {
      console.debug(TAG, 'onClick')
      this.currentFinishedDetail = item
      this.currentFinishedIndex = index
      this.showTaskDetailSheet = true
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
          Row().height(10)
        }
        this.finished()
      }
      .width('100%')
      .height('100%')
      .padding({bottom: this.tabBarHeight+10})
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
      .columnsTemplate('1fr')
      .maxCount(1)
      .cachedCount(3)
      .columnsGap(10)
      .rowsGap(10)
      .animation({duration: 300})
      .onReachEnd(() => {
        if (!this.isLastFinishedPage) {
          this.getAria2Finished(false)
        } else {
          console.warn(TAG, 'last finished page！！！')
        }
      })
      .bindSheet($$this.showTaskDetailSheet, this.taskDetailSheet(this.currentFinishedIndex, this.currentFinishedDetail), {
        detents: [SheetSize.FIT_CONTENT]
      })
    }
    .layoutWeight(1)
    .refreshOffset(77)
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
      .padding({bottom: this.tabBarHeight+10})
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
      .columnsTemplate('1fr')
      .maxCount(1)
      .cachedCount(3)
      .columnsGap(10)
      .rowsGap(10)
      // .animation({duration: 300})
      .onReachEnd(() => {
        if (!this.isLastTasksQueuePage) {
          this.getUserTasks(false)
        } else {
          console.warn(TAG, 'last task queue page！！！')
        }
      })
    }
    .layoutWeight(1)
    .refreshOffset(77)
    .pullToRefresh(true)
    .onRefreshing(() => {
      this.getUserTasks(true);
    })
  }

  @Builder taskQueueItem(task: UserTask) {
    Row({space: 12}) {
      Column({space: 8}) {
        Row({space: 8}) {
          Image($r('app.media.ic_calendar'))
            .width(12)
            .height(12)
            .fillColor(CloudThemeToken.textSecondary)
          Text(DateUtil.getFormatDateStr(new Date(task.create_date), 'yyyy-MM-dd'))
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)
        }

        Text(this.getTaskName(task.name))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Progress({value: task.progress, total: 100, type: ProgressType.Capsule})
          .width('100%')
          .height(6)
          .color(task.status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)
          .backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({space: 8}) {
          Image(task.status == Aria2Status.FINISHED ?
            $r('app.media.ic_checkmark_circle_fill') : $r('app.media.ic_xmark_circle_fill'))
              .width(12)
              .height(12)
              .fillColor(task.status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)

          Text($r('app.string.last_progress'))
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)

          Text(`${task.progress}%`)
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)

          Text(task.status == Aria2Status.FINISHED ?
            $r("app.string.finished") : $r("app.string.failed"))
            .fontSize(12)
            .fontColor(CloudThemeToken.textSecondary)
        }

        if (task.status != Aria2Status.FINISHED) {
          Row({space: 5}) {
            Image($r('app.media.ic_info_circle'))
              .width(12)
              .height(12)
              .fillColor(CloudThemeToken.textSecondary)

            Text(this.getErrorInfo(task.error))
              .fontSize(12)
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
        .width(40)
        .height(40)
        .fillColor(task.status == Aria2Status.FINISHED ? CloudThemeToken.success : CloudThemeToken.danger)
    }
    .width('100%')
    .constraintSize({ minHeight: 104 })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .borderRadius(CloudThemeToken.cardRadius)
    .padding(12)
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
}
