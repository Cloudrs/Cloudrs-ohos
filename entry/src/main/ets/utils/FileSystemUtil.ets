import fs from '@ohos.file.fs';
import taskpool from '@ohos.taskpool';
import { fileUri } from '@kit.CoreFileKit';
import Constant from '../model/Constant';

@Concurrent
function copyUriToPathTask(uri: string, targetPath: string, copyChunkSize: number): number {
  let source: fs.File | undefined = undefined;
  let target: fs.File | undefined = undefined;
  let copied = 0;

  try {
    source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    target = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    const buffer = new ArrayBuffer(copyChunkSize);
    while (true) {
      const readLen = fs.readSync(source.fd, buffer);
      if (readLen <= 0) {
        break;
      }
      fs.writeSync(target.fd, buffer, { length: readLen });
      copied += readLen;
    }
    return copied;
  } catch (err) {
    throw new Error((err as Error)?.message ?? `${err}`);
  } finally {
    if (source) {
      try {
        fs.closeSync(source);
      } catch (_) {
      }
    }
    if (target) {
      try {
        fs.closeSync(target);
      } catch (_) {
      }
    }
  }
}

export class FileSystemUtil {
  static getUriFromPath(path: string): string {
    return fileUri.getUriFromPath(path);
  }

  static getPathFromUri(uriOrPath: string): string {
    if (!uriOrPath.startsWith('file://')) {
      return uriOrPath;
    }

    try {
      return new fileUri.FileUri(uriOrPath).path;
    } catch (_) {
      return uriOrPath;
    }
  }

  static getFileSize(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (_) {
      return 0;
    }
  }

  static async copyUriToPath(
    uri: string,
    targetPath: string,
    onProgress?: (copied: number, total: number) => void
  ): Promise<number> {
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    let copied = 0;
    const total = FileSystemUtil.getFileSize(uri);

    try {
      source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      target = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const buffer = new ArrayBuffer(Constant.FILE_COPY_CHUNK_SIZE);
      while (true) {
        const readLen = fs.readSync(source.fd, buffer);
        if (readLen <= 0) {
          break;
        }
        fs.writeSync(target.fd, buffer, { length: readLen });
        copied += readLen;
        onProgress?.(copied, total);
        await new Promise<void>((resolve) => setTimeout(resolve, Constant.FILE_COPY_YIELD_DELAY_MS));
      }
      return copied;
    } catch (err) {
      throw new Error((err as Error)?.message ?? `${err}`);
    } finally {
      if (source) {
        try {
          fs.closeSync(source);
        } catch (_) {
        }
      }
      if (target) {
        try {
          fs.closeSync(target);
        } catch (_) {
        }
      }
    }
  }

  static async copyUriToPathFast(uri: string, targetPath: string): Promise<number> {
    let source: fs.File | undefined = undefined
    try {
      source = fs.openSync(uri, fs.OpenMode.READ_ONLY)
      await fs.copyFile(source.fd, targetPath, 0)
      return FileSystemUtil.getFileSize(targetPath)
    } catch (err) {
      throw new Error((err as Error)?.message ?? `${err}`)
    } finally {
      if (source) {
        try { fs.closeSync(source) } catch (_) {}
      }
    }
  }

  static async copyUriToPathInBackground(uri: string, targetPath: string): Promise<number> {
    try {
      const task = new taskpool.Task(copyUriToPathTask, uri, targetPath, Constant.FILE_COPY_CHUNK_SIZE);
      return await taskpool.execute(task, taskpool.Priority.LOW) as number;
    } catch (err) {
      throw new Error((err as Error)?.message ?? `${err}`);
    }
  }

  static async unlinkIfExists(path: string): Promise<void> {
    try {
      await fs.unlink(path);
    } catch (_) {
    }
  }

  static async writeArrayBuffer(path: string, data: ArrayBuffer, overwrite: boolean = true): Promise<void> {
    let target: fs.File | undefined = undefined;
    try {
      target = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | (overwrite ? fs.OpenMode.TRUNC : 0));
      fs.writeSync(target.fd, data, { length: data.byteLength });
    } catch (err) {
      throw new Error((err as Error)?.message ?? `${err}`);
    } finally {
      if (target) {
        try {
          fs.closeSync(target);
        } catch (_) {
        }
      }
    }
  }

  static async moveFile(srcPath: string, dstPath: string, mode: number = 0): Promise<void> {
    try {
      await fs.moveFile(srcPath, dstPath, mode);
    } catch (err) {
      throw new Error((err as Error)?.message ?? `${err}`);
    }
  }
}
