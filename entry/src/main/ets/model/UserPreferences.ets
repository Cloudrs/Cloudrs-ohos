import { sendablePreferences } from '@kit.ArkData';
import { lang } from '@kit.ArkTS';
import AppLogger from '../utils/AppLogger';

class UserPreferences {
  perfMap: Map<string, sendablePreferences.Preferences> = new Map()

  init(context: Context, name: string) {
    try {
      let options: sendablePreferences.Options = { name };
      // App 级目录，不随单个 HAP 卸载删除；老数据迁移见 StorageMigration
      let perf = sendablePreferences.getPreferencesSync(context.getApplicationContext(), options)
      this.perfMap.set(name, perf)
    } catch (e) {
      AppLogger.error('UserPrivData', `加载首选项失败, 错误: ${(e as Error)?.message ?? e}`)
    }
  }

  putSync(name: string, key: string, value: lang.ISendable) {
    try {
      if (!this.perfMap.has(name)) {
        AppLogger.error('UserPrivData', `首选项${name}尚未初始化`)
        return
      }
      let perf = this.perfMap.get(name)!
      // 写入数据
      perf.putSync(key, value)
      // 刷入磁盘
      perf.flush()
      console.debug('UserPrivData', `保存首选项${name}.${key} : ${value} 成功`)
    } catch (e) {
      AppLogger.error('UserPrivData', `保存首选项${name}.${key} 失败, 错误: ${(e as Error)?.message ?? e}`)
    }
  }

  getSync(name: string, key: string, defValue: lang.ISendable = ''): lang.ISendable | undefined {
    try {
      if (!this.perfMap.has(name)) {
        AppLogger.error('UserPrivData', `首选项${name}尚未初始化`)
        return undefined
      }
      let perf = this.perfMap.get(name)!
      // 读取数据
      let value = perf.getSync(key, defValue)
      console.debug('UserPrivData', `获取首选项${name}.${key} : ${value} 成功`)
      return value
    } catch (e) {
      AppLogger.error('UserPrivData', `获取首选项${name}.${key} 失败, 错误: ${(e as Error)?.message ?? e}`)
      return undefined
    }
  }

  deleteSync(name: string, key: string) {
    try {
      if (!this.perfMap.has(name)) {
        AppLogger.error('UserPrivData', `首选项${name}尚未初始化`)
        return
      }
      let perf = this.perfMap.get(name)!
      // 删除数据
      perf.deleteSync(key)
      // 刷入磁盘
      perf.flush()
      console.debug('UserPrivData', `删除首选项${name}.${key} 成功`)
    } catch (e) {
      AppLogger.error('UserPrivData', `删除首选项${name}.${key} 失败, 错误: ${(e as Error)?.message ?? e}`)
    }
  }
}

export default new UserPreferences();