import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

export interface LogEntry {
  time: number;
  level: string;
  tag: string;
  message: string;
}

const HILOG_DOMAIN: number = 0xFF02;
const HILOG_PREFIX: string = 'Cloudrs';
const HILOG_FORMAT: string = '%{public}s %{public}s';
const RING_CAPACITY: number = 300;
const FILE_ROTATE_BYTES: number = 256 * 1024;
const LOG_DIR_NAME: string = 'logs';
const FILE_NAME_PRIMARY: string = 'app.log';
const FILE_NAME_BACKUP: string = 'app.log.1';
const TAG_INTERNAL: string = 'AppLogger';

class AppLogger {
  private ring: LogEntry[] = [];
  private writeIndex: number = 0;
  private dir: string = '';
  private filePath: string = '';
  private backupPath: string = '';
  private initialized: boolean = false;

  init(context: Context): void {
    try {
      this.dir = `${context.filesDir}/${LOG_DIR_NAME}`;
      this.filePath = `${this.dir}/${FILE_NAME_PRIMARY}`;
      this.backupPath = `${this.dir}/${FILE_NAME_BACKUP}`;
      this.ensureDir();
      this.initialized = true;
      this.info(TAG_INTERNAL, `init ok, file=${this.filePath}`);
    } catch (err) {
      this.initialized = false;
      hilog.error(HILOG_DOMAIN, HILOG_PREFIX, HILOG_FORMAT, TAG_INTERNAL,
        `init failed: ${(err as Error)?.message ?? err}`);
    }
  }

  debug(tag: string, message: string = ''): void {
    this.write('DEBUG', tag, message);
  }

  info(tag: string, message: string = ''): void {
    this.write('INFO', tag, message);
  }

  warn(tag: string, message: string = ''): void {
    this.write('WARN', tag, message);
  }

  error(tag: string, message: string = ''): void {
    this.write('ERROR', tag, message);
  }

  getRecentText(maxLines: number = 60): string {
    const entries = this.snapshot();
    const start = entries.length > maxLines ? entries.length - maxLines : 0;
    const lines: string[] = [];
    for (let index = start; index < entries.length; index++) {
      lines.push(this.format(entries[index]));
    }
    return lines.join('\n');
  }

  getAllText(): string {
    const fromFile = this.readFile();
    if (fromFile.length > 0) {
      return fromFile;
    }
    return this.snapshot().map((entry) => this.format(entry)).join('\n');
  }

  getFilePath(): string {
    return this.filePath;
  }

  hasLogs(): boolean {
    if (this.ring.length > 0) {
      return true;
    }
    if (!this.initialized) {
      return false;
    }
    try {
      return fs.statSync(this.filePath).size > 0;
    } catch (_) {
      return false;
    }
  }

  clear(): void {
    this.ring = [];
    this.writeIndex = 0;
    if (!this.initialized) {
      return;
    }
    this.unlinkIfExists(this.filePath);
    this.unlinkIfExists(this.backupPath);
    this.info(TAG_INTERNAL, 'log cleared');
  }

  private write(level: string, tag: string, message: string): void {
    const sanitized = this.sanitize(message);
    const entry: LogEntry = { time: Date.now(), level, tag, message: sanitized };
    this.pushRing(entry);
    this.appendFile(entry);
    this.echoHilog(entry);
  }

  private echoHilog(entry: LogEntry): void {
    switch (entry.level) {
      case 'ERROR':
        hilog.error(HILOG_DOMAIN, HILOG_PREFIX, HILOG_FORMAT, entry.tag, entry.message);
        break;
      case 'WARN':
        hilog.warn(HILOG_DOMAIN, HILOG_PREFIX, HILOG_FORMAT, entry.tag, entry.message);
        break;
      case 'DEBUG':
        hilog.debug(HILOG_DOMAIN, HILOG_PREFIX, HILOG_FORMAT, entry.tag, entry.message);
        break;
      default:
        hilog.info(HILOG_DOMAIN, HILOG_PREFIX, HILOG_FORMAT, entry.tag, entry.message);
        break;
    }
  }

  private pushRing(entry: LogEntry): void {
    if (this.ring.length < RING_CAPACITY) {
      this.ring.push(entry);
      return;
    }
    this.ring[this.writeIndex] = entry;
    this.writeIndex = (this.writeIndex + 1) % RING_CAPACITY;
  }

