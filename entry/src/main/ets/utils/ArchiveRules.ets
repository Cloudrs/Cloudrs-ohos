import { UserTask } from '../model/net/ApiTypes';
import {
  TASK_STATUS_CANCELED, TASK_STATUS_COMPLETED, TASK_STATUS_ERROR, TASK_STATUS_QUEUED, TASK_STATUS_SUSPENDING
} from './TaskQueueText';

export interface ZipEncodingOption {
  label: string;
  hint: string;
  /** 服务端认的编码键，空串表示交给服务端（UTF-8） */
  value: string;
}

export interface ArchiveSourceName {
  name: string;
  isDir: boolean;
}

/** 浮条要描述的一个任务：kind 同任务队列；status 为服务端状态，还没查到为空串 */
export interface ArchiveBannerJob {
  kind: string;
  label: string;
  status: string;
}

export interface ArchiveBannerState {
  /** hidden / submitting / queued / running（结果提示 done / failed 由跟踪器另行设置） */
  mode: string;
  text: string;
}

/**
 * v3 任务没有 id，只认提交之后新出现的任务；服务器和手机的时钟可能差几秒，放宽这么多。
 * 不能放太宽：连续压缩时会认领到上一个已完成的任务，还没压完就报「完成」
 */
export const ARCHIVE_V3_MATCH_SKEW_MS: number = 5000;

const MAX_NAME_LENGTH: number = 255;
const ZIP_SUFFIX: string = '.zip';
const DEFAULT_ARCHIVE_NAME: string = 'archive';
// v4 官方前端的可解压扩展名（取最后一个扩展名，小写比较）
const V4_EXTRACT_EXTS: string[] = ['zip', 'gz', 'xz', 'tar', 'rar', '7z', 'bz2'];
// v3 服务端的后缀白名单（区分大小写，不含 7z）
const V3_EXTRACT_SUFFIXES: string[] = ['.zip', '.gz', '.xz', '.tar', '.rar'];
// 服务端只对这两种格式用密码，zip 的密码会被忽略
const V4_PASSWORD_EXTS: string[] = ['rar', '7z'];

/** 压缩 / 解压的纯规则：入口显隐、默认名、校验、错误文案、任务认领。不碰 UI 和网络，方便单测 */
export class ArchiveRules {
  static readonly ZIP_ENCODINGS: ZipEncodingOption[] = [
    { label: '自动', hint: 'UTF-8', value: '' },
    { label: 'GBK', hint: '简体中文 Windows', value: 'gbk' },
    { label: 'GB18030', hint: '简体中文', value: 'gb18030' },
    { label: 'Big5', hint: '繁体中文', value: 'big5' },
    { label: 'Shift_JIS', hint: '日文', value: 'shiftjis' },
    { label: 'EUC-KR', hint: '韩文', value: 'euckr' }
  ];

