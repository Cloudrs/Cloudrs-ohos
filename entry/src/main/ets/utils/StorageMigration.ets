import fs from '@ohos.file.fs';
import Constant from '../model/Constant';
import UserDatabase from '../model/UserDatabase';
import TransferDatabase from '../model/TransferDatabase';
import AppLogger from './AppLogger';

const TAG: string = 'StorageMigration';

/**
 * 把用户数据从 HAP 模块级目录一次性搬到 App 级目录。
 *
 * 背景：模块级目录（UIAbilityContext 的 databaseDir/preferencesDir）会随 HAP 卸载被系统删除。
 * 拆分 entry2in1 模块时 2in1 设备的模块从 entry 换名，模块级数据整体丢失；为避免以后调整
 * 模块结构再丢数据，UserDatabase/TransferDatabase/UserPreferences 全部改存 App 级目录，
 * 老用户遗留在模块级目录里的数据由这里搬迁。
 *
 * 必须在本进程第一次打开这些库/首选项之前调用（保证没有句柄持有 -wal/-shm）。
 * App 级已存在主文件视为已迁移。
 */
export class StorageMigration {
  static migrate(context: Context): void {
    const appContext = context.getApplicationContext();
    StorageMigration.migrateFiles(
      `${context.databaseDir}/rdb`,
      `${appContext.databaseDir}/rdb`,
      [UserDatabase.dbName, TransferDatabase.dbName],
      ['-wal', '-shm']
    );
    StorageMigration.migrateFiles(
      context.preferencesDir,
      appContext.preferencesDir,
      [Constant.USER_PREFERENCES],
      []
    );
  }

  private static migrateFiles(srcDir: string, dstDir: string, names: string[], suffixes: string[]): void {
    for (const name of names) {
      try {
        const srcMain = `${srcDir}/${name}`;
        const dstMain = `${dstDir}/${name}`;
        if (fs.accessSync(dstMain)) {
          // 已迁移;若上次在"拷完、删源前"中断,这里补删残留(含敏感数据副本)
          StorageMigration.removeFiles(srcDir, name, suffixes);
          continue;
        }
        if (!fs.accessSync(srcMain)) {
          continue;
        }
        if (!fs.accessSync(dstDir)) {
          fs.mkdirSync(dstDir, true);
        }
        // 辅助文件(-wal/-shm)先拷,主文件最后经临时名改名落位:
        // 主文件在目标目录出现即代表迁移完整,中断后下次启动可安全重试,
        // 不会出现"主库半份/缺 WAL"却被当成已迁移的静默丢数据
        for (const suffix of suffixes) {
          const src = `${srcDir}/${name}${suffix}`;
          if (fs.accessSync(src)) {
            fs.copyFileSync(src, `${dstDir}/${name}${suffix}`);
          }
        }
        const tmpMain = `${dstMain}.migtmp`;
        fs.copyFileSync(srcMain, tmpMain);
        fs.renameSync(tmpMain, dstMain);
        StorageMigration.removeFiles(srcDir, name, suffixes);
        AppLogger.info(TAG, `migrated ${name} to app-level dir`);
      } catch (err) {
        AppLogger.error(TAG, `migrate ${name} failed: ${(err as Error)?.message ?? err}`);
      }
    }
  }

  private static removeFiles(dir: string, name: string, suffixes: string[]): void {
    const targets: string[] = [`${dir}/${name}`];
    for (const suffix of suffixes) {
      targets.push(`${dir}/${name}${suffix}`);
    }
    for (const target of targets) {
      if (fs.accessSync(target)) {
        fs.unlinkSync(target);
      }
    }
  }
}
