
import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import Constant from '../model/Constant';
import { FileModel, FileModelState } from '../model/FileModel';
import Logger from './Logger';
import AppLogger from './AppLogger';
import { CommonUtil } from './CommonUtil';

const TAG: string = 'RequestDownload';

class RequestDownload {
  private context: common.UIAbilityContext | undefined = undefined;
  private waitList: FileModel[] = [];
  private waitBegins: Map<string, number> = new Map();
  private downloadTasks: Map<string, request.agent.Task> = new Map();
  private fileModels: Map<string, FileModel> = new Map();
  private lastTrans: Map<string, number> = new Map();
  private taskBegins: Map<string, number> = new Map();
  private userPausedTids: Set<string> = new Set();

  constructor() {
    setInterval(() => {
      this.flushBackgroundTask()
    }, Constant.BACKGROUND_TASK_FLUSH_INTERVAL_MS);
  }

  setDownloadTask(id: string, task: request.agent.Task, fileModel: FileModel) {
    this.downloadTasks.set(id, task)
    this.fileModels.set(id, fileModel)
  }

  getDownloadTask(id: string) {
    if (this.downloadTasks.has(id)) {
      return this.downloadTasks.get(id)
    }
    return undefined
  }

  deleteDownloadTask(id: string) {
    this.downloadTasks.delete(id)
    this.fileModels.delete(id)
    this.lastTrans.delete(id)
  }

  getTaskTid(id: string): string {
    return this.downloadTasks.get(id)?.tid ?? ''
  }

  downloadFileBackground(file: FileModel, context?: common.UIAbilityContext, begins: number = 0) {
    if (file) {
      Logger.info(TAG, `downloadFile to -> ${file.path}, begins=${begins}`);
      AppLogger.info(TAG, `enqueue ${file.path}, begins=${begins}`);
      if (context) {
        this.context = context;
      }
      this.waitList.push(file)
      if (begins > 0) {
        this.waitBegins.set(file.id, begins)
      }
    }
  }

  private async flushBackgroundTask() {
    const runningCount = await this.getRunningTaskCount();

    if (runningCount < Constant.TASK_MAX && this.waitList.length > 0) {
      let downloadList: FileModel[] = [];
      if (this.waitList.length <= Constant.TASK_MAX - runningCount) {
        downloadList = this.waitList;
        this.waitList = [];
      } else {
        downloadList = this.waitList.slice(0, Constant.TASK_MAX - runningCount);
        this.waitList = this.waitList.slice(Constant.TASK_MAX - runningCount, this.waitList.length);
      }
      Logger.info(TAG, `this.waitList = ${JSON.stringify(this.waitList)}`);
      this.createBackgroundTask(downloadList);
    }
  }

  private async createBackgroundTask(downloadList: FileModel[]) {
    if (this.context === undefined) {
      return;
    }

    downloadList.forEach(async (fileModel, index) => {
      const begins = this.waitBegins.get(fileModel.id) ?? 0;
      this.waitBegins.delete(fileModel.id);
      let downloadConfig: request.agent.Config = {
        action: request.agent.Action.DOWNLOAD,
        url: fileModel.url,
        method: Constant.REQUEST_METHOD_GET,
        title: Constant.REQUEST_TITLE_DOWNLOAD,
        mode: request.agent.Mode.BACKGROUND,
        network: request.agent.Network.ANY,
        saveas: Constant.REQUEST_SAVE_AS_PREFIX + CommonUtil.getFileName(fileModel.path),
        overwrite: begins > 0 ? false : Constant.REQUEST_OVERWRITE_ENABLED,
        gauge: Constant.REQUEST_GAUGE_ENABLED,
        begins
      }

      try {
        request.agent.create(this.context, downloadConfig).then((task: request.agent.Task) => {
          this.taskBegins.set(fileModel.id, begins);
          this.bindTaskEvents(task, fileModel);
          task.start().then(() => {
            this.setDownloadTask(fileModel.id, task, fileModel);
          }).catch((err: Error) => {
            Logger.error(TAG, 'task start error: ', JSON.stringify(err));
          });
        }).catch((err: Error) => {
          Logger.error(TAG, `task create error: ${JSON.stringify(err)}`);
          this.waitList.push(fileModel);
        })
      } catch (err) {
        Logger.error(TAG, `task create error: ${JSON.stringify(err)}`);
        this.waitList.push(fileModel);
      }
    })
  }

