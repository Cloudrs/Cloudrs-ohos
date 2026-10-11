import Constant from '../model/Constant';
import { UserTask, UserTasks } from '../model/net/ApiTypes';
import { CloudApi } from '../model/net/CloudApi';
import { TabId } from '../model/TabData';
import { ArchiveBannerJob, ArchiveRules } from './ArchiveRules';
import { TASK_STATUS_CANCELED, TASK_STATUS_COMPLETED, TaskQueueText } from './TaskQueueText';
import { showToastTips, ToastType } from './ToastUtil';
import AppLogger from './AppLogger';

const TAG: string = 'ArchiveTaskTracker';
const RETIRED_KEYS_MAX: number = 20;

export interface ArchiveJob {
  /** 'compress' | 'extract'，和任务队列的 kind 一致 */
  kind: string;
  /** 浮条里显示的名字：压缩包名 */
  label: string;
  dstFolder: string;
  /** v4 任务 id；v3 为空，靠提交时间认领 */
  taskId: string;
  submittedAt: number;
  /** 发起提交时的账号作用域，结果只对这个账号有效 */
  scope: string;
}

interface TrackedJob {
  job: ArchiveJob;
  /** v3 认领到的任务键，避免两个提交认同一条 */
  claimedKey: string;
  /** 最近一次查到的服务端状态，还没查到为空串；浮条据此区分排队中 / 进行中 */
  status: string;
}

/** 已点提交、请求还没回来的任务：服务器慢时浮条先显示「正在提交」 */
interface PendingSubmit {
  token: number;
  kind: string;
  label: string;
}

/**
 * 压缩 / 解压提交后在后台盯着任务：每 3 秒拉一次任务队列，App 在后台时跳过；
 * 结束时发「目标文件夹有变化」信号并把结果写到浮条。状态全放 AppStorage，页面用 @StorageProp 读
 * （文件页是 V1 组件，读不到 @ObservedV2 单例的变化）。
 */
export class ArchiveTaskTracker {
  private static jobs: TrackedJob[] = [];
  private static submitting: PendingSubmit[] = [];
  private static nextToken: number = 1;
  // 已结束的 v3 任务认领过的键：容差窗口内再提交时不能又认到它
  private static retiredKeys: string[] = [];
  private static timerId: number = -1;
  private static hideTimerId: number = -1;
  private static polling: boolean = false;

  /** 点下提交、请求发出前调用：浮条马上显示「正在提交」。返回的凭据交给 submit / endSubmit */
  static beginSubmit(kind: string, label: string): number {
    const token = ArchiveTaskTracker.nextToken++;
    ArchiveTaskTracker.submitting.push({ token: token, kind: kind, label: label });
    // 新操作优先：上一条结果提示还在停留也立刻换掉
    ArchiveTaskTracker.cancelNotice();
    ArchiveTaskTracker.showProgress();
    return token;
  }

  /** 提交失败：撤掉「正在提交」（失败原因由调用方 toast） */
  static endSubmit(token: number): void {
    ArchiveTaskTracker.dropPending(token);
    ArchiveTaskTracker.showProgress();
  }

  static submit(job: ArchiveJob, token: number): void {
    ArchiveTaskTracker.dropPending(token);
    const active = ArchiveTaskTracker.activeScope();
    // 提交回调晚到时账号可能已经换了
    if (!ArchiveRules.sameScope(job.scope, active)) {
      AppLogger.info(TAG, `drop ${job.kind} ${job.label}: account changed`);
      ArchiveTaskTracker.showProgress();
      return;
    }
    if (ArchiveTaskTracker.jobs.length > 0 && !ArchiveRules.sameScope(ArchiveTaskTracker.jobs[0].job.scope, active)) {
      ArchiveTaskTracker.clear();
    }
    ArchiveTaskTracker.jobs.push({ job: job, claimedKey: '', status: '' });
    // 新提交优先：上一条结果提示还在停留也立刻换成「进行中」，不然看着像新任务瞬间就完成了
    ArchiveTaskTracker.cancelNotice();
    ArchiveTaskTracker.showProgress();
    if (ArchiveTaskTracker.timerId < 0) {
      ArchiveTaskTracker.timerId = setInterval(() => ArchiveTaskTracker.poll(), Constant.ARCHIVE_POLL_INTERVAL_MS);
    }
  }

