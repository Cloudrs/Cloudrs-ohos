import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import Constant from '../model/Constant';
import { DbUserInfo } from '../model/net/ApiTypes';

const TAG: string = 'AvatarUtil'

interface AvatarApiResponse {
  code?: number
  data?: string
  msg?: string
}

export interface AvatarSource {
  baseUrl: string
  userId: string
  avatar: string
  cookie: string
  refreshToken?: string
}

type HeaderMap = Record<string, string>

interface AvatarFetchResult {
  pixelMap: PixelMap
  data: ArrayBuffer
}

export class AvatarUtil {
  private static cacheDir: string = ''
  private static memoryCache: Map<string, PixelMap> = new Map<string, PixelMap>()
  private static pendingCache: Map<string, Promise<PixelMap | undefined>> = new Map<string, Promise<PixelMap | undefined>>()

  static init(context: Context): void {
    AvatarUtil.cacheDir = `${context.cacheDir}/avatars`
    AvatarUtil.ensureCacheDir()
  }

  static async loadDbUserAvatar(user: DbUserInfo, forceRefresh: boolean = false): Promise<PixelMap | undefined> {
    return AvatarUtil.loadAvatar({
      baseUrl: user.url,
      userId: user.userinfo.id,
      avatar: user.userinfo.avatar,
      cookie: user.cookie,
      refreshToken: user.refresh_token
    }, forceRefresh)
  }

  static async refreshDbUserAvatar(user: DbUserInfo): Promise<PixelMap | undefined> {
    return AvatarUtil.loadDbUserAvatar(user, true)
  }

  static clearDbUserAvatar(user: DbUserInfo): void {
    AvatarUtil.clearAvatar({
      baseUrl: user.url,
      userId: user.userinfo.id,
      avatar: user.userinfo.avatar,
      cookie: user.cookie,
      refreshToken: user.refresh_token
    })
  }

  static clearAvatar(source: AvatarSource): void {
    const cacheKey = AvatarUtil.getCacheKey(source)
    AvatarUtil.memoryCache.delete(cacheKey)
    AvatarUtil.deleteCache(cacheKey)
  }

  static async loadAvatar(source: AvatarSource, forceRefresh: boolean = false): Promise<PixelMap | undefined> {
    const cacheKey = AvatarUtil.getCacheKey(source)
    if (!forceRefresh) {
      const cached = await AvatarUtil.loadCachedPixelMap(cacheKey)
      if (cached) {
        return cached
      }
    }

    const pendingKey = `${cacheKey}|${forceRefresh ? 'refresh' : 'load'}`
    const pending = AvatarUtil.pendingCache.get(pendingKey)
    if (pending) {
      return pending
    }

    const promise = AvatarUtil.loadAvatarFromNetwork(source, cacheKey)
    AvatarUtil.pendingCache.set(pendingKey, promise)
    try {
      return await promise
    } finally {
      AvatarUtil.pendingCache.delete(pendingKey)
    }
  }

