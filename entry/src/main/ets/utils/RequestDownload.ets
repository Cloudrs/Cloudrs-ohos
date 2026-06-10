
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
  private downloadTasks: Map<string, request.agent.Task> = new Map();
  private fileModels: Map<string, FileModel> = new Map();
  private lastTrans: Map<string, number> = new Map();
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

  downloadFileBackground(file: FileModel, context?: common.UIAbilityContext) {
    if (file) {
      Logger.info(TAG, 'downloadFile to -> ' + file.path);
      AppLogger.info(TAG, `enqueue ${file.path}`);
      if (context) {
        this.context = context;
      }
      this.waitList.push(file)
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
      let downloadConfig: request.agent.Config = {
        action: request.agent.Action.DOWNLOAD,
        url: fileModel.url,
        method: Constant.REQUEST_METHOD_GET,
        title: Constant.REQUEST_TITLE_DOWNLOAD,
        mode: request.agent.Mode.BACKGROUND,
        network: request.agent.Network.ANY,
        saveas: Constant.REQUEST_SAVE_AS_PREFIX + CommonUtil.getFileName(fileModel.path),
        overwrite: Constant.REQUEST_OVERWRITE_ENABLED,
        gauge: Constant.REQUEST_GAUGE_ENABLED
      }

      try {
        request.agent.create(this.context, downloadConfig).then((task: request.agent.Task) => {
          task.on('progress', async (progress: request.agent.Progress) => {
            Logger.info(TAG, `progress,  progress = ${progress.processed} ${progress.state}`);
            this.lastTrans.set(fileModel.id, progress.processed);

            if (this.userPausedTids.has(task.tid)) {
              return;
            }

            let processed = Number(progress.processed.toString()).valueOf();
            let size = progress.sizes[Constant.FIRST_ARRAY_INDEX];
            if (size <= Constant.BACKGROUND_TASK_EMPTY_SIZE) {
              return;
            }
            let process: number = Math.floor(processed / size * Constant.BACKGROUND_TASK_COMPLETE_PERCENT);

            if (process < Constant.BACKGROUND_TASK_COMPLETE_PERCENT) {
              if (fileModel.callback) {
                fileModel.callback(progress.processed, FileModelState.RUNNING);
              }
            }
          })

          task.on('completed', async (progress: request.agent.Progress) => {
            Logger.info(TAG, `complete, file= ${fileModel.url}, progress = ${progress.processed}`);
            AppLogger.info(TAG, `complete ${fileModel.path}`);
            if (fileModel.callback) {
              fileModel.callback(progress.processed, FileModelState.COMPLETED);
            }
            this.deleteTask(fileModel.id);
          })

          task.on('pause', async (progress: request.agent.Progress) => {
            const taskInfo = await this.showTask(task.tid);
            const isUserPaused = this.userPausedTids.has(task.tid);
            Logger.info(TAG, `pause event, user=${isUserPaused}, faults=${JSON.stringify(taskInfo?.faults ?? '')}, progress=${progress.processed}`);
            AppLogger.info(TAG, `pause ${fileModel.path}, user=${isUserPaused}`);
            if (fileModel.callback) {
              fileModel.callback(progress.processed, isUserPaused ? FileModelState.PAUSED : FileModelState.STOPPED);
            }
          })

          task.on('resume', async (progress: request.agent.Progress) => {
            Logger.info(TAG, `resume event, progress=${progress.processed}`);
            AppLogger.info(TAG, `resume ${fileModel.path}`);
            this.userPausedTids.delete(task.tid);
            if (fileModel.callback) {
              fileModel.callback(progress.processed, FileModelState.RUNNING);
            }
          })

          task.on('failed', async (progress: request.agent.Progress) => {
            const taskInfo = await this.showTask(task.tid);
            Logger.info(TAG, `fail, reason = ${taskInfo?.reason ?? ''}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo?.faults ?? '')}`);
            AppLogger.warn(TAG, `fail ${fileModel.path}, reason=${taskInfo?.reason ?? ''}, faults=${JSON.stringify(taskInfo?.faults ?? '')}`);
            if (fileModel.callback) {
              fileModel.callback(progress.processed, FileModelState.FAILED);
            }
            this.deleteTask(fileModel.id);
          })

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
    let task = this.getDownloadTask(id)
    if (task) {
      try {
        task.off('progress');
        task.off('completed');
        task.off('failed');
        task.off('pause');
        task.off('resume');
        this.userPausedTids.delete(task.tid);
        await request.agent.remove(task.tid);
        this.deleteDownloadTask(id);
      } catch (err) {
        Logger.info(TAG, `deleteTask fail, err= ${JSON.stringify(err)}`);
      }
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

  private async showTask(tid: string): Promise<request.agent.TaskInfo | undefined> {
    try {
      return await request.agent.show(tid);
    } catch (err) {
      Logger.error(TAG, `show task failed, tid = ${tid}, err = ${JSON.stringify(err)}`);
      return undefined;
    }
  }
}

export const requestDownload = new RequestDownload();
