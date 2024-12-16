import Constant from "../../model/Constant";
import { Aria2Downloading, Aria2Finished, UserTask, UserTasks } from "../../model/net/ApiTypes";
import { CloudApi } from "../../model/net/CloudApi";

const TAG: string = 'TabRemote'

@Component
export struct TabRemoteDown {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State aria2Downloading: Aria2Downloading[] = []
  @State aria2Finished: Aria2Finished[] = []
  @State userTasks: UserTasks = {tasks: [], total: 0}
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
          console.debug(TAG, 'finished number: ' + this.aria2Finished.length)
        } else {
          console.warn(TAG, 'finished no found in this page ' + this.tasksPage)
        }
      },
      onFailure: (msg) => {
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
    Column() {
      Blank().height(this.topRectHeight)
      Text('远程下载')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}