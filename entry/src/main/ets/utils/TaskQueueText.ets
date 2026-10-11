import Constant from '../model/Constant';
import { UserTask } from '../model/net/ApiTypes';

// 任务队列的状态键，由 native 统一成 v4 的叫法（见 UserTask）
export const TASK_STATUS_QUEUED: string = 'queued';
export const TASK_STATUS_PROCESSING: string = 'processing';
export const TASK_STATUS_SUSPENDING: string = 'suspending';
export const TASK_STATUS_ERROR: string = 'error';
export const TASK_STATUS_CANCELED: string = 'canceled';
export const TASK_STATUS_COMPLETED: string = 'completed';

/** 任务队列卡片和详情页共用的文案，保证两处说法一致 */
export class TaskQueueText {
  static kind(kind: string): string {
    switch (kind) {
      case 'compress':
        return '压缩';
      case 'extract':
        return '解压缩';
      case 'import':
        return '导入外部目录';
      case 'relocate':
        return '迁移存储策略';
      case 'transfer':
        return '文件中转';
      case 'recycle':
        return '文件回收';
      default:
        return '后台任务';
    }
  }

  static stage(stage: string): string {
    switch (stage) {
      case 'waiting':
        return '等待中';
      case 'preparing':
        return '准备中';
      case 'compressing':
        return '压缩中';
      case 'extracting':
        return '解压中';
      case 'downloading':
        return '下载中';
      case 'downloading_archive':
        return '获取压缩文件';
      case 'transferring':
        return '转存中';
      case 'indexing':
        return '索引中';
      case 'inserting':
        return '插入中';
      case 'importing':
        return '导入中';
      case 'committing':
        return '提交更改';
      default:
        return '';
    }
  }

  /** 处理中时直接写当前阶段，服务端没给阶段才写「处理中」 */
  static status(task: UserTask): string {
    switch (task.status) {
      case TASK_STATUS_QUEUED:
        return '排队中';
      case TASK_STATUS_PROCESSING: {
        const stage = TaskQueueText.stage(task.stage);
        return stage.length > 0 ? stage : '处理中';
      }
      case TASK_STATUS_SUSPENDING:
        return '已挂起';
      case TASK_STATUS_COMPLETED:
        return '已完成';
      case TASK_STATUS_ERROR:
        return '失败';
      case TASK_STATUS_CANCELED:
        return '已取消';
      default:
        return '未知';
    }
  }

  /** 卡片上的短源名：多项时补「等 N 项」 */
  static source(task: UserTask): string {
    return task.src_count > 1 ? `${task.src} 等 ${task.src_count} 项` : task.src;
  }

  /** 没有源 / 目标时（v3）的补充说明：中转任务写转了几个文件，失败的写停在哪一步 */
  static progress(task: UserTask): string {
    if (task.kind === 'transfer') {
      return `已转存 ${task.transferred} 个文件`;
    }
    const stage = TaskQueueText.stage(task.stage);
    if (task.status === TASK_STATUS_ERROR && stage.length > 0) {
      return `停在：${stage}`;
    }
    return '';
  }

  static duration(durationMs: number): string {
    const totalSeconds = Math.max(1, Math.round(durationMs / Constant.MILLISECONDS_PER_SECOND));
    const secondsPerHour = Constant.SECONDS_PER_MINUTE * Constant.MINUTES_PER_HOUR;
    const hours = Math.floor(totalSeconds / secondsPerHour);
    const minutes = Math.floor((totalSeconds % secondsPerHour) / Constant.SECONDS_PER_MINUTE);
    const seconds = totalSeconds % Constant.SECONDS_PER_MINUTE;
    if (hours > 0) {
      return `${hours} 小时 ${minutes} 分`;
    }
    if (minutes > 0) {
      return `${minutes} 分 ${seconds} 秒`;
    }
    return `${seconds} 秒`;
  }

  static failedObjects(task: UserTask): string {
    return `有 ${task.failed} 个对象处理失败，已跳过`;
  }

  static error(task: UserTask): string {
    return task.error.length > 0 ? task.error : '任务执行失败';
  }
}
