import fs from '@ohos.file.fs'
import { common } from '@kit.AbilityKit'
import AppLogger from './AppLogger'

const TAG: string = 'TextDraftStore'
const DRAFT_DIR_NAME: string = 'text_drafts'

/**
 * 保存失败时的草稿兜底。
 *
 * 上传失败就意味着用户刚写的内容只存在于内存里，一退出页面就没了；
 * UploadManager 里那条「失败会在服务端留 0KB 占位」的注释说明这条链路真的会失败。
 * 所以保存一旦不成功，正文必须先落到本地，下次打开同一个文件时再问要不要恢复。
 */
export class TextDraftStore {
  private static dir: string = ''

  static init(context: common.UIAbilityContext): void {
    if (TextDraftStore.dir.length > 0) {
      return
    }
    TextDraftStore.dir = `${context.filesDir}/${DRAFT_DIR_NAME}`
    try {
      if (!fs.accessSync(TextDraftStore.dir)) {
        fs.mkdirSync(TextDraftStore.dir)
      }
    } catch (err) {
      AppLogger.warn(TAG, `mkdir failed: ${(err as Error)?.message ?? err}`)
    }
  }

  static save(fileId: string, text: string): boolean {
    const path = TextDraftStore.pathOf(fileId)
    if (path.length === 0) {
      return false
    }
    let file: fs.File | undefined = undefined
    try {
      file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, text)
      AppLogger.info(TAG, `draft saved for ${fileId}, ${text.length} chars`)
      return true
    } catch (err) {
      AppLogger.error(TAG, `save draft failed: ${(err as Error)?.message ?? err}`)
      return false
    } finally {
      if (file) {
        try {
          fs.closeSync(file)
        } catch (_) {
        }
      }
    }
  }

  static load(fileId: string): string | undefined {
    const path = TextDraftStore.pathOf(fileId)
    if (path.length === 0) {
      return undefined
    }
    try {
      if (!fs.accessSync(path)) {
        return undefined
      }
      return fs.readTextSync(path)
    } catch (err) {
      AppLogger.warn(TAG, `load draft failed: ${(err as Error)?.message ?? err}`)
      return undefined
    }
  }

  static clear(fileId: string): void {
    const path = TextDraftStore.pathOf(fileId)
    if (path.length === 0) {
      return
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path)
      }
    } catch (err) {
      AppLogger.warn(TAG, `clear draft failed: ${(err as Error)?.message ?? err}`)
    }
  }

  /** fileId 可能带斜杠等字符，不能直接当文件名 */
  private static pathOf(fileId: string): string {
    if (TextDraftStore.dir.length === 0 || fileId.length === 0) {
      return ''
    }
    return `${TextDraftStore.dir}/draft_${TextDraftStore.keyOf(fileId)}.txt`
  }

  /**
   * 用哈希做键，不用"净化字符"的办法。
   * 把非法字符统统换成下划线会丢信息：中文文件名每个字都变成下划线，
   * /文档/笔记.md 与 /日志/记录.md 会得到同一个键，于是打开 A 却被提示
   * 恢复 B 的草稿、保存后写错文件。哈希对全部字符敏感，不存在这个问题。
   */
  private static keyOf(fileId: string): string {
    return `${TextDraftStore.fnv1a(fileId, 0x811C9DC5)}${TextDraftStore.fnv1a(fileId, 0x01000193)}`
  }

  /** FNV-1a：纯函数、无依赖，两个不同种子拼出的键足够避免碰撞 */
  private static fnv1a(input: string, seed: number): string {
    let hash = seed >>> 0
    for (let i = 0; i < input.length; i++) {
      hash = (hash ^ input.charCodeAt(i)) >>> 0
      // 等价于 hash * 16777619，拆成移位避免 32 位溢出丢精度
      hash = (hash + ((hash << 1) >>> 0) + ((hash << 4) >>> 0) +
        ((hash << 7) >>> 0) + ((hash << 8) >>> 0) + ((hash << 24) >>> 0)) >>> 0
    }
    return hash.toString(16).padStart(8, '0')
  }
}
