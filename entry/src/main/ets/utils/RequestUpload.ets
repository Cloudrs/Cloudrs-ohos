
import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import Constant from '../model/Constant';
import { FileModel, FileModelState } from '../model/FileModel';
import Logger from './Logger';
import { FileUtil } from '@pura/harmony-utils';

const TAG: string = 'RequestUpload';
let isNetPause = false;

class RequestUpload {
  private context: common.UIAbilityContext | undefined = undefined;
  private waitList: FileModel[] = [];
  private uploadTasks: Map<string, request.agent.Task> = new Map();

  constructor() {
    setInterval(() => {
      this.flushBackgroundTask()
    }, 2000);
  }

  setUploadTask(id: string, task: request.agent.Task) {
    this.uploadTasks.set(id, task)
  }

  getUploadTask(id: string) {
    if (this.uploadTasks.has(id)) {
      return this.uploadTasks.get(id)
    }
    return undefined
  }

  deleteUploadTask(id: string) {
    if (this.uploadTasks.has(id)) {
      this.uploadTasks.delete(id)
    }
  }

  uploadFileBackground(file: FileModel) {
    if (file) {
      Logger.info(TAG, 'upload ' + file.path);
      this.context = getContext(this) as common.UIAbilityContext;
      this.waitList.push(file)
    }
  }

  private async flushBackgroundTask() {
    let tasks = await request.agent.search({
      state: request.agent.State.RUNNING
    });

    if (tasks.length < Constant.TASK_MAX && this.waitList.length > 0) {
      let uploadList: FileModel[] = [];
      if (this.waitList.length <= Constant.TASK_MAX - tasks.length) {
        uploadList = this.waitList;
        this.waitList = [];
      } else {
        uploadList = this.waitList.slice(0, Constant.TASK_MAX - tasks.length);
        this.waitList = this.waitList.slice(Constant.TASK_MAX - tasks.length, this.waitList.length);
      }
      Logger.info(TAG, `this.waitList = ${JSON.stringify(this.waitList)}`);
      this.createBackgroundTask(uploadList);
    }
  }

  private async createBackgroundTask(uploadList: FileModel[]) {
    if (this.context === undefined) {
      return;
    }

    uploadList.forEach(async (fileModel, index) => {
      let uploadConfig: request.agent.Config = {
        action: request.agent.Action.UPLOAD,
        url: fileModel.url,
        method: 'POST',
        title: 'upload',
        mode: request.agent.Mode.BACKGROUND,
        network: request.agent.Network.ANY,
        gauge: true
      }

      try {
        request.agent.create(this.context, uploadConfig).then((task: request.agent.Task) => {
          task.on('progress', async (progress: request.agent.Progress) => {
            Logger.info(TAG, `progress,  progress = ${progress.processed} ${progress.state}`);

            let processed = Number(progress.processed.toString()).valueOf();
            let size = progress.sizes[0];
            let process: number = Math.floor(processed / size * 100);

            if (process < 100) {
              if (fileModel.callback) {
                fileModel.callback(progress.processed, FileModelState.RUNNING);
              }
            }
          })

          task.on('completed', async (progress: request.agent.Progress) => {
            Logger.info(TAG, `complete, file= ${fileModel.url}, progress = ${progress.processed}`);
            if (fileModel.callback) {
              fileModel.callback(progress.processed, FileModelState.COMPLETED);
            }
            this.deleteTask(fileModel.id);
          })

          task.on('pause', async (progress: request.agent.Progress) => {
            let taskInfo = await request.agent.show(task.tid);
            Logger.info(TAG, `pause,  resean = ${taskInfo.reason}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo.faults)}`);
            isNetPause = taskInfo.faults === 0;
            if (fileModel.callback) {
              if (isNetPause) {
                fileModel.callback(progress.processed, FileModelState.PAUSED);
              } else {
                fileModel.callback(progress.processed, FileModelState.STOPPED);
              }
            }
          })

          task.on('resume', async (progress: request.agent.Progress) => {
            let taskInfo = await request.agent.show(task.tid);
            Logger.info(TAG, `resume,  resean = ${taskInfo.reason}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo.faults)}`);
            if (fileModel.callback) {
              if (isNetPause) {
                isNetPause = false;
                fileModel.callback(progress.processed, FileModelState.RUNNING);
              } else {
                fileModel.callback(progress.processed, FileModelState.RUNNING);
              }
            }
          })

          task.on('failed', async (progress: request.agent.Progress) => {
            let taskInfo = await request.agent.show(task.tid);
            Logger.info(TAG, `failed,  resean = ${taskInfo.reason}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo.faults)}`);
            if (fileModel.callback) {
              fileModel.callback(progress.processed, FileModelState.FAILED);
            }
            this.deleteTask(fileModel.id);
          })

          task.start().then(() => {
            this.setUploadTask(fileModel.id, task);
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
    let task = this.getUploadTask(id)
    if (task) {
      let taskInfo = await request.agent.show(task.tid);
      Logger.info(TAG, `task pause, taskInfo  = ${JSON.stringify(taskInfo)}`);
      await task.pause();
    }
  }

  async resume(id: string) {
    let task = this.getUploadTask(id)
    if (task) {
      let taskInfo = await request.agent.show(task.tid);
      Logger.info(TAG, `task resume, taskInfo  = ${JSON.stringify(taskInfo)}`);
      await task.resume();
    }
  }

  async deleteTask(id: string) {
    let task = this.getUploadTask(id)
    if (task) {
      try {
        task.off('progress');
        task.off('completed');
        task.off('failed');
        task.off('pause');
        task.off('resume');
        await request.agent.remove(task.tid);
        this.deleteUploadTask(id);
      } catch (err) {
        Logger.info(TAG, `deleteTask fail, err= ${JSON.stringify(err)}`);
      }
    }
  }
}

export const requestUpload = new RequestUpload();