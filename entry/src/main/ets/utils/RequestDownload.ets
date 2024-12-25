
import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import Constant from '../model/Constant';
import { DownloadFileModel, DownloadState } from '../model/DownloadFileModel';
import Logger from './Logger';
import { fileUri } from '@kit.CoreFileKit';
import { FileUtil } from '@pura/harmony-utils';

const TAG: string = 'RequestDownload';
let isNetPause = false;

class RequestDownload {
  private context: common.UIAbilityContext | undefined = undefined;
  private waitList: DownloadFileModel[] = [];
  private downloadTasks: Map<string, request.agent.Task> = new Map();

  constructor() {
    setInterval(() => {
      this.flushBackgroundTask()
    }, 2000);
  }

  setDownloadTask(id: string, task: request.agent.Task) {
    this.downloadTasks.set(id, task)
  }

  getDownloadTask(id: string) {
    if (this.downloadTasks.has(id)) {
      return this.downloadTasks.get(id)
    }
    return undefined
  }

  deleteDownloadTask(id: string) {
    if (this.downloadTasks.has(id)) {
      this.downloadTasks.delete(id)
    }
  }

  downloadFileBackground(file: DownloadFileModel) {
    if (file) {
      Logger.info(TAG, 'downloadFile to -> ' + file.path);
      this.context = getContext(this) as common.UIAbilityContext;
      this.waitList.push(file)
    }
  }

  private async flushBackgroundTask() {
    let tasks = await request.agent.search({
      state: request.agent.State.RUNNING
    });

    if (tasks.length < Constant.TASK_MAX && this.waitList.length > 0) {
      let downloadList: DownloadFileModel[] = [];
      if (this.waitList.length <= Constant.TASK_MAX - tasks.length) {
        downloadList = this.waitList;
        this.waitList = [];
      } else {
        downloadList = this.waitList.slice(0, Constant.TASK_MAX - tasks.length);
        this.waitList = this.waitList.slice(Constant.TASK_MAX - tasks.length, this.waitList.length);
      }
      Logger.info(TAG, `this.waitList = ${JSON.stringify(this.waitList)}`);
      this.createBackgroundTask(downloadList);
    }
  }

  private async createBackgroundTask(downloadList: DownloadFileModel[]) {
    if (this.context === undefined) {
      return;
    }

    downloadList.forEach(async (fileModel, index) => {
      let downloadConfig: request.agent.Config = {
        action: request.agent.Action.DOWNLOAD,
        url: fileModel.url,
        method: 'GET',
        title: 'download',
        mode: request.agent.Mode.BACKGROUND,
        network: request.agent.Network.ANY,
        saveas: './' + FileUtil.getFileName(fileModel.path),
        overwrite: true,
        gauge: true
      }

      try {
        request.agent.create(this.context, downloadConfig).then((task: request.agent.Task) => {
          task.on('progress', async (progress: request.agent.Progress) => {
            Logger.info(TAG, `progress,  progress = ${progress.processed} ${progress.state}`);

            let processed = Number(progress.processed.toString()).valueOf();
            let size = progress.sizes[0];
            let process: number = Math.floor(processed / size * 100);

            if (process < 100) {
              if (fileModel.callback) {
                fileModel.callback(progress.processed, DownloadState.RUNNING);
              }
            }
          })

          task.on('completed', async (progress: request.agent.Progress) => {
            Logger.info(TAG, `download complete, file= ${fileModel.url}, progress = ${progress.processed}`);
            if (fileModel.callback) {
              fileModel.callback(progress.processed, DownloadState.COMPLETED);
            }
            this.deleteTask(fileModel.id);
          })

          task.on('pause', async (progress: request.agent.Progress) => {
            let taskInfo = await request.agent.show(task.tid);
            Logger.info(TAG, `pause,  resean = ${taskInfo.reason}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo.faults)}`);
            isNetPause = taskInfo.faults === 0;
            if (fileModel.callback) {
              if (isNetPause) {
                fileModel.callback(progress.processed, DownloadState.PAUSED);
              } else {
                fileModel.callback(progress.processed, DownloadState.STOPPED);
              }
            }
          })

          task.on('resume', async (progress: request.agent.Progress) => {
            let taskInfo = await request.agent.show(task.tid);
            Logger.info(TAG, `resume,  resean = ${taskInfo.reason}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo.faults)}`);
            if (fileModel.callback) {
              if (isNetPause) {
                isNetPause = false;
                fileModel.callback(progress.processed, DownloadState.RUNNING);
              } else {
                fileModel.callback(progress.processed, DownloadState.RUNNING);
              }
            }
          })

          task.on('failed', async (progress: request.agent.Progress) => {
            let taskInfo = await request.agent.show(task.tid);
            Logger.info(TAG, `fail,  resean = ${taskInfo.reason}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo.faults)}`);
            if (fileModel.callback) {
              fileModel.callback(progress.processed, DownloadState.FAILED);
            }
            this.deleteTask(fileModel.id);
          })

          task.start().then(() => {
            this.setDownloadTask(fileModel.id, task);
          }).catch((err: Error) => {
            Logger.error(TAG, 'task start error: ', JSON.stringify(err));
          });
        })
      } catch (err) {
        Logger.error(TAG, `task create error: ${JSON.stringify(err)}`);
        this.waitList.push(fileModel);
      }
    })
  }

  async pause(id: string) {
    let task = this.getDownloadTask(id)
    if (task) {
      let taskInfo = await request.agent.show(task.tid);
      Logger.info(TAG, `task pause, taskInfo  = ${JSON.stringify(taskInfo)}`);
      await task.pause();
    }
  }

  async resume(id: string) {
    let task = this.getDownloadTask(id)
    if (task) {
      let taskInfo = await request.agent.show(task.tid);
      Logger.info(TAG, `task resume, taskInfo  = ${JSON.stringify(taskInfo)}`);
      await task.resume();
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
        await request.agent.remove(task.tid);
        this.deleteDownloadTask(id);
      } catch (err) {
        Logger.info(TAG, `deleteTask fail, err= ${JSON.stringify(err)}`);
      }
    }
  }
}

export const requestDownload = new RequestDownload();