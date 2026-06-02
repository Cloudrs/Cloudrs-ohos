import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { fileUri } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import Constant from '../model/Constant';
import { DbUserInfo } from '../model/net/ApiTypes';

const TAG: string = 'AvatarUtil'
const AVATAR_TRACE_ENABLED: boolean = false

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
  private static legacyCacheDir: string = ''
  private static memoryCache: Map<string, PixelMap> = new Map<string, PixelMap>()
  private static pendingCache: Map<string, Promise<PixelMap | undefined>> = new Map<string, Promise<PixelMap | undefined>>()

  static init(context: Context): void {
    AvatarUtil.cacheDir = `${context.filesDir}/avatars`
    AvatarUtil.legacyCacheDir = `${context.cacheDir}/avatars`
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

  static async loadCachedDbUserAvatar(user: DbUserInfo): Promise<PixelMap | undefined> {
    return AvatarUtil.loadCachedAvatar({
      baseUrl: user.url,
      userId: user.userinfo.id,
      avatar: user.userinfo.avatar,
      cookie: user.cookie,
      refreshToken: user.refresh_token
    })
  }

  static async preloadCachedDbUserAvatars(users: DbUserInfo[]): Promise<void> {
    for (let index = 0; index < users.length; index++) {
      await AvatarUtil.loadCachedDbUserAvatar(users[index])
    }
  }

  static getDbUserAvatarCacheUri(user: DbUserInfo): string {
    return AvatarUtil.getAvatarCacheUri({
      baseUrl: user.url,
      userId: user.userinfo.id,
      avatar: user.userinfo.avatar,
      cookie: user.cookie,
      refreshToken: user.refresh_token
    })
  }

  static getMemoryCachedDbUserAvatar(user: DbUserInfo): PixelMap | undefined {
    return AvatarUtil.getMemoryCachedAvatar({
      baseUrl: user.url,
      userId: user.userinfo.id,
      avatar: user.userinfo.avatar,
      cookie: user.cookie,
      refreshToken: user.refresh_token
    })
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
    const accountCacheKey = AvatarUtil.getAccountCacheKey(source)
    AvatarUtil.memoryCache.delete(cacheKey)
    AvatarUtil.memoryCache.delete(accountCacheKey)
    AvatarUtil.deleteCache(cacheKey)
    AvatarUtil.deleteCache(accountCacheKey)
  }

  static getAvatarCacheUri(source: AvatarSource): string {
    const cacheUri = AvatarUtil.getCacheUri(AvatarUtil.getCacheKey(source))
    return cacheUri.length > 0 ? cacheUri : AvatarUtil.getCacheUri(AvatarUtil.getAccountCacheKey(source))
  }

  static getMemoryCachedAvatar(source: AvatarSource): PixelMap | undefined {
    const cacheKey = AvatarUtil.getCacheKey(source)
    const memory = AvatarUtil.memoryCache.get(cacheKey)
    return memory ? memory : AvatarUtil.memoryCache.get(AvatarUtil.getAccountCacheKey(source))
  }

  static async loadCachedAvatar(source: AvatarSource): Promise<PixelMap | undefined> {
    const cacheKey = AvatarUtil.getCacheKey(source)
    const cached = await AvatarUtil.loadCachedPixelMap(cacheKey)
    if (cached) {
      return cached
    }
    const accountCacheKey = AvatarUtil.getAccountCacheKey(source)
    if (accountCacheKey === cacheKey) {
      return undefined
    }
    const accountCached = await AvatarUtil.loadCachedPixelMap(accountCacheKey)
    if (accountCached) {
      AvatarUtil.memoryCache.set(cacheKey, accountCached)
    }
    return accountCached
  }

  static async loadAvatar(source: AvatarSource, forceRefresh: boolean = false): Promise<PixelMap | undefined> {
    const cacheKey = AvatarUtil.getCacheKey(source)
    const trace = AvatarUtil.traceStart(`loadAvatar key=${cacheKey} force=${forceRefresh}`)
    if (!forceRefresh) {
      const cached = await AvatarUtil.loadCachedPixelMap(cacheKey)
      if (cached) {
        AvatarUtil.traceEnd(trace, 'memory/file cache hit')
        return cached
      }
    }

    const pendingKey = `${cacheKey}|${forceRefresh ? 'refresh' : 'load'}`
    const pending = AvatarUtil.pendingCache.get(pendingKey)
    if (pending) {
      AvatarUtil.traceEnd(trace, 'pending reused')
      return pending
    }

    const promise = AvatarUtil.loadAvatarFromNetwork(source, cacheKey)
    AvatarUtil.pendingCache.set(pendingKey, promise)
    try {
      const pixelMap = await promise
      AvatarUtil.traceEnd(trace, pixelMap ? 'network loaded' : 'network empty')
      return pixelMap
    } finally {
      AvatarUtil.pendingCache.delete(pendingKey)
    }
  }

  private static async loadAvatarFromNetwork(source: AvatarSource, cacheKey: string): Promise<PixelMap | undefined> {
    const trace = AvatarUtil.traceStart(`loadAvatarFromNetwork key=${cacheKey}`)
    const directUrl = AvatarUtil.resolveAvatarUrl(source, source.avatar)
    if (directUrl.length > 0) {
      try {
        const pixelMap = await AvatarUtil.cacheFetchResult(source, cacheKey,
          await AvatarUtil.requestImage(directUrl, AvatarUtil.buildHeaders(source, directUrl)))
        AvatarUtil.traceEnd(trace, 'direct url')
        return pixelMap
      } catch (err) {
        console.warn(TAG, `load direct avatar failed: ${(err as Error)?.message ?? err}`)
      }
    }

    const baseUrl = AvatarUtil.normalizeBaseUrl(source.baseUrl)
    const userId = AvatarUtil.normalizeText(source.userId)
    if (baseUrl.length === 0 || userId.length === 0) {
      AvatarUtil.traceEnd(trace, 'empty source')
      return undefined
    }

    if (AvatarUtil.isV4Source(source)) {
      try {
        const directApiUrl = `${baseUrl}/api/v4/user/avatar/${encodeURIComponent(userId)}?nocache=true`
        const apiAvatar = await AvatarUtil.requestAvatarFromEndpoint(source, directApiUrl)
        if (apiAvatar) {
          const pixelMap = await AvatarUtil.cacheFetchResult(source, cacheKey, apiAvatar)
          AvatarUtil.traceEnd(trace, 'v4 endpoint')
          return pixelMap
        }
      } catch (err) {
        console.warn(TAG, `load v4 avatar endpoint failed: ${(err as Error)?.message ?? err}`)
      }

      try {
        const avatarUrl = await AvatarUtil.requestV4AvatarUrl(source)
        const resolved = AvatarUtil.resolveAvatarUrl(source, avatarUrl)
        if (resolved.length > 0) {
          const pixelMap = await AvatarUtil.cacheFetchResult(source, cacheKey,
            await AvatarUtil.requestImage(resolved, AvatarUtil.buildHeaders(source, resolved)))
          AvatarUtil.traceEnd(trace, 'v4 resolved url')
          return pixelMap
        }
      } catch (err) {
        console.warn(TAG, `load v4 avatar failed: ${(err as Error)?.message ?? err}`)
      }
      AvatarUtil.traceEnd(trace, 'v4 empty')
      return undefined
    }

    try {
      const url = `${baseUrl}/api/v3/user/avatar/${encodeURIComponent(userId)}/l`
      const avatar = await AvatarUtil.requestAvatarFromEndpoint(source, url)
      const pixelMap = avatar ? await AvatarUtil.cacheFetchResult(source, cacheKey, avatar) : undefined
      AvatarUtil.traceEnd(trace, pixelMap ? 'v3 endpoint' : 'v3 empty')
      return pixelMap
    } catch (err) {
      console.warn(TAG, `load v3 avatar failed: ${(err as Error)?.message ?? err}`)
      AvatarUtil.traceEnd(trace, 'v3 failed')
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
    const trace = AvatarUtil.traceStart(`requestImage ${AvatarUtil.safeUrl(url)}`)
    const data = await AvatarUtil.requestArrayBuffer(url, headers)
    if (!AvatarUtil.isImageData(data)) {
      throw new Error('avatar response is not image data')
    }
    const pixelMap = await AvatarUtil.createPixelMap(data)
    AvatarUtil.traceEnd(trace, `bytes=${data.byteLength}`)
    return {
      pixelMap,
      data
    }
  }

  private static async requestAvatarFromEndpoint(source: AvatarSource, url: string): Promise<AvatarFetchResult | undefined> {
    const trace = AvatarUtil.traceStart(`requestAvatarEndpoint ${AvatarUtil.safeUrl(url)}`)
    const data = await AvatarUtil.requestArrayBuffer(url, AvatarUtil.buildHeaders(source, url))
    if (AvatarUtil.isImageData(data)) {
      const pixelMap = await AvatarUtil.createPixelMap(data)
      AvatarUtil.traceEnd(trace, `image bytes=${data.byteLength}`)
      return {
        pixelMap,
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
    const result = await AvatarUtil.requestImage(resolved, AvatarUtil.buildHeaders(source, resolved))
    AvatarUtil.traceEnd(trace, 'resolved text')
    return result
  }

  private static async createPixelMap(data: ArrayBuffer): Promise<PixelMap> {
    const trace = AvatarUtil.traceStart(`createPixelMap bytes=${data.byteLength}`)
    const imageSource: image.ImageSource = image.createImageSource(data)
    try {
      const pixelMap = await imageSource.createPixelMap({
        desiredSize: {
          width: CloudAvatarDecodeSize.SMALL,
          height: CloudAvatarDecodeSize.SMALL
        }
      })
      AvatarUtil.traceEnd(trace)
      return pixelMap
    } finally {
      imageSource.release()
    }
  }

  private static async requestArrayBuffer(url: string, headers: HeaderMap): Promise<ArrayBuffer> {
    const trace = AvatarUtil.traceStart(`http GET ${AvatarUtil.safeUrl(url)}`)
    const req = http.createHttp()
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: headers
      })
      if (resp.responseCode === Constant.HTTP_STATUS_OK) {
        AvatarUtil.traceEnd(trace, `status=200`)
        return resp.result as ArrayBuffer
      }
      AvatarUtil.traceEnd(trace, `status=${resp.responseCode}`)
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

  private static async cacheFetchResult(source: AvatarSource, cacheKey: string,
    result: AvatarFetchResult): Promise<PixelMap> {
    const trace = AvatarUtil.traceStart(`cacheFetchResult key=${cacheKey}`)
    const accountCacheKey = AvatarUtil.getAccountCacheKey(source)
    AvatarUtil.memoryCache.set(cacheKey, result.pixelMap)
    AvatarUtil.memoryCache.set(accountCacheKey, result.pixelMap)
    await AvatarUtil.writeCache(cacheKey, result.data)
    if (accountCacheKey !== cacheKey) {
      await AvatarUtil.writeCache(accountCacheKey, result.data)
    }
    AvatarUtil.traceEnd(trace, `bytes=${result.data.byteLength}`)
    return result.pixelMap
  }

  private static async loadCachedPixelMap(cacheKey: string): Promise<PixelMap | undefined> {
    const trace = AvatarUtil.traceStart(`loadCachedPixelMap key=${cacheKey}`)
    const memory = AvatarUtil.memoryCache.get(cacheKey)
    if (memory) {
      AvatarUtil.traceEnd(trace, 'memory')
      return memory
    }

    const data = AvatarUtil.readCache(cacheKey)
    if (!data || !AvatarUtil.isImageData(data)) {
      AvatarUtil.traceEnd(trace, 'miss')
      return undefined
    }

    try {
      const pixelMap = await AvatarUtil.createPixelMap(data)
      AvatarUtil.memoryCache.set(cacheKey, pixelMap)
      AvatarUtil.traceEnd(trace, `file bytes=${data.byteLength}`)
      return pixelMap
    } catch (err) {
      console.warn(TAG, `decode cached avatar failed: ${(err as Error)?.message ?? err}`)
      AvatarUtil.deleteCache(cacheKey)
      AvatarUtil.traceEnd(trace, 'decode failed')
      return undefined
    }
  }

  private static writeCache(cacheKey: string, data: ArrayBuffer): Promise<void> {
    return new Promise<void>((resolve) => {
      const path = AvatarUtil.getCachePath(cacheKey, AvatarUtil.getImageExtension(data))
      const tempPath = `${path}.tmp_${Date.now()}`
      if (path.length === 0 || data.byteLength === 0) {
        resolve()
        return
      }

      let target: fs.File | undefined = undefined
      let writeOk = false
      try {
        AvatarUtil.ensureCacheDir()
        AvatarUtil.deleteCachePath(tempPath)
        target = fs.openSync(tempPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
        fs.writeSync(target.fd, data, { length: data.byteLength })
        writeOk = true
      } catch (err) {
        console.warn(TAG, `write avatar cache failed: ${(err as Error)?.message ?? err}`)
      } finally {
        if (target) {
          try {
            fs.closeSync(target)
          } catch (_) {
          }
        }
        try {
          if (writeOk && AvatarUtil.cachePathExists(tempPath)) {
            fs.moveFileSync(tempPath, path, 0)
          } else if (!writeOk) {
            AvatarUtil.deleteCachePath(tempPath)
          }
        } catch (err) {
          AvatarUtil.deleteCachePath(tempPath)
          console.warn(TAG, `replace avatar cache failed: ${(err as Error)?.message ?? err}`)
        }
        resolve()
      }
    })
  }

  private static readCache(cacheKey: string): ArrayBuffer | undefined {
    const trace = AvatarUtil.traceStart(`readCache key=${cacheKey}`)
    const path = AvatarUtil.getExistingCachePath(cacheKey)
    if (path.length === 0) {
      AvatarUtil.traceEnd(trace, 'path miss')
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
      AvatarUtil.traceEnd(trace, `path=${AvatarUtil.shortPath(path)} size=${size} read=${readLen}`)
      return readLen > 0 ? buffer.slice(0, readLen) : undefined
    } catch (_) {
      AvatarUtil.traceEnd(trace, 'failed')
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
    AvatarUtil.getCacheExtensions().forEach((extension: string) => {
      AvatarUtil.deleteCachePath(AvatarUtil.getCachePath(cacheKey, extension))
      AvatarUtil.deleteCachePath(AvatarUtil.getLegacyCachePath(cacheKey, extension))
    })
  }

  private static deleteCachePath(path: string): void {
    if (path.length > 0) {
      try {
        fs.unlinkSync(path)
      } catch (_) {
      }
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

  private static getCachePath(cacheKey: string, extension: string = 'img'): string {
    if (AvatarUtil.cacheDir.length === 0) {
      return ''
    }
    return `${AvatarUtil.cacheDir}/avatar_${cacheKey}.${extension}`
  }

  private static getLegacyCachePath(cacheKey: string, extension: string = 'img'): string {
    if (AvatarUtil.legacyCacheDir.length === 0) {
      return ''
    }
    return `${AvatarUtil.legacyCacheDir}/avatar_${cacheKey}.${extension}`
  }

  private static getExistingCachePath(cacheKey: string): string {
    const extensions = AvatarUtil.getCacheExtensions()
    let bestPath = ''
    let bestMtime = -1
    for (let index = 0; index < extensions.length; index++) {
      const path = AvatarUtil.getCachePath(cacheKey, extensions[index])
      if (AvatarUtil.cachePathExists(path)) {
        const resolvedPath = extensions[index] === 'img' ? AvatarUtil.migrateLegacyExtensionCache(path, cacheKey) : path
        const mtime = AvatarUtil.getCacheMtime(resolvedPath)
        if (mtime >= bestMtime) {
          bestMtime = mtime
          bestPath = resolvedPath
        }
      }
    }
    for (let index = 0; index < extensions.length; index++) {
      const legacyPath = AvatarUtil.getLegacyCachePath(cacheKey, extensions[index])
      if (AvatarUtil.cachePathExists(legacyPath)) {
        const resolvedPath = extensions[index] === 'img' ? AvatarUtil.migrateLegacyExtensionCache(legacyPath, cacheKey) : legacyPath
        const mtime = AvatarUtil.getCacheMtime(resolvedPath)
        if (mtime >= bestMtime) {
          bestMtime = mtime
          bestPath = resolvedPath
        }
      }
    }
    return bestPath
  }

  private static getCacheUri(cacheKey: string): string {
    const path = AvatarUtil.getExistingCachePath(cacheKey)
    if (path.length === 0) {
      AvatarUtil.traceLog(`avatar cache uri miss key=${cacheKey}`)
      return ''
    }
    const uri = fileUri.getUriFromPath(path)
    AvatarUtil.traceLog(`avatar cache uri hit key=${cacheKey} path=${AvatarUtil.shortPath(path)}`)
    return uri
  }

  private static cachePathExists(path: string): boolean {
    if (path.length === 0) {
      return false
    }
    try {
      return fs.statSync(path).size > 0
    } catch (_) {
      return false
    }
  }

  private static getCacheMtime(path: string): number {
    if (path.length === 0) {
      return -1
    }
    try {
      return fs.statSync(path).mtime
    } catch (_) {
      return -1
    }
  }

  private static migrateLegacyExtensionCache(path: string, cacheKey: string): string {
    const data = AvatarUtil.readCachePath(path)
    if (!data || !AvatarUtil.isImageData(data)) {
      return path
    }
    const extension = AvatarUtil.getImageExtension(data)
    if (extension === 'img') {
      return path
    }
    const targetPath = AvatarUtil.getCachePath(cacheKey, extension)
    if (targetPath.length === 0 || targetPath === path) {
      return path
    }
    if (AvatarUtil.cachePathExists(targetPath)) {
      return targetPath
    }
    if (AvatarUtil.writeCachePath(targetPath, data)) {
      return targetPath
    }
    return path
  }

  private static readCachePath(path: string): ArrayBuffer | undefined {
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

  private static writeCachePath(path: string, data: ArrayBuffer): boolean {
    let target: fs.File | undefined = undefined
    try {
      AvatarUtil.ensureCacheDir()
      target = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(target.fd, data, { length: data.byteLength })
      return true
    } catch (_) {
      return false
    } finally {
      if (target) {
        try {
          fs.closeSync(target)
        } catch (_) {
        }
      }
    }
  }

  private static getCacheKey(source: AvatarSource): string {
    const baseUrl = AvatarUtil.normalizeBaseUrl(source.baseUrl)
    const userId = AvatarUtil.normalizeText(source.userId)
    const avatar = AvatarUtil.normalizeText(source.avatar)
    const raw = `${baseUrl}|${userId}|${avatar}`
    return `${raw.length}_${AvatarUtil.hashText(raw)}`
  }

  private static getAccountCacheKey(source: AvatarSource): string {
    const baseUrl = AvatarUtil.normalizeBaseUrl(source.baseUrl)
    const userId = AvatarUtil.normalizeText(source.userId)
    const raw = `${baseUrl}|${userId}`
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
    return AvatarUtil.getImageExtension(data) !== 'img'
  }

  private static getImageExtension(data: ArrayBuffer): string {
    const bytes = new Uint8Array(data)
    if (bytes.length < 12) {
      return 'img'
    }
    const isJpeg = bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF
    const isPng = bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47
    const isGif = bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46
    const isWebp = bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
    if (isJpeg) {
      return 'jpg'
    }
    if (isPng) {
      return 'png'
    }
    if (isGif) {
      return 'gif'
    }
    if (isWebp) {
      return 'webp'
    }
    return 'img'
  }

  private static getCacheExtensions(): string[] {
    return ['jpg', 'png', 'webp', 'gif', 'img']
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

  private static traceStart(label: string): number {
    if (!AVATAR_TRACE_ENABLED) {
      return 0
    }
    const now = Date.now()
    console.info(TAG, `[avatar-trace] start ${label} at=${now}`)
    return now
  }

  private static traceEnd(start: number, label: string = ''): void {
    if (!AVATAR_TRACE_ENABLED || start <= 0) {
      return
    }
    console.info(TAG, `[avatar-trace] end ${label} cost=${Date.now() - start}ms`)
  }

  private static traceLog(message: string): void {
    if (AVATAR_TRACE_ENABLED) {
      console.info(TAG, message)
    }
  }

  private static safeUrl(url: string): string {
    if (!url || url.length === 0) {
      return ''
    }
    const queryIndex = url.indexOf('?')
    const cleanUrl = queryIndex >= 0 ? url.substring(0, queryIndex) : url
    return cleanUrl.length > 96 ? `${cleanUrl.substring(0, 96)}...` : cleanUrl
  }

  private static shortPath(path: string): string {
    if (!path || path.length <= 80) {
      return path
    }
    return `...${path.substring(path.length - 80)}`
  }
}

class CloudAvatarDecodeSize {
  static readonly SMALL: number = 160
  static readonly TEXT_PREVIEW: number = 4096
}
