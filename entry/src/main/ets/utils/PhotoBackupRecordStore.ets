import fs from '@ohos.file.fs';
import Constant from '../model/Constant';
import UserPreferences from '../model/UserPreferences';
import { PhotoBackupItemData } from '../model/PhotoBackupModel';
import AppLogger from './AppLogger';

const TAG: string = 'PhotoBackupRecordStore';
const DIR_NAME: string = 'photo_backup';
const ITEMS_FILE: string = 'items.json';
const ITEMS_JOURNAL: string = 'items.log';
const DONE_IDS_FILE: string = 'done_ids.json';
const DONE_IDS_JOURNAL: string = 'done_ids.log';
const TMP_SUFFIX: string = '.tmp';

// journal 攒到这个条数就重写快照。取 max(绝对下限, 总数/2)：
// 小库不会因为几十条改动就重写整份，大库也不会让 journal 无限长到拖慢启动加载。
const COMPACT_MIN_RECORDS: number = 2000;

interface ItemJournalEntry {
  __del?: string
  data?: PhotoBackupItemData
}

interface DoneIdJournalEntry {
  a?: string
  d?: string
}

/**
 * 相册备份大块记录（照片清单 + 已备份标记）的落盘层。
 *
 * 为什么不放 Preferences：Preferences 的 flush/flushSync 会重写整个实例文件。
 * 真机上 photoBackupItems 2.5MB + photoBackupDoneIds 0.6MB 把 UserPreference 撑到 4.4MB，
 * 而备份中 PhotoBackupSessionStore 每张照片要 putCriticalSync（flushSync）三次，
 * 等于每秒好几次在 UI 线程同步重写 4.4MB，全 App 的滚动都会跟着掉帧。
 *
 * 为什么还要 journal：拆成独立文件后写入不再阻塞 UI 线程，但"每次都全量序列化"
 * 的开销和照片数成正比——1~2 万张时一次 stringify 就是 5~10MB 字符串加同样规模的
 * 临时对象，全砸在 UI 线程和 ArkTS GC 上。备份中真正变化的只有那么几条，
 * 所以改成"快照 + 增量日志"：平时只追加变更行（每条约 250 字节），
 * 日志攒够了再重写一次快照。
 *
 * 崩溃安全：快照走 tmp + rename 原子落位；journal 是纯追加，最后一行可能因断电写半截，
 * 加载时按行解析、跳过解析失败的行即可。任何遗漏的脏标记都会在下次快照重写时自愈。
 */
class PhotoBackupRecordStoreImpl {
  private baseDir: string = '';
  private writeChain: Promise<void> = Promise.resolve();
  private flushScheduled: boolean = false;

  // 待写快照（设了就取代同一数据流上所有待写的增量）
  private pendingItemsSnapshot: string | undefined = undefined;
  private pendingDoneIdsSnapshot: string | undefined = undefined;
  // 待追加的 journal 文本
  private pendingItemsJournal: string = '';
  private pendingDoneIdsJournal: string = '';
  // 已落盘的 journal 条数，用来决定何时重写快照
  private itemsJournalCount: number = 0;
  private doneIdsJournalCount: number = 0;
  private itemsSnapshotCount: number = 0;
  private doneIdsSnapshotCount: number = 0;

  /** 必须在首次读写前调用；重复调用幂等。用 App 级目录，不随 HAP 卸载丢失。 */
  init(context: Context): void {
    if (this.baseDir.length > 0) {
      return;
    }
    try {
      const dir = `${context.getApplicationContext().filesDir}/${DIR_NAME}`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      this.baseDir = dir;
      this.migrateFromPreferences();
    } catch (err) {
      AppLogger.error(TAG, `init failed: ${(err as Error)?.message ?? err}`);
    }
  }

  isReady(): boolean {
    return this.baseDir.length > 0;
  }

  // ---- 读取 ----