  /** 最后一个扩展名（小写，不含点）；没有扩展名或以点开头的隐藏文件名返回空串 */
  static lastExt(name: string): string {
    const dot = name.lastIndexOf('.');
    if (dot <= 0 || dot === name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  static canExtract(name: string, isV4: boolean): boolean {
    if (isV4) {
      return V4_EXTRACT_EXTS.includes(ArchiveRules.lastExt(name));
    }
    return V3_EXTRACT_SUFFIXES.some((suffix: string) => name.length > suffix.length && name.endsWith(suffix));
  }

  /** zip 才有文件名编码问题 */
  static needsEncoding(name: string, isV4: boolean): boolean {
    return ArchiveRules.canExtract(name, isV4) && ArchiveRules.lastExt(name) === 'zip';
  }

  static acceptsPassword(name: string, isV4: boolean): boolean {
    return isV4 && V4_PASSWORD_EXTS.includes(ArchiveRules.lastExt(name));
  }

  /** 单项取它的名字（文件去掉扩展名），多项取当前文件夹名，根目录用 archive */
  static defaultArchiveName(selected: ArchiveSourceName[], currentPath: string): string {
    let base = '';
    if (selected.length === 1) {
      const item = selected[0];
      const dot = item.name.lastIndexOf('.');
      base = (!item.isDir && dot > 0) ? item.name.substring(0, dot) : item.name;
    } else {
      const trimmed = currentPath.endsWith('/') ? currentPath.substring(0, currentPath.length - 1) : currentPath;
      base = trimmed.substring(trimmed.lastIndexOf('/') + 1);
    }
    return `${base.length > 0 ? base : DEFAULT_ARCHIVE_NAME}${ZIP_SUFFIX}`;
  }

  /** 空串表示合法 */
  static archiveNameError(name: string): string {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return '请输入文件名';
    }
    if (trimmed.includes('/') || trimmed.includes('\\')) {
      return '文件名不能包含 / 或 \\';
    }
    if (trimmed.length > MAX_NAME_LENGTH) {
      return `文件名最多 ${MAX_NAME_LENGTH} 个字符`;
    }
    return '';
  }

  /** 两个版本的 ObjectInfo.path 都是父目录，全路径 = 父目录 + / + 名字 */
  static joinPath(folder: string, name: string): string {
    const base = folder.endsWith('/') ? folder.substring(0, folder.length - 1) : folder;
    return `${base}/${name}`;
  }

  /**
   * 浮条进行中的样子：提交请求还没回来是「正在提交」（服务器慢时也有反馈），
   * 服务器已接收但没开始处理是「排队中」，其余是「正在压缩 / 解压」；多个任务只报数量
   */
  static bannerFor(submitting: ArchiveBannerJob[], tracked: ArchiveBannerJob[]): ArchiveBannerState {
    const total = submitting.length + tracked.length;
    if (total === 0) {
      return { mode: 'hidden', text: '' };
    }
    if (total > 1) {
      return { mode: 'running', text: `${total} 个任务进行中` };
    }
    if (submitting.length === 1) {
      const job = submitting[0];
      return { mode: 'submitting', text: `正在提交${ArchiveRules.verb(job.kind)} ${job.label}…` };
    }
    const job = tracked[0];
    if (job.status === TASK_STATUS_QUEUED) {
      return { mode: 'queued', text: `排队中 · ${ArchiveRules.verb(job.kind)} ${job.label}` };
    }
    // v4 任务开始处理前会挂起等待一段时间，用户看来同样是「还没轮到」
    if (job.status === TASK_STATUS_SUSPENDING) {
      return { mode: 'queued', text: `等待中 · ${ArchiveRules.verb(job.kind)} ${job.label}` };
    }
    return { mode: 'running', text: `正在${ArchiveRules.verb(job.kind)} ${job.label}` };
  }

  static verb(kind: string): string {
    return kind === 'compress' ? '压缩' : '解压';
  }

  /** 任务 / 结论只属于提交它的账号；退出登录（空作用域）一律不算 */
  static sameScope(ownerScope: string, activeScope: string): boolean {
    return ownerScope.length > 0 && ownerScope === activeScope;
  }

  /**
   * 任务完成后当前文件夹要不要刷新：压缩只多出一个文件，只刷目标文件夹；
   * 解压可能并进已有的子文件夹，停在目标的子孙文件夹里也刷
   */
  static shouldRefreshFolder(kind: string, target: string, current: string): boolean {
    const dst = ArchiveRules.normalizeFolder(target);
    const here = ArchiveRules.normalizeFolder(current);
    if (here === dst) {
      return true;
    }
    return kind === 'extract' && here.startsWith(dst === '/' ? '/' : `${dst}/`);
  }

  private static normalizeFolder(path: string): string {
    if (path.length === 0 || path === '/') {
      return '/';
    }
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  static isNotAllowed(msg: string): boolean {
    return (msg ?? '').includes('40007');
  }

  static errorText(msg: string): string {
    const raw = msg ?? '';
    if (ArchiveRules.isNotAllowed(raw)) {
      return '当前账号没有压缩权限';
    }
    if (raw.includes('40049')) {
      return '文件超过用户组允许的大小';
    }
    if (raw.includes('40051')) {
      return '空间不足';
    }
    if (raw.includes('40056')) {
      return '不支持该格式的压缩包';
    }
    if (raw.includes('40052')) {
      return '文件名不合法';
    }
    if (raw.toLowerCase().includes('already exist')) {
      return '已存在同名文件';
    }
    // 网络类错误在 CloudreveNative.wrap 里已经翻译过，这里原样返回
    return raw;
  }

  static isTaskFinished(status: string): boolean {
    return status === TASK_STATUS_COMPLETED || status === TASK_STATUS_ERROR || status === TASK_STATUS_CANCELED;
  }

  static findV4Task(tasks: UserTask[], id: string): UserTask | undefined {
    return tasks.find((t: UserTask) => t.id === id);
  }

  static v3TaskKey(task: UserTask): string {
    return `${task.kind}|${task.create_date}`;
  }

  /** v3：提交之后新出现的同类任务里最早的那条，跳过已经被别的提交认领的 */
  static matchV3Task(tasks: UserTask[], kind: string, submittedAtMs: number, claimed: string[]): UserTask | undefined {
    const threshold = submittedAtMs - ARCHIVE_V3_MATCH_SKEW_MS;
    let best: UserTask | undefined = undefined;
    let bestTime = Number.MAX_VALUE;
    for (const t of tasks) {
      const created = Date.parse(t.create_date);
      if (t.kind !== kind || Number.isNaN(created) || created < threshold ||
        claimed.includes(ArchiveRules.v3TaskKey(t))) {
        continue;
      }
      if (created < bestTime) {
        best = t;
        bestTime = created;
      }
    }
    return best;
  }
}
