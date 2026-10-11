import Constant from '../model/Constant';
import { CloudApi } from '../model/net/CloudApi';
import AppLogger from './AppLogger';

const TAG: string = 'ArchiveCapability';

/**
 * 当前账号能否压缩 / 解压。按账号作用域问一次服务端（v4 看用户组权限位 5，v3 看 group.compress），
 * 结果放进 AppStorage，菜单和多选栏直接 @StorageProp 读。问失败按「不支持」处理，下次 refresh 再试。
 */
export class ArchiveCapability {
  private static resolvedScope: string = '';
  private static pendingScope: string = '';

  static refresh(scope: string): void {
    if (scope.length === 0 || scope === ArchiveCapability.resolvedScope || scope === ArchiveCapability.pendingScope) {
      return;
    }
    // 宽屏下文件页不常驻、重新登录时首页重建，都收不到文件页的换账号回调：
    // 结论属于别的账号就先收起入口，等这次查询的结果
    if (ArchiveCapability.resolvedScope.length > 0) {
      ArchiveCapability.resolvedScope = '';
      AppStorage.setOrCreate(Constant.ARCHIVE_ENABLED, false);
    }
    ArchiveCapability.pendingScope = scope;
    CloudApi.archiveSupported({
      onSuccess: (allowed: boolean) => {
        if (ArchiveCapability.pendingScope !== scope) {
          return;
        }
        ArchiveCapability.pendingScope = '';
        ArchiveCapability.resolvedScope = scope;
        AppStorage.setOrCreate(Constant.ARCHIVE_ENABLED, allowed);
        AppLogger.info(TAG, 'archive supported: ' + allowed);
      },
      onFailure: (msg: string) => {
        if (ArchiveCapability.pendingScope !== scope) {
          return;
        }
        ArchiveCapability.pendingScope = '';
        AppStorage.setOrCreate(Constant.ARCHIVE_ENABLED, false);
        AppLogger.warn(TAG, 'check archive permission failed: ' + msg);
      }
    });
  }

  /** 提交时服务端回了 40007：权限刚被收回，立即隐藏入口 */
  static markUnsupported(): void {
    AppStorage.setOrCreate(Constant.ARCHIVE_ENABLED, false);
  }

  /** 换账号：丢掉旧结论，等新账号的 refresh */
  static clear(): void {
    ArchiveCapability.resolvedScope = '';
    ArchiveCapability.pendingScope = '';
    AppStorage.setOrCreate(Constant.ARCHIVE_ENABLED, false);
  }
}
