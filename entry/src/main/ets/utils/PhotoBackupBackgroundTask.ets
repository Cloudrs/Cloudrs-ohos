import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import AppLogger from './AppLogger';

const TAG: string = 'PhotoBackupBackgroundTask';
const INVALID_TASK_ID: number = -1;
const WANT_AGENT_REQUEST_CODE: number = 21001;
// 系统会移除超过 10 分钟未更新的长时任务通知；留出足够余量，避免锁屏时因调度抖动越过阈值。
const NOTIFICATION_REFRESH_INTERVAL_MS: number = 4 * 60 * 1000;

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
  private notificationRefreshTimer: number = -1;
  private lastNotificationRefreshAt: number = 0;
  private notificationRefreshInFlight: boolean = false;
  private readonly cancelListener =
    (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      if (!this.matchesTask(info.id)) {
        return;
      }
      AppLogger.warn(TAG, `data transfer task canceled by system, reason=${info.reason}`);
      this.stopNotificationRefresh();
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
    this.stopNotificationRefresh();
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

  /**
   * 上传进度持续变化时兜底刷新通知。正常情况下定时器负责刷新；锁屏调度延迟时，
   * native 上传进度回调仍可在跨过刷新间隔后触发这里，避免通知超过系统 10 分钟阈值。
   */
  notifyTransferProgress(): void {
    this.refreshNotificationIfDue();
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
      this.startNotificationRefresh();
      this.lastNotificationRefreshAt = new Date().getTime();
      AppLogger.info(TAG, `data transfer task started, id=${this.continuousTaskId}`);
      return true;
    } catch (err) {
      this.stopNotificationRefresh();
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

  private startNotificationRefresh(): void {
    this.stopNotificationRefresh();
    this.notificationRefreshTimer = setInterval(() => {
      this.refreshNotificationIfDue();
    }, NOTIFICATION_REFRESH_INTERVAL_MS);
  }

  private stopNotificationRefresh(): void {
    if (this.notificationRefreshTimer >= 0) {
      clearInterval(this.notificationRefreshTimer);
      this.notificationRefreshTimer = -1;
    }
    this.lastNotificationRefreshAt = 0;
    this.notificationRefreshInFlight = false;
  }

  private refreshNotificationIfDue(): void {
    if (!this.active || !this.context || this.notificationRefreshInFlight) {
      return;
    }
    const now = new Date().getTime();
    if (now - this.lastNotificationRefreshAt < NOTIFICATION_REFRESH_INTERVAL_MS) {
      return;
    }
    // 先记录尝试时间，避免高频进度回调在接口失败时形成请求风暴；下一周期会继续重试。
    this.lastNotificationRefreshAt = now;
    this.refreshNotification();
  }

  private async refreshNotification(): Promise<void> {
    const context = this.context;
    if (!context || !this.active) {
      return;
    }
    this.notificationRefreshInFlight = true;
    try {
      const notification = await backgroundTaskManager.updateBackgroundRunning(context, ['dataTransfer']);
      // 当前 API 23 真机的字符串重载更新成功时可能返回 -1；保留 start 阶段取得的有效任务 ID。
      if (notification.continuousTaskId !== undefined && notification.continuousTaskId >= 0) {
        this.continuousTaskId = notification.continuousTaskId;
      }
      AppLogger.info(TAG, `data transfer notification refreshed, id=${this.continuousTaskId}`);
    } catch (err) {
      AppLogger.warn(TAG, `refresh data transfer notification failed: ${(err as Error)?.message ?? err}`);
    } finally {
      this.notificationRefreshInFlight = false;
    }
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