  private bindTaskEvents(task: request.agent.Task, fileModel: FileModel): void {
    task.on('progress', async (progress: request.agent.Progress) => {
      const begins = this.taskBegins.get(fileModel.id) ?? 0;
      const absoluteTrans = progress.processed + begins;
      Logger.info(TAG, `progress, processed=${progress.processed}, begins=${begins}, abs=${absoluteTrans}, state=${progress.state}`);
      this.lastTrans.set(fileModel.id, absoluteTrans);

      if (this.userPausedTids.has(task.tid)) {
        return;
      }

      let size = progress.sizes[Constant.FIRST_ARRAY_INDEX];
      if (size <= Constant.BACKGROUND_TASK_EMPTY_SIZE) {
        return;
      }
      let process: number = Math.floor(progress.processed / size * Constant.BACKGROUND_TASK_COMPLETE_PERCENT);

      if (process < Constant.BACKGROUND_TASK_COMPLETE_PERCENT) {
        if (fileModel.callback) {
          fileModel.callback(absoluteTrans, FileModelState.RUNNING);
        }
      }
    })

    task.on('completed', async (progress: request.agent.Progress) => {
      const begins = this.taskBegins.get(fileModel.id) ?? 0;
      const absoluteTrans = progress.processed + begins;
      Logger.info(TAG, `complete, file= ${fileModel.url}, abs=${absoluteTrans}`);
      AppLogger.info(TAG, `complete ${fileModel.path}`);
      if (fileModel.callback) {
        fileModel.callback(absoluteTrans, FileModelState.COMPLETED);
      }
      this.detachTask(fileModel.id, true);
    })

    task.on('pause', async (progress: request.agent.Progress) => {
      const begins = this.taskBegins.get(fileModel.id) ?? 0;
      const absoluteTrans = progress.processed + begins;
      const taskInfo = await this.showTask(task.tid);
      const isUserPaused = this.userPausedTids.has(task.tid);
      Logger.info(TAG, `pause event, user=${isUserPaused}, faults=${JSON.stringify(taskInfo?.faults ?? '')}, abs=${absoluteTrans}`);
      AppLogger.info(TAG, `pause ${fileModel.path}, user=${isUserPaused}`);
      if (fileModel.callback) {
        fileModel.callback(absoluteTrans, isUserPaused ? FileModelState.PAUSED : FileModelState.STOPPED);
      }
    })

    task.on('resume', async (progress: request.agent.Progress) => {
      const begins = this.taskBegins.get(fileModel.id) ?? 0;
      const absoluteTrans = progress.processed + begins;
      Logger.info(TAG, `resume event, abs=${absoluteTrans}`);
      AppLogger.info(TAG, `resume ${fileModel.path}`);
      this.userPausedTids.delete(task.tid);
      if (fileModel.callback) {
        fileModel.callback(absoluteTrans, FileModelState.RUNNING);
      }
    })

    task.on('failed', async (progress: request.agent.Progress) => {
      const begins = this.taskBegins.get(fileModel.id) ?? 0;
      const absoluteTrans = progress.processed + begins;
      const taskInfo = await this.showTask(task.tid);
      Logger.info(TAG, `fail, reason = ${taskInfo?.reason ?? ''}, abs=${absoluteTrans}, faults = ${JSON.stringify(taskInfo?.faults ?? '')}`);
      AppLogger.warn(TAG, `fail ${fileModel.path}, reason=${taskInfo?.reason ?? ''}, faults=${JSON.stringify(taskInfo?.faults ?? '')}`);
      if (fileModel.callback) {
        fileModel.callback(absoluteTrans, FileModelState.FAILED);
      }
      this.detachTask(fileModel.id, false);
    })
  }

