
import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import Constant from '../model/Constant';
import { FileModel, FileModelState } from '../model/FileModel';
import Logger from './Logger';

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

  uploadFileBackground(file: FileModel, context?: common.UIAbilityContext) {
    if (file) {
      Logger.info(TAG, 'upload ' + file.path);
      if (context) {
        this.context = context;
      }
      this.waitList.push(file)
    }
  }

  private async flushBackgroundTask() {
    const runningCount = await this.getRunningTaskCount();

    if (runningCount < Constant.TASK_MAX && this.waitList.length > 0) {
      let uploadList: FileModel[] = [];
      if (this.waitList.length <= Constant.TASK_MAX - runningCount) {
        uploadList = this.waitList;
        this.waitList = [];
      } else {
        uploadList = this.waitList.slice(0, Constant.TASK_MAX - runningCount);
        this.waitList = this.waitList.slice(Constant.TASK_MAX - runningCount, this.waitList.length);
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
            const taskInfo = await this.showTask(task.tid);
            Logger.info(TAG, `pause, reason = ${taskInfo?.reason ?? ''}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo?.faults ?? '')}`);
            isNetPause = taskInfo?.faults === 0;
            if (fileModel.callback) {
              if (isNetPause) {
                fileModel.callback(progress.processed, FileModelState.PAUSED);
              } else {
                fileModel.callback(progress.processed, FileModelState.STOPPED);
              }
            }
          })

          task.on('resume', async (progress: request.agent.Progress) => {
            const taskInfo = await this.showTask(task.tid);
            Logger.info(TAG, `resume, reason = ${taskInfo?.reason ?? ''}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo?.faults ?? '')}`);
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
            const taskInfo = await this.showTask(task.tid);
            Logger.info(TAG, `failed, reason = ${taskInfo?.reason ?? ''}, progress = ${progress.processed}, faults = ${JSON.stringify(taskInfo?.faults ?? '')}`);
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
    let task = this.getUploadTask(id)
    if (task) {
      try {
        let taskInfo = await this.showTask(task.tid);
        Logger.info(TAG, `task pause, taskInfo = ${JSON.stringify(taskInfo)}`);
        await task.pause();
      } catch (err) {
        Logger.error(TAG, `task pause failed, err = ${JSON.stringify(err)}`);
      }
    }
  }

  async resume(id: string) {
    let task = this.getUploadTask(id)
    if (task) {
      try {
        let taskInfo = await this.showTask(task.tid);
        Logger.info(TAG, `task resume, taskInfo = ${JSON.stringify(taskInfo)}`);
        await task.resume();
      } catch (err) {
        Logger.error(TAG, `task resume failed, err = ${JSON.stringify(err)}`);
      }
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

export const requestUpload = new RequestUpload();
