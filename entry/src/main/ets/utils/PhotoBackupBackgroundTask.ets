import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import AppLogger from './AppLogger';

const TAG: string = 'PhotoBackupBackgroundTask';
const INVALID_TASK_ID: number = -1;
const WANT_AGENT_REQUEST_CODE: number = 21001;

export enum PhotoBackupBackgroundInterruptReason {
  SYSTEM_CANCELED = 'system_canceled',
  SYSTEM_SUSPENDED = 'system_suspended'
}

export type PhotoBackupBackgroundInterruptListener =
  (reason: PhotoBackupBackgroundInterruptReason) => void;

/**
 * 相册备份的数据传输长时任务。
 *
 * 长时任务只负责让已经启动的上传队列在退后台后继续运行，不负责唤醒应用扫描新照片。
 * 系统取消/挂起任务时通知上传队列在下一个分片边界暂停，保留 session 供下次续传。
 */
class PhotoBackupBackgroundTaskImpl {
  private active: boolean = false;
  private continuousTaskId: number = INVALID_TASK_ID;
  private context: common.UIAbilityContext | undefined = undefined;
  private starting: Promise<boolean> | undefined = undefined;
  private interruptListener: PhotoBackupBackgroundInterruptListener | undefined = undefined;
  private cancelListenerRegistered: boolean = false;
  private suspendListenerRegistered: boolean = false;
  private interruptDelivered: boolean = false;
  private readonly cancelListener =
    (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      if (!this.matchesTask(info.id)) {
        return;
      }
      AppLogger.warn(TAG, `data transfer task canceled by system, reason=${info.reason}`);
      this.active = false;
      this.continuousTaskId = INVALID_TASK_ID;
      this.context = undefined;
      this.deliverInterrupt(PhotoBackupBackgroundInterruptReason.SYSTEM_CANCELED);
    };
  private readonly suspendListener =
    (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
      if (!info.suspendState || !this.matchesTask(info.continuousTaskId)) {
        return;
      }
      AppLogger.warn(TAG, `data transfer task suspended by system, reason=${info.suspendReason}`);
      this.deliverInterrupt(PhotoBackupBackgroundInterruptReason.SYSTEM_SUSPENDED);
    };

  async start(context: common.UIAbilityContext,
    listener: PhotoBackupBackgroundInterruptListener): Promise<boolean> {
    this.interruptListener = listener;
    if (this.active) {
      return true;
    }
    if (this.starting) {
      return await this.starting;
    }
    this.starting = this.startInternal(context);
    try {
      return await this.starting;
    } finally {
      this.starting = undefined;
    }
  }

  async stop(): Promise<void> {
    if (this.starting) {
      try {
        await this.starting;
      } catch (_) {
      }
    }
    const context = this.context;
    const taskId = this.continuousTaskId;
    this.active = false;
    this.continuousTaskId = INVALID_TASK_ID;
    this.context = undefined;
    this.interruptListener = undefined;
    this.interruptDelivered = false;
    if (!context) {
      return;
    }
    try {
      if (taskId >= 0) {
        await backgroundTaskManager.stopBackgroundRunning(context, taskId);
      } else {
        await backgroundTaskManager.stopBackgroundRunning(context);
      }
      AppLogger.info(TAG, `data transfer task stopped, id=${taskId}`);
    } catch (err) {
      AppLogger.warn(TAG, `stop data transfer task failed: ${(err as Error)?.message ?? err}`);
    }
  }

  isActive(): boolean {
    return this.active;
  }

  private async startInternal(context: common.UIAbilityContext): Promise<boolean> {
    try {
      this.registerListeners();
      const clickAgent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: context.applicationInfo.name,
          abilityName: context.abilityInfo.name,
          moduleName: context.abilityInfo.moduleName
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: WANT_AGENT_REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      // API 23 的 ContinuousTaskRequest 构造器在当前真机上未初始化 native continuousRequestInfo，
      // 会以 9800005 拒绝；string[] 重载同样支持 UIAbility 且会返回 continuousTaskId。
      const notification =
        await backgroundTaskManager.startBackgroundRunning(context, ['dataTransfer'], clickAgent);
      this.context = context;
      this.continuousTaskId = notification.continuousTaskId ?? INVALID_TASK_ID;
      this.active = true;
      this.interruptDelivered = false;
      AppLogger.info(TAG, `data transfer task started, id=${this.continuousTaskId}`);
      return true;
    } catch (err) {
      this.active = false;
      this.continuousTaskId = INVALID_TASK_ID;
      this.context = undefined;
      AppLogger.error(TAG, `start data transfer task failed: ${(err as Error)?.message ?? err}`);
      return false;
    }
  }

  private registerListeners(): void {
    if (!this.cancelListenerRegistered) {
      try {
        backgroundTaskManager.on('continuousTaskCancel', this.cancelListener);
        this.cancelListenerRegistered = true;
      } catch (err) {
        AppLogger.warn(TAG, `register cancel listener failed: ${(err as Error)?.message ?? err}`);
      }
    }
    if (!this.suspendListenerRegistered) {
      try {
        backgroundTaskManager.on('continuousTaskSuspend', this.suspendListener);
        this.suspendListenerRegistered = true;
      } catch (err) {
        AppLogger.warn(TAG, `register suspend listener failed: ${(err as Error)?.message ?? err}`);
      }
    }
  }

  private matchesTask(id: number): boolean {
    return this.active && (this.continuousTaskId < 0 || this.continuousTaskId === id);
  }

  private deliverInterrupt(reason: PhotoBackupBackgroundInterruptReason): void {
    if (this.interruptDelivered) {
      return;
    }
    this.interruptDelivered = true;
    this.interruptListener?.(reason);
  }
}

const PhotoBackupBackgroundTask = new PhotoBackupBackgroundTaskImpl();
export default PhotoBackupBackgroundTask;