  /** 换账号 / 退出登录：旧账号的任务一律不再跟 */
  static clear(): void {
    ArchiveTaskTracker.jobs = [];
    ArchiveTaskTracker.submitting = [];
    ArchiveTaskTracker.retiredKeys = [];
    ArchiveTaskTracker.stopTimer();
    ArchiveTaskTracker.cancelNotice();
    ArchiveTaskTracker.setBanner('hidden', '');
  }

  private static poll(): void {
    if (ArchiveTaskTracker.polling || !(AppStorage.get<boolean>(Constant.APP_IN_FOREGROUND) ?? true)) {
      return;
    }
    // 宽屏下文件页不常驻、退出登录时首页整个被替换，都收不到文件页的换账号回调，这里自己核对
    if (!ArchiveTaskTracker.ownedByActiveAccount()) {
      AppLogger.info(TAG, 'account changed, stop tracking');
      ArchiveTaskTracker.clear();
      return;
    }
    ArchiveTaskTracker.polling = true;
    const scope = ArchiveTaskTracker.activeScope();
    // 只拉最近一页：整表一次拉全要翻很多页，每 3 秒来一遍太重
    CloudApi.recentUserTasks({
      onSuccess: (data: UserTasks) => {
        ArchiveTaskTracker.polling = false;
        if (scope !== ArchiveTaskTracker.activeScope()) {
          return;
        }
        ArchiveTaskTracker.settle(data.tasks);
      },
      onFailure: (msg: string) => {
        ArchiveTaskTracker.polling = false;
        AppLogger.warn(TAG, 'poll task queue failed: ' + msg);
      }
    });
  }

  private static settle(tasks: UserTask[]): void {
    const now = Date.now();
    const remaining: TrackedJob[] = [];
    for (const tracked of ArchiveTaskTracker.jobs) {
      const task = ArchiveTaskTracker.locate(tracked, tasks);
      if (task && ArchiveRules.isTaskFinished(task.status)) {
        ArchiveTaskTracker.retire(tracked);
        ArchiveTaskTracker.finish(tracked.job, task);
        continue;
      }
      const age = now - tracked.job.submittedAt;
      const lost = !task && tracked.job.taskId.length === 0 && age > Constant.ARCHIVE_V3_MATCH_TIMEOUT_MS;
      if (lost || age > Constant.ARCHIVE_TRACK_TIMEOUT_MS) {
        AppLogger.info(TAG, `stop tracking ${tracked.job.kind} ${tracked.job.label} (lost=${lost})`);
        ArchiveTaskTracker.retire(tracked);
        ArchiveTaskTracker.notice('failed', '仍在进行，可在任务队列查看进度');
        continue;
      }
      if (task && task.status !== tracked.status) {
        AppLogger.info(TAG, `${tracked.job.kind} ${tracked.job.label} status ${tracked.status || '-'} -> ${task.status}`);
        tracked.status = task.status;
      } else if (!task) {
        AppLogger.info(TAG, `${tracked.job.kind} ${tracked.job.label} not in recent tasks (${tasks.length})`);
      }
      remaining.push(tracked);
    }
    ArchiveTaskTracker.jobs = remaining;
    if (remaining.length === 0) {
      ArchiveTaskTracker.stopTimer();
    }
    ArchiveTaskTracker.showProgress();
  }

  private static locate(tracked: TrackedJob, tasks: UserTask[]): UserTask | undefined {
    if (tracked.job.taskId.length > 0) {
      return ArchiveRules.findV4Task(tasks, tracked.job.taskId);
    }
    if (tracked.claimedKey.length > 0) {
      return tasks.find((t: UserTask) => ArchiveRules.v3TaskKey(t) === tracked.claimedKey);
    }
    const claimed = ArchiveTaskTracker.jobs
      .filter((j: TrackedJob) => j.claimedKey.length > 0)
      .map((j: TrackedJob) => j.claimedKey)
      .concat(ArchiveTaskTracker.retiredKeys);
    const found = ArchiveRules.matchV3Task(tasks, tracked.job.kind, tracked.job.submittedAt, claimed);
    if (found) {
      tracked.claimedKey = ArchiveRules.v3TaskKey(found);
    }
    return found;
  }

  private static retire(tracked: TrackedJob): void {
    if (tracked.claimedKey.length === 0) {
      return;
    }
    ArchiveTaskTracker.retiredKeys.push(tracked.claimedKey);
    // 只需挡住容差窗口内的几条，留最近的就够
    if (ArchiveTaskTracker.retiredKeys.length > RETIRED_KEYS_MAX) {
      ArchiveTaskTracker.retiredKeys.shift();
    }
  }

