import fs from '@ohos.file.fs';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import TransferDatabase, { DownloadRecord } from '../model/TransferDatabase';
import { FileModelState } from '../model/FileModel';
import { FileSystemUtil } from './FileSystemUtil';
import { CloudApi } from '../model/net/CloudApi';
import UserPreferences from '../model/UserPreferences';
import Constant from '../model/Constant';

export class KnockShareLink {
  url: string = ''
  password: string = ''
}

/**
 * 碰一碰分享的分层策略工具:
 * 已下载完成的文件分享本体(对端媒体文件进图库、其他文件进文件管理"华为分享"目录),
 * 未下载的分享下载直链(对端浏览器在线查看或下载)。
 */
export class KnockShareUtil {
  // 该文件已下载完成且本地仍存在时返回其 file:// URI,否则返回 ''
  static findLocalDownloadUri(fileId: string): string {
    const record = TransferDatabase.listDownloads().find((r: DownloadRecord) =>
      r.item.id === fileId && r.state === FileModelState.COMPLETED)
    if (!record || !FileSystemUtil.exists(record.path)) {
      return ''
    }
    return FileSystemUtil.getUriFromPath(record.path)
  }

  static buildFileShareData(fileName: string, uri: string): systemShare.SharedData {
    return new systemShare.SharedData({
      utd: KnockShareUtil.utdForFileName(fileName),
      title: fileName,
      uri: uri
    })
  }

  static buildLinkShareData(fileName: string, url: string, password: string = ''): systemShare.SharedData {
    return new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
      content: url,
      title: fileName,
      description: password.length > 0 ? `提取码：${password}` : '通过浏览器在线查看或下载'
    })
  }

  // 设置项:未下载文件碰一碰时是否创建 Cloudreve 分享链接(默认发下载直链)
  static useShareLink(): boolean {
    return UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.KNOCK_SHARE_USE_SHARE_LINK, false) as boolean
  }

  // 同一文件本次会话内复用已创建的分享链接,避免重复碰产生一堆分享记录
  private static shareLinkCache: Map<string, KnockShareLink> = new Map<string, KnockShareLink>()

  static createOrReuseShareLink(fileId: string, sharePath: string): Promise<KnockShareLink | null> {
    const cached = KnockShareUtil.shareLinkCache.get(fileId)
    if (cached) {
      return Promise.resolve<KnockShareLink | null>(cached)
    }
    const expireDays = UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.KNOCK_SHARE_EXPIRE_DAYS, 1) as number
    const passwordEnabled = UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.KNOCK_SHARE_PASSWORD_ENABLED, false) as boolean
    const password = passwordEnabled ? KnockShareUtil.randomPassword() : ''
    return new Promise<KnockShareLink | null>((resolve: (value: KnockShareLink | null) => void) => {
      CloudApi.createShareLink(sharePath, expireDays, password, {
        onSuccess: (url: string) => {
          const link = new KnockShareLink()
          link.url = url
          link.password = password
          KnockShareUtil.shareLinkCache.set(fileId, link)
          resolve(link)
        },
        onFailure: () => {
          resolve(null)
        }
      })
    })
  }

  private static randomPassword(): string {
    return Math.floor(1000 + Math.random() * 9000).toString()
  }

  // ---- 沙箱接收(平板/2in1 作为接收端) ----

  private static readonly RECEIVE_DIR_TTL_MS: number = 24 * 60 * 60 * 1000

  // 每次接收使用独立的时间戳子目录(官方建议用空目录做授权),同时清理超过一天的历史目录。
  // 返回子目录路径;创建失败返回 ''。
  static prepareReceiveDir(filesDir: string): string {
    const baseDir = `${filesDir}/knock_receive`
    try {
      if (!fs.accessSync(baseDir)) {
        fs.mkdirSync(baseDir)
      }
      KnockShareUtil.cleanStaleReceiveDirs(baseDir)
      const dir = `${baseDir}/${Date.now()}`
      fs.mkdirSync(dir)
      return dir
    } catch (_) {
      return ''
    }
  }

  private static cleanStaleReceiveDirs(baseDir: string): void {
    try {
      const names = fs.listFileSync(baseDir)
      const now = Date.now()
      names.forEach((name: string) => {
        const ts = Number(name)
        if (!Number.isNaN(ts) && now - ts > KnockShareUtil.RECEIVE_DIR_TTL_MS) {
          try {
            fs.rmdirSync(`${baseDir}/${name}`)
          } catch (_) {
            // 忽略单个目录清理失败
          }
        }
      })
    } catch (_) {
      // 忽略清理失败,不影响本次接收
    }
  }

  // 按扩展名解析 UTD,识别不了时回退 general.object;媒体类 UTD 决定对端"存图库"的一步直达体验。
  private static utdForFileName(fileName: string): string {
    const dot = fileName.lastIndexOf('.')
    const ext = dot >= 0 ? fileName.substring(dot).toLowerCase() : ''
    if (ext.length > 1) {
      try {
        const utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(ext,
          uniformTypeDescriptor.UniformDataType.OBJECT)
        if (utd && utd.length > 0) {
          return utd
        }
      } catch (_) {
        // fall through
      }
    }
    return uniformTypeDescriptor.UniformDataType.OBJECT
  }
}
