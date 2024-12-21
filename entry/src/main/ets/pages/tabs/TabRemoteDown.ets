import Constant from "../../model/Constant";
import { Aria2Downloading,
  Aria2Files,
  Aria2Finished, Aria2Status,
  TaskError,
  UserTask, UserTasks,
  UserTaskType } from "../../model/net/ApiTypes";
import { CloudApi } from "../../model/net/CloudApi";
import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import { DateUtil } from "@pura/harmony-utils";
import LazyDataSource from "../../utils/LazyDataSource";
import { Aria2FinishedDetail } from "../../components/Aria2FinishedDetail";
import { CommonUtil } from "../../utils/CommonUtil";
import { Aria2Create } from "../../components/Aria2Create";
import { DialogAction, DialogHelper } from "@pura/harmony-dialog";
import { showToast } from "../../utils/ToastUtil";

const TAG: string = 'TabRemote'

@Component
export struct TabRemoteDown {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
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
        this.getAria2Finished(true)
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

  getAria2Finished(isFresh: boolean) {
    if (isFresh) {
      this.aria2FinishedSource.clear()
      this.finishedPage = 1
      this.isLastFinishedPage = false
    }

    CloudApi.aria2Finished(this.finishedPage, {
      onSuccess: (data) => {
        if (data.length > 0) {
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
    Column({space: 10}) {
      this.title()
      if (this.selectedIndexes[0] == 0) {
        this.offlineDownload()
      }
      else {
        this.tasksQueue()
      }
    }
    .width('100%')
    .height('100%')
    .padding({left: 15, right: 15, top: this.topRectHeight+10})
    .justifyContent(FlexAlign.Start)
  }

  deleteTaskConfirm(index: number, item: Aria2Finished) {
    DialogHelper.showAlertDialog({
      primaryTitle:  $r('app.string.delete_task_confirm'),
      content: item.name,
      primaryButton: {value: $r('app.string.dialog_cancel')},
      secondaryButton: {value: $r('app.string.dialog_delete'), role: ButtonRole.ERROR},
      onAction: (action: number, dialogId: string, content: string) => {
        if (action == DialogAction.TWO) {
          this.showTaskDetailSheet = false
          console.debug(TAG, `action: ${action}, content: ${content}`)
          if (item.name != content) {
            CloudApi.deleteAria2Task(item.gid, {
              onSuccess: (data) => {
                this.aria2FinishedSource.deleteData(index)
                showToast($r('app.string.delete_task_success'))
              },
              onFailure: (msg) => {
                console.error(TAG, '删除任务失败 msg: ' + msg)
                showToast($r('app.string.delete_task_failed'))
              }
            })
          }
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

      Button({type: ButtonType.Circle}) {
        Image($r('app.media.ic_plus'))
          .fillColor(Color.Black)
      }
      .width(20)
      .height(20)
      .margin({right: 10})
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showCreateSheet = true
      })
      .bindSheet($$this.showCreateSheet, this.taskCreateSheet(), {
        title: {title: $r('app.string.download_offline')},
        backgroundColor: $r('app.color.sheet_default_background'),
      })
    }
    .width('100%')
    .height(30)
  }

  getDownloadLength(files: Aria2Files[]) {
    let length: number = 0
    files?.forEach((value) => {
      length += parseInt(value.completedLength)
    })
    return length
  }

  @Builder downloadingItem(item: Aria2Downloading) {
    Row({space: 10}) {
      Stack({alignContent: Alignment.Center}) {
        DataPanel({ values: [item.downloaded], max: item.total, type: DataPanelType.Circle })
          .width(42)
          .height(42)
          .strokeWidth(4)
          .valueColors([Color.Blue])

        Text(item.info.files ? item.info.files.length.toString() : '1')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
      }

      Column({space: 5}) {
        Text(item.name === '.' || item.name === '' ? $r('app.string.aria2_unknown_name') : item.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Row({space: 5}) {
          Image($r('app.media.ic_arrowshape_down'))
            .width(12)
            .height(12)
            .fillColor(Color.Black)
          Text(CommonUtil.formatBytes(item.speed, 1)+'/s')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)

          Divider().vertical(true).strokeWidth('4px').color($r('app.color.default_line_color'))

          Image($r('app.media.ic_calendar'))
            .width(12)
            .height(12)
            .fillColor($r('app.color.aria2_no_task_font'))
          Text(DateUtil.getFormatDateStr(new Date(item.update), 'yyyy-MM-dd'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
        }
        .height(15)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .height('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Image($r('app.media.ic_dot_grid'))
        .width(20)
        .height(20)
    }
    .width('100%')
    .height(60)
    .borderRadius(10)
    .padding(10)
    .backgroundColor($r("app.color.aria2_default_background"))
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
    Row({space: 10}) {
      Stack({alignContent: Alignment.Center}) {
        DataPanel({ values: [this.getDownloadLength(item.files)], max: item.total, type: DataPanelType.Circle })
          .width(42)
          .height(42)
          .strokeWidth(4)
          .closeEffect(true)
          .valueColors([item.task_status == Aria2Status.FINISHED ? Color.Green : Color.Red])

        Text(item.files?.length.toString())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
      }

      Column({space: 5}) {
        Text(item.name === '.' ? $r('app.string.aria2_unknown_name') : item.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Row({space: 5}) {
          Image(item.task_status == Aria2Status.FINISHED ?
            $r('app.media.ic_checkmark_circle_fill') : $r('app.media.ic_xmark_circle_fill'))
            .width(12)
            .height(12)
            .fillColor(item.task_status == Aria2Status.FINISHED ? Color.Green : Color.Red)
          Text(this.getTaskStatus(item.task_status))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)

          Divider().vertical(true).strokeWidth('4px').color($r('app.color.default_line_color'))

          Image($r('app.media.ic_calendar'))
            .width(12)
            .height(12)
            .fillColor($r('app.color.aria2_no_task_font'))
          Text(DateUtil.getFormatDateStr(new Date(item.update), 'yyyy-MM-dd'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
        }
        .height(15)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .height('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Image($r('app.media.ic_dot_grid'))
        .width(20)
        .height(20)
    }
    .width('100%')
    .height(60)
    .borderRadius(10)
    .padding(10)
    .backgroundColor(item.task_status == Aria2Status.FINISHED ?
      $r("app.color.aria2_finished_background") : $r("app.color.aria2_failed_background"))
    .onClick(() => {
      console.debug(TAG, 'onClick')
      this.currentFinishedDetail = item
      this.currentFinishedIndex = index
      this.showTaskDetailSheet = true
    })
  }

  @Builder noTask(title: ResourceStr) {
    Column() {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.aria2_no_task_font'))
    }
    .backgroundColor($r("app.color.aria2_default_background"))
    .width('100%')
    .height(80)
    .borderRadius(10)
    .padding(10)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
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
      .backgroundColor(Color.White)
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
      .bindSheet($$this.showTaskDetailSheet, this.taskDetailSheet(this.currentFinishedIndex, this.currentFinishedDetail))
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
          }, (item: UserTask, index:number) => item.create_date + index)
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
      .animation({duration: 300})
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
    Row() {
      Column({space: 5}) {
        Row({space: 5}) {
          Image($r('app.media.ic_calendar'))
            .width(14)
            .height(14)
            .fillColor($r('app.color.aria2_no_task_font'))
          Text(DateUtil.getFormatDateStr(new Date(task.create_date), 'yyyy-MM-dd'))
            .fontSize(12)
            .fontColor($r('app.color.aria2_no_task_font'))
        }

        Text(task.type == UserTaskType.FileTransfer ?
          $r('app.string.file_transfer') : $r('app.string.policy_transfer'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)

        Row({space: 5}) {
          Image(task.status == Aria2Status.FINISHED ?
            $r('app.media.ic_checkmark_circle_fill') : $r('app.media.ic_xmark_circle_fill'))
              .width(12)
              .height(12)
              .fillColor(task.status == Aria2Status.FINISHED ? Color.Green : Color.Red)

          Text($r('app.string.last_progress'))
            .fontSize(12)
            .fontColor($r('app.color.aria2_no_task_font'))

          Text(task.status == Aria2Status.FINISHED ?
            $r('app.string.task_queue_finished') : $r('app.string.task_queue_failed'))
            .fontSize(12)
            .fontColor($r('app.color.aria2_no_task_font'))
        }

        if (task.status != Aria2Status.FINISHED) {
          Row({space: 5}) {
            Image($r('app.media.ic_info_circle'))
              .width(12)
              .height(12)
              .fillColor($r('app.color.aria2_no_task_font'))

            Text(this.getErrorInfo(task.error))
              .fontSize(12)
              .fontColor(Color.Red)
              .wordBreak(WordBreak.BREAK_ALL)
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
        .fillColor(task.status == Aria2Status.FINISHED ? Color.Green : Color.Red)
    }
    .width('100%')
    // .height(80)
    .padding({left: 15, right: 15})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .borderRadius(10)
    .padding(10)
    .backgroundColor($r('app.color.aria2_default_background'))
  }

  getErrorInfo(errorJson: string) {
    let error: TaskError = JSON.parse(errorJson)
    return `${error.msg}:${error.error}`
  }
}