  /** 快照 + journal 回放。启动时读一次，调用方已推迟到首帧之后。 */
  readItems(): PhotoBackupItemData[] {
    const snapshot = this.parseArray<PhotoBackupItemData>(this.readFile(ITEMS_FILE));
    this.itemsSnapshotCount = snapshot.length;
    const lines = this.readJournalLines(ITEMS_JOURNAL);
    this.itemsJournalCount = lines.length;
    if (lines.length === 0) {
      return snapshot;
    }
    // Map 保持插入顺序：更新已有 id 不改变原位置，新 id 追加到末尾
    const byId = new Map<string, PhotoBackupItemData>();
    snapshot.forEach((data: PhotoBackupItemData) => {
      if (data.id) {
        byId.set(data.id, data);
      }
    });
    lines.forEach((line: string) => {
      try {
        const entry = JSON.parse(line) as ItemJournalEntry;
        if (entry.__del !== undefined) {
          byId.delete(entry.__del);
        } else if (entry.data && entry.data.id) {
          byId.set(entry.data.id, entry.data);
        }
      } catch (_) {
        // 断电可能留下半截的最后一行，跳过即可
      }
    });
    AppLogger.info(TAG, `loaded ${byId.size} items (snapshot ${snapshot.length} + journal ${lines.length})`);
    return Array.from(byId.values());
  }

  readDoneIds(): string[] {
    const snapshot = this.parseArray<string>(this.readFile(DONE_IDS_FILE));
    this.doneIdsSnapshotCount = snapshot.length;
    const lines = this.readJournalLines(DONE_IDS_JOURNAL);
    this.doneIdsJournalCount = lines.length;
    if (lines.length === 0) {
      return snapshot;
    }
    const keys = new Set<string>(snapshot);
    lines.forEach((line: string) => {
      try {
        const entry = JSON.parse(line) as DoneIdJournalEntry;
        if (entry.a !== undefined) {
          keys.add(entry.a);
        } else if (entry.d !== undefined) {
          keys.delete(entry.d);
        }
      } catch (_) {
      }
    });
    AppLogger.info(TAG, `loaded ${keys.size} done ids (snapshot ${snapshot.length} + journal ${lines.length})`);
    return Array.from(keys);
  }

  // ---- 写入 ----

  /** 照片集合本身变了（扫描/合并/删除）时用，重写快照并清空 journal。 */
  writeItemsSnapshot(all: PhotoBackupItemData[]): void {
    this.pendingItemsSnapshot = JSON.stringify(all);
    this.pendingItemsJournal = '';
    this.itemsSnapshotCount = all.length;
    // 立刻归零而不是等异步落盘：否则快照还在写的这段时间里 needsItemsCompaction()
    // 仍然为真，会连着排一串多余的全量重写。
    this.itemsJournalCount = 0;
    this.scheduleFlush();
  }

  /** 只有若干条记录的字段变了时用，追加增量。 */
  appendItems(changed: PhotoBackupItemData[]): void {
    if (changed.length === 0) {
      return;
    }
    if (this.pendingItemsSnapshot !== undefined) {
      // 快照还没落盘，它已经包含这些改动了
      return;
    }
    let text = '';
    changed.forEach((data: PhotoBackupItemData) => {
      const entry: ItemJournalEntry = { data: data };
      text += `${JSON.stringify(entry)}\n`;
    });
    this.pendingItemsJournal += text;
    this.itemsJournalCount += changed.length;
    this.scheduleFlush();
  }

  writeDoneIdsSnapshot(all: string[]): void {
    this.pendingDoneIdsSnapshot = JSON.stringify(all);
    this.pendingDoneIdsJournal = '';
    this.doneIdsSnapshotCount = all.length;
    this.doneIdsJournalCount = 0;
    this.scheduleFlush();
  }

  appendDoneIds(added: string[], removed: string[]): void {
    if (added.length === 0 && removed.length === 0) {
      return;
    }
    if (this.pendingDoneIdsSnapshot !== undefined) {
      return;
    }
    let text = '';
    added.forEach((key: string) => {
      const entry: DoneIdJournalEntry = { a: key };
      text += `${JSON.stringify(entry)}\n`;
    });
    removed.forEach((key: string) => {
      const entry: DoneIdJournalEntry = { d: key };
      text += `${JSON.stringify(entry)}\n`;
    });
    this.pendingDoneIdsJournal += text;
    this.doneIdsJournalCount += added.length + removed.length;
    this.scheduleFlush();
  }

  /** journal 是否已经长到该重写快照了。调用方据此决定下次落盘走全量。 */
  needsItemsCompaction(): boolean {
    return this.itemsJournalCount >= Math.max(COMPACT_MIN_RECORDS, this.itemsSnapshotCount / 2);
  }

  needsDoneIdsCompaction(): boolean {
    return this.doneIdsJournalCount >= Math.max(COMPACT_MIN_RECORDS, this.doneIdsSnapshotCount / 2);
  }

