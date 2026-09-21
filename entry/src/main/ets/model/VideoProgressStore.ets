import Constant from './Constant';
import UserPreferences from './UserPreferences';
import { ActiveAccount } from '../utils/ActiveAccount';
import AppLogger from '../utils/AppLogger';

const TAG: string = 'VideoProgress';

/**
 * 一条本地续播记录。
 *
 * 整张表以 JSON 数组存在 Preferences 的单个 key 下：条数上限 200、只按 fileId 精确取用，
 * 没有任何查询需求，为它单开一张 SQLite 表是杀鸡用牛刀。字段名压到一个字母是因为
 * 每条记录的键名都要跟着值一起进磁盘，短名比值本身省得还多。
 */
export class VideoProgressEntry {
  /** 账号作用域 + fileId。不同站点的 fileId 会撞，不带 scope 会串播 */
  k: string = '';
  /** 上次播放位置(秒) */
  t: number = 0;
  /** 视频总时长(秒)，判断"是否接近看完"以及展示用 */
  d: number = 0;
  /** 最后播放时间戳(ms)，LRU 裁剪依据 */
  at: number = 0;
}

export class VideoProgressStore {
  /**
   * 读取某个文件的续播记录，没有则返回 undefined。
   */
  static load(fileId: string): VideoProgressEntry | undefined {
    const key = VideoProgressStore.keyOf(fileId);
    if (key.length === 0) {
      return undefined;
    }
    const list = VideoProgressStore.readAll();
    for (const entry of list) {
      if (entry.k === key) {
        AppLogger.info(TAG, `load hit: t=${entry.t} d=${entry.d}`);
        return entry;
      }
    }
    return undefined;
  }

  /**
   * 写入播放进度。"该不该记"的规则全部收在这里，调用方无需判断：
   * 太短的视频、刚开头、已接近看完，一律落到删除记录而不是写入。
   *
   * @param critical 为 true 时同步落盘（离开页面场景，进程随时可能被回收）
   */
  static save(fileId: string, currentTime: number, duration: number, critical: boolean = false): void {
    const key = VideoProgressStore.keyOf(fileId);
    if (key.length === 0 || !Number.isFinite(currentTime) || !Number.isFinite(duration)) {
      return;
    }
    // 可记录区间 [edge, duration - edge]：区间外要么是"才刚开头"，要么是"基本看完"，
    // 两种情况下次都该从头播。10 秒以内的视频算出来是空区间，自然一条也不会记
    const edge = Math.max(duration * Constant.VIDEO_PROGRESS_EDGE_RATIO,
      Constant.VIDEO_PROGRESS_EDGE_MIN_SECONDS);
    if (currentTime < edge || currentTime > duration - edge) {
      AppLogger.info(TAG,
        `skip: t=${Math.floor(currentTime)} d=${Math.floor(duration)} edge=${Math.floor(edge)}`);
      VideoProgressStore.remove(fileId, critical);
      return;
    }
    AppLogger.info(TAG, `save: t=${Math.floor(currentTime)} d=${Math.floor(duration)} critical=${critical}`);

    const list = VideoProgressStore.readAll();
    const kept: VideoProgressEntry[] = list.filter((entry: VideoProgressEntry) => entry.k !== key);
    const record = new VideoProgressEntry();
    record.k = key;
    record.t = Math.floor(currentTime);
    record.d = Math.floor(duration);
    record.at = new Date().getTime();
    kept.push(record);

    VideoProgressStore.writeAll(VideoProgressStore.trim(kept), critical);
  }

  /**
   * 删除某个文件的续播记录。表里本来就没有时不落盘，避免无谓的磁盘 I/O。
   */
  static remove(fileId: string, critical: boolean = false): void {
    const key = VideoProgressStore.keyOf(fileId);
    if (key.length === 0) {
      return;
    }
    const list = VideoProgressStore.readAll();
    const kept: VideoProgressEntry[] = list.filter((entry: VideoProgressEntry) => entry.k !== key);
    if (kept.length === list.length) {
      return;
    }
    VideoProgressStore.writeAll(kept, critical);
  }

  /** 站点 + 用户名 + fileId 才唯一。未登录（scope 为空）时不记录 */
  private static keyOf(fileId: string): string {
    const scope = ActiveAccount.current();
    if (scope.length === 0 || fileId.length === 0) {
      return '';
    }
    return `${scope}|${fileId}`;
  }

  private static readAll(): VideoProgressEntry[] {
    const raw = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.VIDEO_PROGRESS_KEY, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as VideoProgressEntry[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      // 手改过或旧版本残留的脏数据在这里挡掉，别让 NaN 传到 seek 上
      return parsed.filter((entry: VideoProgressEntry) =>
        entry !== null && entry !== undefined &&
        typeof entry.k === 'string' && entry.k.length > 0 &&
        Number.isFinite(entry.t) && Number.isFinite(entry.d));
    } catch (err) {
      AppLogger.warn(TAG, `parse failed, drop table: ${(err as Error)?.message ?? err}`);
      return [];
    }
  }

  private static writeAll(list: VideoProgressEntry[], critical: boolean): void {
    const json = JSON.stringify(list);
    if (critical) {
      UserPreferences.putCriticalSync(Constant.USER_PREFERENCES, Constant.VIDEO_PROGRESS_KEY, json);
    } else {
      UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.VIDEO_PROGRESS_KEY, json);
    }
  }

  /** 超出上限时按最后播放时间保留最近的若干条 */
  private static trim(list: VideoProgressEntry[]): VideoProgressEntry[] {
    if (list.length <= Constant.VIDEO_PROGRESS_MAX_RECORDS) {
      return list;
    }
    const sorted = list.sort((left: VideoProgressEntry, right: VideoProgressEntry) => right.at - left.at);
    return sorted.slice(0, Constant.VIDEO_PROGRESS_MAX_RECORDS);
  }
}