  private static activeScope(): string {
    return AppStorage.get<string>(Constant.ACTIVE_ACCOUNT_SCOPE) ?? '';
  }

  private static ownedByActiveAccount(): boolean {
    const active = ArchiveTaskTracker.activeScope();
    return ArchiveTaskTracker.jobs.every((t: TrackedJob) => ArchiveRules.sameScope(t.job.scope, active));
  }

  private static dropPending(token: number): void {
    ArchiveTaskTracker.submitting = ArchiveTaskTracker.submitting.filter((p: PendingSubmit) => p.token !== token);
  }

  private static finish(job: ArchiveJob, task: UserTask): void {
    const verb = ArchiveRules.verb(job.kind);
    AppLogger.info(TAG, `${job.kind} ${job.label} finished: ${task.status}`);
    if (task.status === TASK_STATUS_COMPLETED) {
      AppStorage.setOrCreate(Constant.ARCHIVE_REFRESH_KIND, job.kind);
      AppStorage.setOrCreate(Constant.ARCHIVE_REFRESH_PATH, job.dstFolder);
      const tick = AppStorage.get<number>(Constant.ARCHIVE_REFRESH_TICK) ?? 0;
      AppStorage.setOrCreate(Constant.ARCHIVE_REFRESH_TICK, tick + 1);
      ArchiveTaskTracker.notice('done', `${verb}完成 · ${job.dstFolder}`);
    } else if (task.status === TASK_STATUS_CANCELED) {
      ArchiveTaskTracker.notice('failed', `${verb}已取消`);
    } else {
      ArchiveTaskTracker.notice('failed', `${verb}失败：${TaskQueueText.error(task)}`);
    }
  }

  /** 进行中的浮条：提交中 / 排队中 / 正在…；什么都没有就收起 */
  private static showProgress(): void {
    const pending = ArchiveTaskTracker.submitting.map((p: PendingSubmit): ArchiveBannerJob => {
      return { kind: p.kind, label: p.label, status: '' };
    });
    const tracked = ArchiveTaskTracker.jobs.map((t: TrackedJob): ArchiveBannerJob => {
      return { kind: t.job.kind, label: t.job.label, status: t.status };
    });
    const state = ArchiveRules.bannerFor(pending, tracked);
    ArchiveTaskTracker.setBanner(state.mode, state.text);
  }

  /**
   * 结果停留几秒后收起；期间还有任务就回到进行中。
   * 浮条只在文件页，人在别的 Tab 就改用系统提示，免得结果没人看见
   */
  private static notice(mode: string, text: string): void {
    ArchiveTaskTracker.cancelNotice();
    if ((AppStorage.get<number>(Constant.HOME_TAB_INDEX) ?? TabId.FILES) !== TabId.FILES) {
      showToastTips(text, mode === 'failed' ? ToastType.Error : ToastType.Info);
    }
    ArchiveTaskTracker.setBanner(mode, text);
    const duration = mode === 'done' ? Constant.ARCHIVE_BANNER_DONE_MS : Constant.ARCHIVE_BANNER_NOTICE_MS;
    ArchiveTaskTracker.hideTimerId = setTimeout(() => {
      ArchiveTaskTracker.hideTimerId = -1;
      ArchiveTaskTracker.showProgress();
    }, duration);
  }

  private static setBanner(mode: string, text: string): void {
    // 结果提示还在停留时，不让轮询 / 提交回调把它刷回进行中或收起
    if (mode !== 'done' && mode !== 'failed' && ArchiveTaskTracker.hideTimerId >= 0) {
      return;
    }
    AppStorage.setOrCreate(Constant.ARCHIVE_BANNER_TEXT, text);
    AppStorage.setOrCreate(Constant.ARCHIVE_BANNER_MODE, mode);
  }

  private static cancelNotice(): void {
    if (ArchiveTaskTracker.hideTimerId >= 0) {
      clearTimeout(ArchiveTaskTracker.hideTimerId);
      ArchiveTaskTracker.hideTimerId = -1;
    }
  }

  private static stopTimer(): void {
    if (ArchiveTaskTracker.timerId >= 0) {
      clearInterval(ArchiveTaskTracker.timerId);
      ArchiveTaskTracker.timerId = -1;
    }
  }
}
