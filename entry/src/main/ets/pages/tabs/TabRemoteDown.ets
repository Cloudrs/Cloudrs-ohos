import Constant from "../../model/Constant";
import { Aria2Downloading,
  Aria2Files,
  Aria2Finished, Aria2Status, UserTask, UserTasks } from "../../model/net/ApiTypes";
import { CloudApi } from "../../model/net/CloudApi";
import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from "@kit.ArkUI";
import { DateUtil } from "@pura/harmony-utils";

const TAG: string = 'TabRemote'

@Component
export struct TabRemoteDown {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
  @State aria2Downloading: Aria2Downloading[] = []
  @State aria2Finished: Aria2Finished[] = []
  @State userTasks: UserTasks = {tasks: [], total: 0}
  @State selectCapsuleOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: $r('app.string.download_offline') }, { text: $r('app.string.task_queue') }] as SegmentButtonItemTuple,
    multiply: false,
    backgroundBlurStyle: BlurStyle.BACKGROUND_THICK
  })
  @State selectedIndexes: number[] = [0]
  @State downloadRefresh: boolean = false
  @State taskQueueRefresh: boolean = false
  private finishedPage: number = 1
  private tasksPage: number = 1

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
      this.aria2Finished = []
      this.finishedPage = 1
    }

    CloudApi.aria2Finished(this.finishedPage, {
      onSuccess: (data) => {
        if (data.length > 0) {
          this.aria2Finished.push(...data)
          this.finishedPage++
          this.downloadRefresh = false
          console.debug(TAG, 'finished number: ' + this.aria2Finished.length)
        } else {
          console.warn(TAG, 'finished no found in this page ' + this.tasksPage)
        }
      },
      onFailure: (msg) => {
        this.downloadRefresh = false
        console.error(TAG, 'Aria2 finished get failed, msg: ' + msg)
      }
    })
  }

  getUserTasks(isFresh: boolean) {
    if (isFresh) {
      this.userTasks.tasks = []
      this.userTasks.total = 0
      this.tasksPage = 1
    }

    CloudApi.userTasks(this.tasksPage, {
      onSuccess: (data: UserTasks) => {
        if (data.tasks.length > 0) {
          this.userTasks.tasks.push(...data.tasks)
          this.tasksPage++
        } else {
          console.warn(TAG, 'tasks no found in this page ' + this.tasksPage)
        }
        this.userTasks.total = data.total
        console.debug(TAG, 'task number: ' + this.userTasks.total)
      },
      onFailure: (msg) => {
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
        Text('没有队列任务')
      }
    }
    .width('100%')
    .height('100%')
    .padding({left: 10, right: 10, top: this.topRectHeight+10})
    .justifyContent(FlexAlign.Start)
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
        .width(12)
        .height(12)
    }
    .width('100%')
    .height(60)
    .borderRadius(5)
    .padding(10)
    .backgroundColor(finished.task_status == Aria2Status.FINISHED ?
      $r("app.color.aria2_finished_background") : $r("app.color.aria2_failed_background"))
    .onClick(() => {

    })
  }

  @Builder noTask(isFinished: boolean) {
    Column() {
      Text(isFinished ? $r('app.string.no_finished_task') : $r('app.string.no_download_task'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.aria2_no_task_font'))
    }
    .backgroundColor($r('app.color.aria2_no_task_background'))
    .width('100%')
    .height(60)
    .borderRadius(5)
    .padding(10)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder downloading() {
    if (this.aria2Downloading.length == 0) {
      this.noTask(false)
    } else {
      ForEach(this.aria2Downloading, (item: Aria2Downloading, index) => {

      })
    }
  }

  @Builder finished() {
    if (this.aria2Finished.length == 0) {
      this.noTask(true)
    } else {
      ForEach(this.aria2Finished, (item: Aria2Finished, index) => {
        ListItem() {
          this.finishedItem(item)
        }
      }, (item: Aria2Finished, index:number) => item.gid + index)
    }
  }

  @Builder offlineDownload() {
    Refresh({refreshing: $$this.downloadRefresh}) {
      List({space: 10}) {
        this.downloading()
        this.finished()
      }
      .width('100%')
      .height('100%')
      .padding({bottom: this.tabBarHeight+10})
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
    }
    .layoutWeight(1)
    .refreshOffset(77)
    .pullToRefresh(true)
    .onRefreshing(() => {
      this.getAria2Downloading();
      this.getAria2Finished(true);
    })
  }
}