  private static async loadAvatarFromNetwork(source: AvatarSource, cacheKey: string): Promise<PixelMap | undefined> {
    const directUrl = AvatarUtil.resolveAvatarUrl(source, source.avatar)
    if (directUrl.length > 0) {
      try {
        return await AvatarUtil.cacheFetchResult(cacheKey,
          await AvatarUtil.requestImage(directUrl, AvatarUtil.buildHeaders(source, directUrl)))
      } catch (err) {
        console.warn(TAG, `load direct avatar failed: ${(err as Error)?.message ?? err}`)
      }
    }

    const baseUrl = AvatarUtil.normalizeBaseUrl(source.baseUrl)
    const userId = AvatarUtil.normalizeText(source.userId)
    if (baseUrl.length === 0 || userId.length === 0) {
      return undefined
    }

    if (AvatarUtil.isV4Source(source)) {
      try {
        const directApiUrl = `${baseUrl}/api/v4/user/avatar/${encodeURIComponent(userId)}?nocache=true`
        const apiAvatar = await AvatarUtil.requestAvatarFromEndpoint(source, directApiUrl)
        if (apiAvatar) {
          return await AvatarUtil.cacheFetchResult(cacheKey, apiAvatar)
        }
      } catch (err) {
        console.warn(TAG, `load v4 avatar endpoint failed: ${(err as Error)?.message ?? err}`)
      }

      try {
        const avatarUrl = await AvatarUtil.requestV4AvatarUrl(source)
        const resolved = AvatarUtil.resolveAvatarUrl(source, avatarUrl)
        if (resolved.length > 0) {
          return await AvatarUtil.cacheFetchResult(cacheKey,
            await AvatarUtil.requestImage(resolved, AvatarUtil.buildHeaders(source, resolved)))
        }
      } catch (err) {
        console.warn(TAG, `load v4 avatar failed: ${(err as Error)?.message ?? err}`)
      }
      return undefined
    }

    try {
      const url = `${baseUrl}/api/v3/user/avatar/${encodeURIComponent(userId)}/l`
      const avatar = await AvatarUtil.requestAvatarFromEndpoint(source, url)
      return avatar ? await AvatarUtil.cacheFetchResult(cacheKey, avatar) : undefined
    } catch (err) {
      console.warn(TAG, `load v3 avatar failed: ${(err as Error)?.message ?? err}`)
      return undefined
    }
  }

  private static async requestV4AvatarUrl(source: AvatarSource): Promise<string> {
    const baseUrl = AvatarUtil.normalizeBaseUrl(source.baseUrl)
    const userId = AvatarUtil.normalizeText(source.userId)
    const url = `${baseUrl}/api/v4/user/avatar/${encodeURIComponent(userId)}`
    const body = await AvatarUtil.requestString(url, AvatarUtil.buildHeaders(source, url))
    const trimmed = body.trim()
    if (trimmed.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
      trimmed.startsWith(Constant.PROTOCOL_HTTPS_SCHEME) ||
      trimmed.startsWith('/')) {
      return trimmed
    }

    const response = JSON.parse(trimmed) as AvatarApiResponse
    return response.data ?? ''
  }

  private static async requestImage(url: string, headers: HeaderMap): Promise<AvatarFetchResult> {
    const data = await AvatarUtil.requestArrayBuffer(url, headers)
    if (!AvatarUtil.isImageData(data)) {
      throw new Error('avatar response is not image data')
    }
    return {
      pixelMap: await AvatarUtil.createPixelMap(data),
      data
    }
  }

  private static async requestAvatarFromEndpoint(source: AvatarSource, url: string): Promise<AvatarFetchResult | undefined> {
    const data = await AvatarUtil.requestArrayBuffer(url, AvatarUtil.buildHeaders(source, url))
    if (AvatarUtil.isImageData(data)) {
      return {
        pixelMap: await AvatarUtil.createPixelMap(data),
        data
      }
    }

    const text = AvatarUtil.arrayBufferToString(data).trim()
    if (text.length === 0 || text.startsWith('<')) {
      throw new Error('avatar endpoint returned empty or html response')
    }
    const resolved = AvatarUtil.resolveAvatarUrl(source, AvatarUtil.extractAvatarUrlFromText(text))
    if (resolved.length === 0) {
      throw new Error('avatar endpoint did not return an image url')
    }
    return AvatarUtil.requestImage(resolved, AvatarUtil.buildHeaders(source, resolved))
  }

  private static async createPixelMap(data: ArrayBuffer): Promise<PixelMap> {
    const imageSource: image.ImageSource = image.createImageSource(data)
    try {
      return await imageSource.createPixelMap({
        desiredSize: {
          width: CloudAvatarDecodeSize.SMALL,
          height: CloudAvatarDecodeSize.SMALL
        }
      })
    } finally {
      imageSource.release()
    }
  }

