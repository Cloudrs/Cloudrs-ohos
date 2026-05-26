import fs from '@ohos.file.fs';

export class FileSystemUtil {
  static async copyUriToPath(uri: string, targetPath: string): Promise<void> {
    let source: fs.File | undefined = undefined;
    try {
      source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(source.fd, targetPath);
    } catch (err) {
      throw new Error((err as Error)?.message ?? `${err}`);
    } finally {
      if (source) {
        try {
          fs.closeSync(source);
        } catch (_) {
        }
      }
    }
  }

  static async unlinkIfExists(path: string): Promise<void> {
    try {
      await fs.unlink(path);
    } catch (_) {
    }
  }
}