  private snapshot(): LogEntry[] {
    if (this.ring.length < RING_CAPACITY) {
      return this.ring.slice();
    }
    const out: LogEntry[] = [];
    for (let index = 0; index < RING_CAPACITY; index++) {
      out.push(this.ring[(this.writeIndex + index) % RING_CAPACITY]);
    }
    return out;
  }

  private appendFile(entry: LogEntry): void {
    if (!this.initialized) {
      return;
    }
    let file: fs.File | undefined = undefined;
    try {
      this.maybeRotate();
      const line = this.format(entry) + '\n';
      file = fs.openSync(this.filePath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, line);
    } catch (err) {
      hilog.warn(HILOG_DOMAIN, HILOG_PREFIX, HILOG_FORMAT, TAG_INTERNAL,
        `append failed: ${(err as Error)?.message ?? err}`);
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private maybeRotate(): void {
    let size = 0;
    try {
      size = fs.statSync(this.filePath).size;
    } catch (_) {
      return;
    }
    if (size < FILE_ROTATE_BYTES) {
      return;
    }
    this.unlinkIfExists(this.backupPath);
    try {
      fs.renameSync(this.filePath, this.backupPath);
    } catch (err) {
      hilog.warn(HILOG_DOMAIN, HILOG_PREFIX, HILOG_FORMAT, TAG_INTERNAL,
        `rotate failed: ${(err as Error)?.message ?? err}`);
    }
  }

  private ensureDir(): void {
    try {
      fs.mkdirSync(this.dir);
    } catch (_) {
    }
  }

  private unlinkIfExists(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (_) {
    }
  }

  private readFile(): string {
    if (!this.initialized) {
      return '';
    }
    const backup = this.readWholeFile(this.backupPath);
    const primary = this.readWholeFile(this.filePath);
    if (backup.length === 0) {
      return primary;
    }
    if (primary.length === 0) {
      return backup;
    }
    return `${backup}${primary}`;
  }

  private readWholeFile(path: string): string {
    let file: fs.File | undefined = undefined;
    try {
      const stat = fs.statSync(path);
      if (stat.size <= 0) {
        return '';
      }
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer));
    } catch (_) {
      return '';
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private format(entry: LogEntry): string {
    return `${this.formatTime(entry.time)} ${this.padLevel(entry.level)} [${entry.tag}] ${entry.message}`;
  }

  private padLevel(level: string): string {
    if (level.length >= 5) {
      return level;
    }
    return level + '     '.substring(0, 5 - level.length);
  }

  private formatTime(t: number): string {
    const d = new Date(t);
    return `${d.getFullYear()}-${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())} ` +
      `${this.pad2(d.getHours())}:${this.pad2(d.getMinutes())}:${this.pad2(d.getSeconds())}.${this.pad3(d.getMilliseconds())}`;
  }

  private pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  private pad3(n: number): string {
    if (n < 10) {
      return `00${n}`;
    }
    if (n < 100) {
      return `0${n}`;
    }
    return `${n}`;
  }

  private sanitize(text: string): string {
    let s = text;
    s = s.replace(/(cookie\s*[:=]\s*)([^\s,;]+)/gi, '$1***');
    s = s.replace(/(set-cookie\s*[:=]\s*)([^\s,;]+)/gi, '$1***');
    s = s.replace(/(authorization\s*[:=]\s*)([^\s,;]+)/gi, '$1***');
    s = s.replace(/(token\s*=\s*)([^&\s"']+)/gi, '$1***');
    s = s.replace(/(refresh_token\s*=\s*)([^&\s"']+)/gi, '$1***');
    s = s.replace(/(refresh_token["']?\s*[:=]\s*["']?)([^"',\s}]+)/gi, '$1***');
    s = s.replace(/(sign\s*=\s*)([^&\s"']+)/gi, '$1***');
    s = s.replace(/(cloudreve-session\s*=\s*)([^;\s"']+)/gi, '$1***');
    s = s.replace(/(v4:)([A-Za-z0-9_.\-+/=]{8,})/g, '$1***');
    return s;
  }
}

const appLogger = new AppLogger();
export default appLogger;