  private static async requestArrayBuffer(url: string, headers: HeaderMap): Promise<ArrayBuffer> {
    const req = http.createHttp()
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: headers
      })
      if (resp.responseCode === Constant.HTTP_STATUS_OK) {
        return resp.result as ArrayBuffer
      }
      throw new Error(`HTTP ${resp.responseCode}`)
    } finally {
      req.destroy()
    }
  }

  private static async requestString(url: string, headers: HeaderMap): Promise<string> {
    const req = http.createHttp()
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        header: headers
      })
      if (resp.responseCode === Constant.HTTP_STATUS_OK) {
        return resp.result as string
      }
      throw new Error(`HTTP ${resp.responseCode}`)
    } finally {
      req.destroy()
    }
  }

  private static async cacheFetchResult(cacheKey: string, result: AvatarFetchResult): Promise<PixelMap> {
    AvatarUtil.memoryCache.set(cacheKey, result.pixelMap)
    await AvatarUtil.writeCache(cacheKey, result.data)
    return result.pixelMap
  }

  private static async loadCachedPixelMap(cacheKey: string): Promise<PixelMap | undefined> {
    const memory = AvatarUtil.memoryCache.get(cacheKey)
    if (memory) {
      return memory
    }

    const data = AvatarUtil.readCache(cacheKey)
    if (!data || !AvatarUtil.isImageData(data)) {
      return undefined
    }

    try {
      const pixelMap = await AvatarUtil.createPixelMap(data)
      AvatarUtil.memoryCache.set(cacheKey, pixelMap)
      return pixelMap
    } catch (err) {
      console.warn(TAG, `decode cached avatar failed: ${(err as Error)?.message ?? err}`)
      AvatarUtil.deleteCache(cacheKey)
      return undefined
    }
  }

  private static writeCache(cacheKey: string, data: ArrayBuffer): Promise<void> {
    return new Promise<void>((resolve) => {
      const path = AvatarUtil.getCachePath(cacheKey)
      if (path.length === 0 || data.byteLength === 0) {
        resolve()
        return
      }

      let target: fs.File | undefined = undefined
      try {
        AvatarUtil.ensureCacheDir()
        target = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
        fs.writeSync(target.fd, data, { length: data.byteLength })
      } catch (err) {
        console.warn(TAG, `write avatar cache failed: ${(err as Error)?.message ?? err}`)
      } finally {
        if (target) {
          try {
            fs.closeSync(target)
          } catch (_) {
          }
        }
        resolve()
      }
    })
  }

  private static readCache(cacheKey: string): ArrayBuffer | undefined {
    const path = AvatarUtil.getCachePath(cacheKey)
    if (path.length === 0) {
      return undefined
    }

    let source: fs.File | undefined = undefined
    try {
      const size = fs.statSync(path).size
      if (size <= 0) {
        return undefined
      }
      source = fs.openSync(path, fs.OpenMode.READ_ONLY)
      const buffer = new ArrayBuffer(size)
      const readLen = fs.readSync(source.fd, buffer)
      return readLen > 0 ? buffer.slice(0, readLen) : undefined
    } catch (_) {
      return undefined
    } finally {
      if (source) {
        try {
          fs.closeSync(source)
        } catch (_) {
        }
      }
    }
  }

  private static deleteCache(cacheKey: string): void {
    const path = AvatarUtil.getCachePath(cacheKey)
    if (path.length === 0) {
      return
    }
    try {
      fs.unlinkSync(path)
    } catch (_) {
    }
  }

  private static ensureCacheDir(): void {
    if (AvatarUtil.cacheDir.length === 0) {
      return
    }
    try {
      fs.mkdirSync(AvatarUtil.cacheDir)
    } catch (_) {
    }
  }

  private static getCachePath(cacheKey: string): string {
    if (AvatarUtil.cacheDir.length === 0) {
      return ''
    }
    return `${AvatarUtil.cacheDir}/avatar_${cacheKey}.img`
  }

  private static getCacheKey(source: AvatarSource): string {
    const baseUrl = AvatarUtil.normalizeBaseUrl(source.baseUrl)
    const userId = AvatarUtil.normalizeText(source.userId)
    const avatar = AvatarUtil.normalizeText(source.avatar)
    const raw = `${baseUrl}|${userId}|${avatar}`
    return `${raw.length}_${AvatarUtil.hashText(raw)}`
  }

  private static hashText(value: string): string {
    let hash = 2166136261
    for (let index = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index)
      hash = Math.imul(hash, 16777619)
    }
    return (hash >>> 0).toString(16)
  }

  private static buildHeaders(source: AvatarSource, targetUrl: string): HeaderMap {
    const headers: HeaderMap = {
      'Accept': 'image/*,application/json,*/*'
    }
    const cookie = source.cookie ?? ''
    if (AvatarUtil.isV4Source(source)) {
      const token = cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX)
        ? cookie.substring(Constant.CLOUD_V4_COOKIE_PREFIX.length)
        : cookie
      if (token.length > 0 && AvatarUtil.isSameBaseUrl(source.baseUrl, targetUrl)) {
        headers['Authorization'] = `Bearer ${token}`
      }
      return headers
    }

    if (cookie.length > 0 && AvatarUtil.isSameBaseUrl(source.baseUrl, targetUrl)) {
      headers['Cookie'] = cookie.startsWith(Constant.CLOUD_V3_COOKIE_PREFIX)
        ? cookie
        : `${Constant.CLOUD_V3_COOKIE_PREFIX}${cookie}`
    }
    return headers
  }

  private static resolveAvatarUrl(source: AvatarSource, avatar: string): string {
    const value = AvatarUtil.normalizeText(avatar)
    if (value.length === 0 || value === 'file' || value === 'gravatar') {
      return ''
    }
    if (value.startsWith(Constant.PROTOCOL_HTTP_SCHEME) || value.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) {
      return value
    }
    if (value.startsWith('//')) {
      return `${Constant.PROTOCOL_HTTPS_LABEL}:${value}`
    }
    if (value.startsWith('/')) {
      const baseUrl = AvatarUtil.normalizeBaseUrl(source.baseUrl)
      return baseUrl.length > 0 ? `${baseUrl}${value}` : ''
    }
    if (value.startsWith('api/')) {
      const baseUrl = AvatarUtil.normalizeBaseUrl(source.baseUrl)
      return baseUrl.length > 0 ? `${baseUrl}/${value}` : ''
    }
    return ''
  }

  private static extractAvatarUrlFromText(text: string): string {
    if (text.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
      text.startsWith(Constant.PROTOCOL_HTTPS_SCHEME) ||
      text.startsWith('/')) {
      return text
    }
    try {
      const response = JSON.parse(text) as AvatarApiResponse
      return response.data ?? ''
    } catch (_) {
      const match = text.match(/https?:\/\/[^\s"'<>]+/)
      return match && match.length > 0 ? match[0] : ''
    }
  }

  private static isImageData(data: ArrayBuffer): boolean {
    const bytes = new Uint8Array(data)
    if (bytes.length < 12) {
      return false
    }
    const isJpeg = bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF
    const isPng = bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47
    const isGif = bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46
    const isWebp = bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
    return isJpeg || isPng || isGif || isWebp
  }

  private static arrayBufferToString(data: ArrayBuffer): string {
    const bytes = new Uint8Array(data)
    const limit = Math.min(bytes.length, CloudAvatarDecodeSize.TEXT_PREVIEW)
    let text = ''
    for (let index = 0; index < limit; index++) {
      text += String.fromCharCode(bytes[index])
    }
    try {
      return decodeURIComponent(escape(text))
    } catch (_) {
      return text
    }
  }

  private static normalizeBaseUrl(url: string): string {
    let result = AvatarUtil.normalizeText(url)
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1)
    }
    return result
  }

  private static normalizeText(value: string): string {
    if (!value) {
      return ''
    }
    return value.toString().trim()
  }

  private static isV4Source(source: AvatarSource): boolean {
    return (source.cookie ?? '').startsWith(Constant.CLOUD_V4_COOKIE_PREFIX)
  }

  private static isSameBaseUrl(baseUrl: string, targetUrl: string): boolean {
    const base = AvatarUtil.normalizeBaseUrl(baseUrl)
    if (base.length === 0) {
      return false
    }
    return targetUrl.startsWith(base)
  }
}

class CloudAvatarDecodeSize {
  static readonly SMALL: number = 160
  static readonly TEXT_PREVIEW: number = 4096
}
