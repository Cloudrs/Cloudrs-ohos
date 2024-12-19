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
  private  aria2Downloading: Aria2Downloading[] = []
  private aria2FinishedSource: LazyDataSource<Aria2Finished> = new LazyDataSource()
  private tasksQueueSource: LazyDataSource<UserTask> = new LazyDataSource()
  @State totalFinished: number = 0;
  @State totalTasks: number = 0;
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
  @State showSheet: boolean = false

  aboutToAppear(): void {
    this.getAria2Downloading()
    this.getAria2Finished(true)
    this.getUserTasks(true)
  }

  getAria2Downloading() {
    CloudApi.aria2Downloading({
      onSuccess: (data) => {
        this.aria2Downloading = data
        console.debug(TAG, 'downloading number: ' + this.aria2Downloading.length)
      },
      onFailure: (msg) => {
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
    .padding({left: 10, right: 10, top: this.topRectHeight+10})
    .justifyContent(FlexAlign.Start)
    .bindSheet($$this.showSheet, this.detailSheet())
  }

  @Builder detailSheet() {
    Aria2FinishedDetail({detailData: this.currentFinishedDetail})
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
        // 创建离线下载任务
      })
    }
    .width('100%')
    .height(30)
  }

  getDownloadLength(files: Aria2Files[]) {
    let length: number = 0
    files.forEach((value) => {
      length += parseInt(value.completedLength)
    })
    return length
  }

  @Builder finishedItem(finished: Aria2Finished) {
    Row({space: 10}) {
      Stack({alignContent: Alignment.Center}) {
        DataPanel({ values: [this.getDownloadLength(finished.files)], max: finished.total, type: DataPanelType.Circle })
          .width(42)
          .height(42)
          .strokeWidth(4)
          .valueColors([finished.task_status == Aria2Status.FINISHED ? Color.Green : Color.Red])

        Text(finished.files.length.toString())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
      }

      Column({space: 5}) {
        Text(finished.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({overflow: TextOverflow.Ellipsis})

        Row({space: 5}) {
          Image(finished.task_status == Aria2Status.FINISHED ?
            $r('app.media.ic_checkmark_circle_fill') : $r('app.media.ic_xmark_circle_fill'))
            .width(12)
            .height(12)
            .fillColor(finished.task_status == Aria2Status.FINISHED ? Color.Green : Color.Red)
          Text(finished.task_status == Aria2Status.FINISHED ?
          $r('app.string.download_finished') : $r('app.string.download_failed'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)

          Divider().vertical(true).strokeWidth('4px').color($r('app.color.default_line_color'))

          Image($r('app.media.ic_calendar'))
            .width(12)
            .height(12)
            .fillColor($r('app.color.aria2_no_task_font'))
          Text(DateUtil.getFormatDateStr(new Date(finished.update), 'yyyy-MM-dd'))
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
    .backgroundColor(finished.task_status == Aria2Status.FINISHED ?
      $r("app.color.aria2_finished_background") : $r("app.color.aria2_failed_background"))
    .onClick(() => {
      console.debug(TAG, 'onClick')
      this.currentFinishedDetail = finished
      this.showSheet = true
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
    .margin({bottom: 10})
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder downloading() {
    if (this.aria2Downloading.length == 0) {
      GridItem() {
        this.noTask($r('app.string.no_finished_task'))
      }
    } else {
      ForEach(this.aria2Downloading, (item: Aria2Downloading, index) => {

      })
    }
  }

  @Builder finished() {
    if (this.totalFinished == 0) {
      GridItem() {
        this.noTask($r('app.string.no_download_task'))
      }
    } else {
      LazyForEach(this.aria2FinishedSource, (item: Aria2Finished, index) => {
        GridItem() {
          this.finishedItem(item)
        }
      }, (item: Aria2Finished, index:number) => item.gid + index)
    }
  }

  @Builder offlineDownload() {
    Refresh({refreshing: $$this.downloadRefresh}) {
      Grid(this.scroller) {
        this.downloading()
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
            .fontSize(14)
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
            .fontSize(14)
            .fontColor($r('app.color.aria2_no_task_font'))

          Text(task.status == Aria2Status.FINISHED ?
            $r('app.string.task_queue_finished') : $r('app.string.task_queue_failed'))
            .fontSize(14)
            .fontColor($r('app.color.aria2_no_task_font'))
        }

        if (task.status != Aria2Status.FINISHED) {
          Row({space: 5}) {
            Image($r('app.media.ic_info_circle'))
              .width(12)
              .height(12)
              .fillColor($r('app.color.aria2_no_task_font'))

            Text(this.getErrorInfo(task.error))
              .fontSize(14)
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
        .width(48)
        .height(48)
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