  async restoreTask(id: string, context: common.UIAbilityContext, tid: string,
                    fileModel: FileModel, autoResume: boolean): Promise<boolean> {
    if (this.context === undefined) {
      this.context = context;
    }
    try {
      const task = await request.agent.getTask(context, tid);
      this.bindTaskEvents(task, fileModel);
      this.downloadTasks.set(id, task);
      this.fileModels.set(id, fileModel);
      this.lastTrans.set(id, this.lastTrans.get(id) ?? 0);
      Logger.info(TAG, `restoreTask ok, id=${id}, tid=${tid}`);
      if (autoResume) {
        await task.resume();
      }
      return true;
    } catch (err) {
      Logger.error(TAG, `restoreTask failed, tid=${tid}, err=${JSON.stringify(err)}`);
      return false;
    }
  }

  async pause(id: string) {
    const task = this.getDownloadTask(id)
    const fileModel = this.fileModels.get(id)
    if (!task) {
      Logger.warn(TAG, `pause: task not found, id=${id}`);
      return;
    }
    try {
      this.userPausedTids.add(task.tid);
      await task.pause();
      Logger.info(TAG, `pause ok, id=${id}, tid=${task.tid}`);
      if (fileModel?.callback) {
        fileModel.callback(this.lastTrans.get(id) ?? 0, FileModelState.PAUSED);
      }
    } catch (err) {
      this.userPausedTids.delete(task.tid);
      Logger.error(TAG, `task pause failed, err = ${JSON.stringify(err)}`);
    }
  }

  async resume(id: string) {
    const task = this.getDownloadTask(id)
    const fileModel = this.fileModels.get(id)
    if (!task) {
      Logger.warn(TAG, `resume: task not found, id=${id}`);
      return;
    }
    try {
      await task.resume();
      this.userPausedTids.delete(task.tid);
      Logger.info(TAG, `resume ok, id=${id}, tid=${task.tid}`);
      if (fileModel?.callback) {
        fileModel.callback(this.lastTrans.get(id) ?? 0, FileModelState.RUNNING);
      }
    } catch (err) {
      Logger.error(TAG, `task resume failed, err = ${JSON.stringify(err)}`);
    }
  }

  async deleteTask(id: string) {
    await this.detachTask(id, true)
  }

  async removeSystemTask(tid: string): Promise<void> {
    if (tid.length === 0) {
      return
    }
    try {
      await request.agent.remove(tid)
      Logger.info(TAG, `removeSystemTask ok, tid=${tid}`)
    } catch (err) {
      Logger.warn(TAG, `removeSystemTask failed, tid=${tid}, err=${JSON.stringify(err)}`)
    }
  }

  private async detachTask(id: string, removeSystem: boolean): Promise<void> {
    const task = this.getDownloadTask(id)
    if (!task) {
      return
    }
    try {
      task.off('progress');
      task.off('completed');
      task.off('failed');
      task.off('pause');
      task.off('resume');
      this.userPausedTids.delete(task.tid);
      this.taskBegins.delete(id);
      if (removeSystem) {
        await request.agent.remove(task.tid);
      }
      this.deleteDownloadTask(id);
    } catch (err) {
      Logger.info(TAG, `detachTask fail, removeSystem=${removeSystem}, err=${JSON.stringify(err)}`);
    }
  }

  private async getRunningTaskCount(): Promise<number> {
    try {
      const tasks = await request.agent.search({
        state: request.agent.State.RUNNING
      });
      return tasks.length;
    } catch (err) {
      Logger.error(TAG, `search running tasks failed, err = ${JSON.stringify(err)}`);
      return 0;
    }
  }

  async showTask(tid: string): Promise<request.agent.TaskInfo | undefined> {
    try {
      return await request.agent.show(tid);
    } catch (err) {
      Logger.error(TAG, `show task failed, tid = ${tid}, err = ${JSON.stringify(err)}`);
      return undefined;
    }
  }
}

export const requestDownload = new RequestDownload();
