import Constant from '../model/Constant'
import { ObjectInfo } from '../model/net/ApiTypes'
import { TextPreviewParam } from '../model/Params'
import { CloudRouter } from './CloudRouter'
import { CommonUtil } from './CommonUtil'
import { showToast } from './ToastUtil'

/**
 * 文本预览的统一入口。
 * 文件页和搜索页都要打开文本，大小拦截只写一次，免得两处阈值走散。
 */
export class TextPreviewEntry {
  static open(item: ObjectInfo, onSaved?: () => void): void {
    if (item.size > Constant.TEXT_PREVIEW_MAX_BYTES) {
      showToast(`文件超过 ${CommonUtil.formatBytes(Constant.TEXT_PREVIEW_MAX_BYTES)}，暂不支持预览`)
      return
    }
    CloudRouter.push(Constant.TEXT_PREVIEW_PAGE,
      new TextPreviewParam(item.name, item.id, item.size, TextPreviewEntry.remotePathOf(item), onSaved))
  }

  /**
   * 文件的覆盖上传路径 = 所在目录 + 文件名。
   * 注意 ObjectInfo.path 对文件而言是所在目录而不是自身全路径（CloudApi.getTotalPath
   * 只对目录返回全路径），直接拿它当上传目标会打到目录上，服务端回 40004 Object existed。
   * 拼法与 UploadManager.enqueue 保持一致。
   */
  private static remotePathOf(item: ObjectInfo): string {
    const dir = item.path
    const sep = dir.endsWith('/') ? '' : '/'
    return `${dir}${sep}${item.name}`
  }
}
