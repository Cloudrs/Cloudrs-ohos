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
    return `${TextDraftStore.dir}/${TextDraftStore.sanitize(fileId)}.txt`
  }

  private static sanitize(fileId: string): string {
    let safe = ''
    for (let i = 0; i < fileId.length; i++) {
      const ch = fileId.charAt(i)
      safe += /[a-zA-Z0-9_-]/.test(ch) ? ch : '_'
    }
    // 不同 id 净化后可能撞名，补一个长度后缀降低碰撞
    return `${safe.substring(0, 96)}_${fileId.length}`
  }
}