  /** 页面销毁 / 进程可能马上退出时兜底，同步写完再返回。 */
  flushSync(): void {
    const itemsSnapshot = this.pendingItemsSnapshot;
    const doneIdsSnapshot = this.pendingDoneIdsSnapshot;
    const itemsJournal = this.pendingItemsJournal;
    const doneIdsJournal = this.pendingDoneIdsJournal;
    this.clearPending();
    if (itemsSnapshot !== undefined) {
      this.writeFileSync(ITEMS_FILE, itemsSnapshot);
      this.truncateJournalSync(ITEMS_JOURNAL);
    } else if (itemsJournal.length > 0) {
      this.appendJournalSync(ITEMS_JOURNAL, itemsJournal);
    }
    if (doneIdsSnapshot !== undefined) {
      this.writeFileSync(DONE_IDS_FILE, doneIdsSnapshot);
      this.truncateJournalSync(DONE_IDS_JOURNAL);
    } else if (doneIdsJournal.length > 0) {
      this.appendJournalSync(DONE_IDS_JOURNAL, doneIdsJournal);
    }
  }

  private clearPending(): void {
    this.pendingItemsSnapshot = undefined;
    this.pendingDoneIdsSnapshot = undefined;
    this.pendingItemsJournal = '';
    this.pendingDoneIdsJournal = '';
  }

  private scheduleFlush(): void {
    if (this.flushScheduled) {
      return;
    }
    this.flushScheduled = true;
    setTimeout(() => {
      this.flushScheduled = false;
      const itemsSnapshot = this.pendingItemsSnapshot;
      const doneIdsSnapshot = this.pendingDoneIdsSnapshot;
      const itemsJournal = this.pendingItemsJournal;
      const doneIdsJournal = this.pendingDoneIdsJournal;
      this.clearPending();
      // 串成一条链：同一个文件的两次写不能并发交叉，后写的必须后落位
      this.writeChain = this.writeChain.then(async (): Promise<void> => {
        if (itemsSnapshot !== undefined) {
          await this.writeFile(ITEMS_FILE, itemsSnapshot);
          await this.truncateJournal(ITEMS_JOURNAL);
          this.itemsJournalCount = 0;
        } else if (itemsJournal.length > 0) {
          await this.appendJournal(ITEMS_JOURNAL, itemsJournal);
        }
        if (doneIdsSnapshot !== undefined) {
          await this.writeFile(DONE_IDS_FILE, doneIdsSnapshot);
          await this.truncateJournal(DONE_IDS_JOURNAL);
          this.doneIdsJournalCount = 0;
        } else if (doneIdsJournal.length > 0) {
          await this.appendJournal(DONE_IDS_JOURNAL, doneIdsJournal);
        }
      }).catch((err: Error) => {
        AppLogger.error(TAG, `flush failed: ${err?.message ?? err}`);
      });
    }, 0);
  }

  // ---- 文件基础操作 ----

  private parseArray<T>(text: string): T[] {
    if (text.length === 0) {
      return [];
    }
    try {
      return JSON.parse(text) as T[];
    } catch (err) {
      AppLogger.error(TAG, `parse snapshot failed: ${(err as Error)?.message ?? err}`);
      return [];
    }
  }

  private readJournalLines(name: string): string[] {
    const text = this.readFile(name);
    if (text.length === 0) {
      return [];
    }
    return text.split('\n').filter((line: string) => line.length > 0);
  }

  private readFile(name: string): string {
    if (this.baseDir.length === 0) {
      AppLogger.error(TAG, `read ${name} before init`);
      return '';
    }
    const path = `${this.baseDir}/${name}`;
    try {
      if (!fs.accessSync(path)) {
        return '';
      }
      return fs.readTextSync(path);
    } catch (err) {
      AppLogger.error(TAG, `read ${name} failed: ${(err as Error)?.message ?? err}`);
      return '';
    }
  }

