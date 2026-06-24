import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { ObjectInfo } from '../model/net/ApiTypes'
import { CloudApi } from '../model/net/CloudApi'
import { CommonUtil } from './CommonUtil'
import Constant from '../model/Constant'
import AppLogger from './AppLogger'

export interface SaveAlbumResult {
  success: number
  failed: number
  canceled: boolean
}

export type SaveProgress = (done: number, total: number) => void

const TAG: string = 'PhotoSaveUtil'

function resolveDownloadUrl(id: string): Promise<string> {
  return new Promise<string>((resolve: (url: string) => void, reject: (err: Error) => void) => {
    CloudApi.getDownloadUri(id, {
      onSuccess: (url: string) => {
        const full = (url.startsWith(Constant.PROTOCOL_HTTP_SCHEME) || url.startsWith(Constant.PROTOCOL_HTTPS_SCHEME))
          ? url : CloudApi.getBaseURL() + url
        resolve(full)
      },
      onFailure: (msg: string) => reject(new Error(msg))
    })
  })
}

async function downloadArrayBuffer(url: string): Promise<ArrayBuffer> {
  const req = http.createHttp()
  try {
    const resp = await req.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    })
    if (resp.responseCode !== Constant.HTTP_STATUS_OK) {
      throw new Error('http status ' + resp.responseCode)
    }
    return resp.result as ArrayBuffer
  } finally {
    req.destroy()
  }
}

/** 申请相册写入权限（WRITE_IMAGEVIDEO）。已授予则直接返回 true，未授予则弹一次系统授权框。 */
async function ensureWritePermission(context: common.UIAbilityContext): Promise<boolean> {
  const permission: Permissions = 'ohos.permission.WRITE_IMAGEVIDEO'
  try {
    const atManager = abilityAccessCtrl.createAtManager()
    const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(context, [permission])
    const auths: number[] = result.authResults ?? []
    return auths.length > 0 && auths[Constant.FIRST_ARRAY_INDEX] === Constant.PERMISSION_AUTH_GRANTED
  } catch (err) {
    AppLogger.error(TAG, `request WRITE_IMAGEVIDEO failed: ${(err as Error)?.message ?? err}`)
    return false
  }
}

/**
 * 将一组云端图片保存到系统相册。
 * 首次调用申请一次 WRITE_IMAGEVIDEO 权限；授予后逐张 http 下原图 → createAssetRequest + addResource
 * + applyChanges 静默写入媒体库（之后保存不再弹框）。文件名用原名（CreateOptions.title）。
 */
export async function saveImagesToAlbum(items: ObjectInfo[], context: common.UIAbilityContext,
  onProgress?: SaveProgress): Promise<SaveAlbumResult> {
  const total = items.length
  if (total === 0) {
    return { success: 0, failed: 0, canceled: false }
  }

  const granted = await ensureWritePermission(context)
  if (!granted) {
    return { success: 0, failed: total, canceled: true }
  }

  const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context)
  let success = 0
  let failed = 0
  for (let i = 0; i < total; i++) {
    const item = items[i]
    try {
      const url = await resolveDownloadUrl(item.id)
      const buffer = await downloadArrayBuffer(url)
      const ext = CommonUtil.getFileExtention(item.name) || 'jpg'
      const options: photoAccessHelper.CreateOptions = {
        title: CommonUtil.sanitizeAlbumTitle(item.name)
      }
      const assetRequest = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        context, photoAccessHelper.PhotoType.IMAGE, ext, options)
      assetRequest.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, buffer)
      await phAccessHelper.applyChanges(assetRequest)
      success++
    } catch (err) {
      AppLogger.error(TAG, `save failed: ${(err as Error)?.message ?? err}`)
      failed++
    } finally {
      if (onProgress) {
        onProgress(i + 1, total)
      }
    }
  }
  return { success: success, failed: failed, canceled: false }
}