  /**
   * 先写 .tmp 再 rename 落位：中途崩溃/断电只会留下一个孤儿 tmp，
   * 正式文件要么是旧的完整内容、要么是新的完整内容，不会被截断成半截 JSON
   * （几千条照片记录被截断就等于整份丢失，所有照片会被当成未备份重传）。
   */
  private async writeFile(name: string, content: string): Promise<void> {
    if (this.baseDir.length === 0) {
      AppLogger.error(TAG, `write ${name} before init`);
      return;
    }
    const path = `${this.baseDir}/${name}`;
    const tmpPath = `${path}${TMP_SUFFIX}`;
    let file: fs.File | undefined = undefined;
    try {
      file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, content);
      await fs.close(file);
      file = undefined;
      await fs.rename(tmpPath, path);
    } catch (err) {
      AppLogger.error(TAG, `write ${name} failed: ${(err as Error)?.message ?? err}`);
      if (file) {
        try {
          await fs.close(file);
        } catch (_) {
        }
      }
    }
  }

  private async appendJournal(name: string, content: string): Promise<void> {
    if (this.baseDir.length === 0) {
      return;
    }
    let file: fs.File | undefined = undefined;
    try {
      file = await fs.open(`${this.baseDir}/${name}`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      await fs.write(file.fd, content);
    } catch (err) {
      AppLogger.error(TAG, `append ${name} failed: ${(err as Error)?.message ?? err}`);
    } finally {
      if (file) {
        try {
          await fs.close(file);
        } catch (_) {
        }
      }
    }
  }

  private async truncateJournal(name: string): Promise<void> {
    const path = `${this.baseDir}/${name}`;
    try {
      if (fs.accessSync(path)) {
        await fs.unlink(path);
      }
    } catch (err) {
      AppLogger.error(TAG, `truncate ${name} failed: ${(err as Error)?.message ?? err}`);
    }
  }

  private writeFileSync(name: string, content: string): void {
    if (this.baseDir.length === 0) {
      AppLogger.error(TAG, `write ${name} before init`);
      return;
    }
    const path = `${this.baseDir}/${name}`;
    const tmpPath = `${path}${TMP_SUFFIX}`;
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      file = undefined;
      fs.renameSync(tmpPath, path);
    } catch (err) {
      AppLogger.error(TAG, `write ${name} sync failed: ${(err as Error)?.message ?? err}`);
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private appendJournalSync(name: string, content: string): void {
    if (this.baseDir.length === 0) {
      return;
    }
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(`${this.baseDir}/${name}`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, content);
    } catch (err) {
      AppLogger.error(TAG, `append ${name} sync failed: ${(err as Error)?.message ?? err}`);
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private truncateJournalSync(name: string): void {
    const path = `${this.baseDir}/${name}`;
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (err) {
      AppLogger.error(TAG, `truncate ${name} sync failed: ${(err as Error)?.message ?? err}`);
    }
  }

  /**
   * 老版本把这两份数据存在 UserPreference 里，一次性搬到独立文件。
   * 顺序很关键：先把文件写完并确认存在，再删 Preferences 里的键——
   * 中途崩溃最多是下次再搬一遍，不会两边都没有。
   */
  private migrateFromPreferences(): void {
    try {
      const itemsDone = this.migrateKey(Constant.PHOTO_BACKUP_ITEMS, ITEMS_FILE);
      const doneIdsDone = this.migrateKey(Constant.PHOTO_BACKUP_DONE_IDS, DONE_IDS_FILE);
      if (itemsDone && doneIdsDone) {
        // 删键会重写一次 Preferences，但只发生在升级后的第一次启动
        UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_ITEMS);
        UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_DONE_IDS);
      }
    } catch (err) {
      AppLogger.error(TAG, `migrate failed: ${(err as Error)?.message ?? err}`);
    }
  }

  /** 返回 true 表示该键的数据已确定存在于文件中（或本来就没有数据），可以安全删除旧键。 */
  private migrateKey(prefKey: string, fileName: string): boolean {
    const path = `${this.baseDir}/${fileName}`;
    if (fs.accessSync(path)) {
      return true;
    }
    const legacy = UserPreferences.getSync(Constant.USER_PREFERENCES, prefKey, '') as string;
    if (!legacy || legacy.length === 0) {
      return true;
    }
    this.writeFileSync(fileName, legacy);
    const ok = fs.accessSync(path);
    if (ok) {
      AppLogger.info(TAG, `migrated ${prefKey} to ${fileName} (${legacy.length} bytes)`);
    } else {
      AppLogger.error(TAG, `migrate ${prefKey} failed, keeping preferences copy`);
    }
    return ok;
  }
}

const PhotoBackupRecordStore = new PhotoBackupRecordStoreImpl();
export default PhotoBackupRecordStore;
