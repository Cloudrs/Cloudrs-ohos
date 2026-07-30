import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { ObjectItem } from "../components/ObjectItem";
import { FileMenuType, ShowType } from "../model/MenuModel";
import { DirectoryInfo, ObjectInfo } from "../model/net/ApiTypes";
import { FileSearchParam, ImagePreview, PreviewFile, VideoPreview } from "../model/Params";
import { CommonUtil, FileType } from "../utils/CommonUtil";
import { CloudRouter } from "../utils/CloudRouter";
import { TextPreviewEntry } from "../utils/TextPreviewEntry";
import { showToast } from "../utils/ToastUtil";
import { CloudApi } from "../model/net/CloudApi";
import { ObjectSrc } from "../model/net/ObjectParam";
import { showCloudConfirmDialog } from "../utils/CloudDialogUtil";
import AppLogger from "../utils/AppLogger";
import UserPreferences from "../model/UserPreferences";
import { FileThumbSourceCache } from "../utils/FileThumbSourceCache";
import { FileGridLayout } from "../utils/FileGridLayout";
import { DividerShowType, HdsNavigation, HdsNavigationTitleMode, hdsEffect, hdsMaterial } from "@kit.UIDesignKit";

const TAG = 'FileSearchPage'
const GLOBAL_SEARCH_CONCURRENCY = 4
const SEARCH_HISTORY_MAX_COUNT = 10
const LEGACY_REGEX_HISTORY_PREFIX = '__cloudrs_regex__:'
const SEARCH_THUMB_MAX_CONCURRENT = 4
const SEARCH_THUMB_QUEUE_DELAY_MS = 100
const SEARCH_THUMB_QUEUE_MAX = 64

enum FileSearchScope {
  CURRENT_DIRECTORY,
  ALL_FILES
}

@Component
export struct FileSearchPage {
  routeParam?: FileSearchParam
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0
  @StorageProp(Constant.ACTIVE_ACCOUNT_SCOPE) accountScope: string = ''
  @Provide thumbImage: Map<string, PixelMap> = new Map<string, PixelMap>()
  @Provide thumbSource: Map<string, string> = new Map<string, string>()
  @State searchKeyword: string = ''
  @State activeSearchKeyword: string = ''
  @State results: ObjectInfo[] = []
  @State searchScope: FileSearchScope = FileSearchScope.CURRENT_DIRECTORY
  @State searchHistory: string[] = []
  @State searchHistoryExpanded: boolean = false
  @State searchHistoryContentWidth: number = 0
  @State searchHistoryViewportWidth: number = 0
  @State gridWidth: number = 0
  @State isLoadingGlobalObjects: boolean = false
  @State isMultiSelectMode: boolean = false
  @State selectedObjects: ObjectInfo[] = []
  private currentObjects: ObjectInfo[] = []
  private globalObjects: ObjectInfo[] = []
  private globalObjectsLoaded: boolean = false
  private loadGeneration: number = 0
  private deletedObjectIds: Set<string> = new Set<string>()
  private deletedDirectoryPaths: Set<string> = new Set<string>()
  private thumbLoadingIds: Set<string> = new Set<string>()
  private thumbFailedIds: Set<string> = new Set<string>()
  private thumbQueue: ObjectInfo[] = []
  private activeThumbLoads: number = 0
  private thumbQueueTimer: number = -1
  private isPageActive: boolean = false

  aboutToAppear(): void {
    this.isPageActive = true
    this.currentObjects = this.routeParam?.objects ?? []
    if (this.globalObjects.length === 0) {
      this.globalObjects = this.currentObjects.slice()
    }
    this.thumbImage = this.routeParam?.thumbImage ?? new Map<string, PixelMap>()
    this.restoreThumbSources()
    this.loadSearchHistory()
    this.applySearch()
    if (this.thumbQueue.length > 0) {
      this.scheduleThumbQueue()
    }
  }

  aboutToDisappear(): void {
    this.isPageActive = false
    this.loadGeneration += 1
    this.isLoadingGlobalObjects = false
    if (this.thumbQueueTimer >= 0) {
      clearTimeout(this.thumbQueueTimer)
      this.thumbQueueTimer = -1
    }
  }

  private getThumbScopeKey(): string {
    return this.accountScope.length > 0 ? `${this.accountScope}|` : ''
  }

  private getThumbCacheKey(item: ObjectInfo): string {
    return `${this.getThumbScopeKey()}${item.id}`
  }

  private restoreThumbSources(): void {
    const restored = new Map<string, string>()
    this.routeParam?.thumbSource?.forEach((source: string, id: string) => {
      restored.set(id, source)
    })
    const scope = this.getThumbScopeKey()
    if (scope.length > 0) {
      FileThumbSourceCache.snapshot(scope).forEach((source: string, id: string) => {
        restored.set(id, source)
      })
    }
    this.thumbSource = restored
  }

  private getThumbSourceData(id: string): string {
    return this.thumbSource.get(id) ?? ''
  }

  private setThumbSourceData(item: ObjectInfo, source: string): void {
    if (source.length === 0) {
      return
    }
    const scope = this.getThumbScopeKey()
    if (scope.length > 0) {
      FileThumbSourceCache.set(this.getThumbCacheKey(item), source)
    }
    const updated = new Map<string, string>(this.thumbSource)
    updated.set(item.id, source)
    this.thumbSource = updated
  }

  private requestThumb(item: ObjectInfo): void {
    if (!this.isPageActive || !item.thumb || this.thumbImage.has(item.id) ||
      this.getThumbSourceData(item.id).length > 0) {
      return
    }
    const scope = this.getThumbScopeKey()
    const cachedSource = scope.length > 0 ? FileThumbSourceCache.get(this.getThumbCacheKey(item)) : ''
    if (cachedSource.length > 0) {
      this.setThumbSourceData(item, cachedSource)
      return
    }
    if (this.thumbLoadingIds.has(item.id) || this.thumbFailedIds.has(item.id) ||
      this.thumbQueue.some((queued: ObjectInfo) => queued.id === item.id)) {
      return
    }
    this.thumbQueue.push(item)
    if (this.thumbQueue.length > SEARCH_THUMB_QUEUE_MAX) {
      this.thumbQueue.shift()
    }
    this.scheduleThumbQueue()
  }

  private scheduleThumbQueue(): void {
    if (!this.isPageActive || this.thumbQueueTimer >= 0) {
      return
    }
    this.thumbQueueTimer = setTimeout(() => {
      this.thumbQueueTimer = -1
      this.processThumbQueue()
    }, SEARCH_THUMB_QUEUE_DELAY_MS)
  }

  private processThumbQueue(): void {
    if (!this.isPageActive) {
      return
    }
    while (this.activeThumbLoads < SEARCH_THUMB_MAX_CONCURRENT && this.thumbQueue.length > 0) {
      const item = this.thumbQueue.pop()
      if (!item || this.getThumbSourceData(item.id).length > 0 ||
        this.thumbLoadingIds.has(item.id)) {
        continue
      }
      this.activeThumbLoads += 1
      this.thumbLoadingIds.add(item.id)
      CloudApi.getThumb(item.id, {
        onSuccess: (source: string) => {
          if (source.length > 0) {
            if (this.isPageActive) {
              this.setThumbSourceData(item, source)
            } else {
              const scope = this.getThumbScopeKey()
              if (scope.length > 0) {
                FileThumbSourceCache.set(this.getThumbCacheKey(item), source)
              }
            }
          }
          this.finishThumbLoad(item)
        },
        onFailure: (msg: string) => {
          this.thumbFailedIds.add(item.id)
          AppLogger.warn(TAG, `load search thumbnail failed id=${item.id}, msg=${msg}`)
          this.finishThumbLoad(item)
        }
      })
    }
  }

  private finishThumbLoad(item: ObjectInfo): void {
    this.thumbLoadingIds.delete(item.id)
    this.activeThumbLoads = Math.max(0, this.activeThumbLoads - 1)
    if (this.isPageActive) {
      this.processThumbQueue()
    }
  }

  private getTopInset(): number {
    return CloudThemeToken.getSafeTopInset(this.topRectHeight)
  }

  private getTitleBarHeight(): number {
    return this.getTopInset() + CloudThemeToken.rowHeight5xl
  }

  private getShowType(): ShowType {
    return this.routeParam?.showType ?? ShowType.SHOW_LIST
  }

  private getResultDirs(): ObjectInfo[] {
    return this.results.filter((item: ObjectInfo) => item.type === Constant.OBJECT_DIR_TYPE)
  }

  private getResultFiles(): ObjectInfo[] {
    return this.results.filter((item: ObjectInfo) => item.type !== Constant.OBJECT_DIR_TYPE)
  }

  private getGridColumns(): number {
    return FileGridLayout.getColumns(this.gridWidth, this.getShowType())
  }

  private getGridColumnsTemplate(): string {
    return FileGridLayout.getColumnsTemplate(this.gridWidth, this.getShowType())
  }

  private getFolderPaddingItems(): number[] {
    const count = FileGridLayout.getPaddingCount(
      this.getResultDirs().length, this.gridWidth, this.getShowType())
    const items: number[] = []
    for (let index = 0; index < count; index++) {
      items.push(index)
    }
    return items
  }

  private getSearchFieldEffect(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: CloudThemeToken.onPrimary,
          intensity: CloudThemeToken.hdsIconButtonLightIntensity,
          height: CloudThemeToken.hdsIconButtonLightHeight,
          bloom: CloudThemeToken.hdsIconButtonLightBloom
        }
      })
      .buildEffect()
  }

  private applySearch(): void {
    const keyword = this.activeSearchKeyword.trim()
    if (keyword.length === CloudThemeToken.zero) {
      this.results = []
      return
    }
    const source = this.searchScope === FileSearchScope.ALL_FILES ?
      this.globalObjects : this.currentObjects
    let expression: RegExp | null = null
    try {
      expression = this.createPatternExpression(keyword)
    } catch (_) {
      this.results = []
      return
    }
    const normalizedKeyword = keyword.toLowerCase()
    this.results = source.filter((item: ObjectInfo) => {
      if (this.isDeletedObject(item)) {
        return false
      }
      return expression !== null ? expression.test(item.name) :
        item.name.toLowerCase().includes(normalizedKeyword)
    })
    if (this.isMultiSelectMode) {
      const visibleIds = new Set<string>(this.results.map((item: ObjectInfo) => item.id))
      this.selectedObjects = this.selectedObjects.filter((item: ObjectInfo) => visibleIds.has(item.id))
    }
  }

  private getSearchHistoryKey(): string {
    return this.accountScope.length > 0 ?
      `${Constant.FILE_SEARCH_HISTORY}:${this.accountScope}` : Constant.FILE_SEARCH_HISTORY
  }

  private loadSearchHistory(): void {
    const raw = UserPreferences.getSync(
      Constant.USER_PREFERENCES, this.getSearchHistoryKey(), '[]') as string
    try {
      const parsed = JSON.parse(raw) as string[]
      this.searchHistory = parsed
        .filter((item: string) => item.trim().length > 0)
        .map((item: string) => this.getHistoryKeyword(item))
        .slice(0, SEARCH_HISTORY_MAX_COUNT)
    } catch (err) {
      AppLogger.warn(TAG, `parse search history failed: ${(err as Error)?.message ?? err}`)
      this.searchHistory = []
    }
  }

  private saveSearchHistory(): void {
    UserPreferences.putSync(
      Constant.USER_PREFERENCES, this.getSearchHistoryKey(), JSON.stringify(this.searchHistory))
  }

  private recordSearchHistory(keywordValue?: string): void {
    const keyword = (keywordValue ?? this.activeSearchKeyword).trim()
    if (keyword.length === 0) {
      return
    }
    const normalized = keyword.toLowerCase()
    this.searchHistory = [keyword]
      .concat(this.searchHistory.filter((item: string) => item.toLowerCase() !== normalized))
      .slice(0, SEARCH_HISTORY_MAX_COUNT)
    this.searchHistoryExpanded = false
    this.searchHistoryContentWidth = 0
    this.searchHistoryViewportWidth = 0
    this.saveSearchHistory()
  }

  private clearSearchHistory(): void {
    this.searchHistory = []
    this.searchHistoryExpanded = false
    this.searchHistoryContentWidth = 0
    this.searchHistoryViewportWidth = 0
    UserPreferences.deleteSync(Constant.USER_PREFERENCES, this.getSearchHistoryKey())
  }

  private getHistoryKeyword(value: string): string {
    return value.startsWith(LEGACY_REGEX_HISTORY_PREFIX) ?
      value.substring(LEGACY_REGEX_HISTORY_PREFIX.length) : value
  }

  private useSearchHistory(value: string): void {
    this.searchKeyword = this.getHistoryKeyword(value)
    this.executeSearch()
  }

  private shouldShowSearchHistoryToggle(): boolean {
    return this.searchHistoryContentWidth >
      this.searchHistoryViewportWidth + CloudThemeToken.spacingTiny
  }

  private toggleSearchHistory(): void {
    this.getUIContext().animateTo({
      duration: CloudThemeToken.defaultAnimationDuration,
      curve: Curve.EaseOut
    }, () => {
      this.searchHistoryExpanded = !this.searchHistoryExpanded
    })
  }

  private executeSearch(): void {
    const keyword = this.searchKeyword.trim()
    if (keyword.length === 0) {
      this.activeSearchKeyword = ''
      this.results = []
      this.exitMultiSelectMode()
      if (this.isLoadingGlobalObjects) {
        this.loadGeneration += 1
        this.isLoadingGlobalObjects = false
        this.globalObjectsLoaded = false
        this.globalObjects = this.currentObjects.slice()
      }
      return
    }
    if (this.isPatternKeyword(keyword)) {
      try {
        this.createPatternExpression(keyword)
      } catch (_) {
        showToast('搜索表达式格式不正确')
        return
      }
    }
    this.exitMultiSelectMode()
    this.activeSearchKeyword = keyword
    this.recordSearchHistory(keyword)
    this.startGlobalSearch()
    this.applySearch()
  }

  private changeSearchScope(scope: FileSearchScope): void {
    if (this.searchScope === scope) {
      return
    }
    this.exitMultiSelectMode()
    this.searchScope = scope
    if (scope === FileSearchScope.CURRENT_DIRECTORY) {
      this.loadGeneration += 1
      this.isLoadingGlobalObjects = false
    } else {
      this.startGlobalSearch()
    }
    this.applySearch()
  }

  private startGlobalSearch(): void {
    if (this.searchScope !== FileSearchScope.ALL_FILES ||
      this.activeSearchKeyword.trim().length === 0) {
      return
    }
    if (this.isPatternKeyword(this.activeSearchKeyword)) {
      this.ensureGlobalObjectsLoaded()
      return
    }
    this.loadServerSearch()
  }

  private isWildcardKeyword(keyword: string): boolean {
    return keyword.includes('*') || keyword.includes('?')
  }

  private isRegexKeyword(keyword: string): boolean {
    const slashWrapped = keyword.length > 2 && keyword.startsWith('/') &&
      keyword.lastIndexOf('/') > 0
    return slashWrapped || keyword.startsWith('^') || keyword.endsWith('$') ||
      keyword.includes('\\')
  }

  private isPatternKeyword(keyword: string): boolean {
    return this.isWildcardKeyword(keyword) || this.isRegexKeyword(keyword)
  }

  private createPatternExpression(keyword: string): RegExp | null {
    if (this.isRegexKeyword(keyword)) {
      if (keyword.startsWith('/') && keyword.lastIndexOf('/') > 0) {
        return new RegExp(keyword.substring(1, keyword.lastIndexOf('/')), 'i')
      }
      return new RegExp(keyword, 'i')
    }
    if (!this.isWildcardKeyword(keyword)) {
      return null
    }
    let pattern = '^'
    for (let index = 0; index < keyword.length; index++) {
      const char = keyword[index]
      if (char === '*') {
        pattern += '.*'
      } else if (char === '?') {
        pattern += '.'
      } else if ('\\^$+.|(){}[]'.includes(char)) {
        pattern += `\\${char}`
      } else {
        pattern += char
      }
    }
    return new RegExp(`${pattern}$`, 'i')
  }

  private ensureGlobalObjectsLoaded(): void {
    if (this.searchScope !== FileSearchScope.ALL_FILES ||
      this.activeSearchKeyword.trim().length === 0 ||
      this.globalObjectsLoaded ||
      this.isLoadingGlobalObjects) {
      return
    }
    this.loadGlobalObjects()
  }

  private loadServerSearch(): void {
    const generation = ++this.loadGeneration
    const keyword = this.activeSearchKeyword
    this.isLoadingGlobalObjects = true
    this.globalObjects = []
    this.results = []
    CloudApi.searchFiles(keyword, '/', {
      onSuccess: (objects: ObjectInfo[]) => {
        if (generation !== this.loadGeneration) {
          return
        }
        this.isLoadingGlobalObjects = false
        this.globalObjects = objects
        this.applySearch()
      },
      onFailure: (msg: string) => {
        if (generation !== this.loadGeneration) {
          return
        }
        AppLogger.warn(TAG, `server search unavailable, fallback to traversal: ${msg}`)
        this.isLoadingGlobalObjects = false
        this.globalObjectsLoaded = false
        this.globalObjects = this.currentObjects.slice()
        showToast('服务器搜索不可用，已切换兼容搜索')
        this.loadGlobalObjects()
      }
    })
  }

  private isDeletedObject(item: ObjectInfo): boolean {
    if (this.deletedObjectIds.has(item.id)) {
      return true
    }
    let deletedByParent = false
    this.deletedDirectoryPaths.forEach((path: string) => {
      if (item.path === path || item.path.startsWith(`${path}/`)) {
        deletedByParent = true
      }
    })
    return deletedByParent
  }

  /**
   * 搜索页不能只拿进入页面时的当前目录快照。这里从根目录分批遍历文件夹，
   * 使用 CloudApi 的协议适配层，因此 Cloudreve V3/V4 都能得到一致的全局结果。
   */
  private async loadGlobalObjects(): Promise<void> {
    const generation = ++this.loadGeneration
    this.isLoadingGlobalObjects = true
    const pendingPaths: string[] = ['/']
    const visitedPaths: Set<string> = new Set<string>()
    const objectsById: Map<string, ObjectInfo> = new Map<string, ObjectInfo>()
    this.currentObjects.forEach((item: ObjectInfo) => objectsById.set(item.id, item))
    let failedDirectoryCount = 0

    while (pendingPaths.length > 0 && generation === this.loadGeneration) {
      const batch: string[] = []
      while (batch.length < GLOBAL_SEARCH_CONCURRENCY && pendingPaths.length > 0) {
        const path = pendingPaths.shift()
        if (path !== undefined && !visitedPaths.has(path)) {
          visitedPaths.add(path)
          batch.push(path)
        }
      }
      if (batch.length === 0) {
        continue
      }

      const directories = await Promise.all(batch.map((path: string) => this.loadDirectory(path)))
      if (generation !== this.loadGeneration) {
        return
      }
      directories.forEach((directory: DirectoryInfo | null) => {
        if (directory === null) {
          failedDirectoryCount += 1
          return
        }
        directory.objects.forEach((item: ObjectInfo) => {
          if (this.isDeletedObject(item)) {
            return
          }
          objectsById.set(item.id, item)
          if (item.type === Constant.OBJECT_DIR_TYPE) {
            const childPath = CloudApi.getTotalPath(item)
            if (!visitedPaths.has(childPath)) {
              pendingPaths.push(childPath)
            }
          }
        })
      })
      this.globalObjects = Array.from(objectsById.values())
      this.applySearch()
    }

    if (generation !== this.loadGeneration) {
      return
    }
    this.isLoadingGlobalObjects = false
    this.globalObjectsLoaded = true
    if (failedDirectoryCount > 0) {
      AppLogger.warn(TAG, `global search skipped ${failedDirectoryCount} directories`)
      showToast(`有 ${failedDirectoryCount} 个目录无法读取，已展示其余搜索结果`)
    }
  }

  private loadDirectory(path: string): Promise<DirectoryInfo | null> {
    return new Promise<DirectoryInfo | null>((resolve) => {
      CloudApi.getFilesInfo(path, {
        onSuccess: (data: DirectoryInfo) => resolve(data),
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `load search directory failed path=${path}, msg=${msg}`)
          resolve(null)
        }
      })
    })
  }

  private dispatchOpenResult(item: ObjectInfo): void {
    this.recordSearchHistory(this.activeSearchKeyword)
    if (item.type === Constant.OBJECT_DIR_TYPE && this.routeParam?.onOpen) {
      CloudRouter.pop()
      this.routeParam.onOpen(item)
      return
    }
    this.openResult(item)
  }

  private dispatchMenuClick(item: ObjectInfo, type: FileMenuType): void {
    this.recordSearchHistory(this.activeSearchKeyword)
    if (type === FileMenuType.MULTI_SELECT) {
      this.enterMultiSelectMode(item)
      return
    }
    if (type === FileMenuType.DELETE) {
      this.confirmDelete([item])
      return
    }
    if (type === FileMenuType.PREVIEW) {
      this.openResult(item)
      return
    }
    if (type === FileMenuType.DIR_ENTER && this.routeParam?.onOpen) {
      CloudRouter.pop()
      this.routeParam.onOpen(item)
      return
    }
    if (this.routeParam?.onMenuClick) {
      this.routeParam.onMenuClick(item, type)
      return
    }
    showToast('请返回文件页操作')
  }

  private enterMultiSelectMode(item: ObjectInfo): void {
    this.isMultiSelectMode = true
    this.selectedObjects = [item]
  }

  private exitMultiSelectMode(): void {
    this.isMultiSelectMode = false
    this.selectedObjects = []
  }

  private isObjectSelected(item: ObjectInfo): boolean {
    return this.selectedObjects.some((selected: ObjectInfo) => selected.id === item.id)
  }

  private toggleObjectSelection(item: ObjectInfo): void {
    if (this.isObjectSelected(item)) {
      this.selectedObjects =
        this.selectedObjects.filter((selected: ObjectInfo) => selected.id !== item.id)
    } else {
      this.selectedObjects = this.selectedObjects.concat([item])
    }
  }

  private toggleSelectAll(): void {
    if (this.areAllResultsSelected()) {
      this.selectedObjects = []
    } else {
      this.selectedObjects = this.results.slice()
    }
  }

  private areAllResultsSelected(): boolean {
    return this.results.length > 0 &&
      this.results.every((item: ObjectInfo) => this.isObjectSelected(item))
  }

  private confirmDelete(items: ObjectInfo[]): void {
    if (items.length === 0) {
      return
    }
    showCloudConfirmDialog(this.getUIContext(), {
      title: $r('app.string.delete_confirm'),
      message: items.length === 1 ? items[0].name : `将删除 ${items.length} 个项目`,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        const src = new ObjectSrc()
        items.forEach((item: ObjectInfo) => {
          if (item.type === Constant.OBJECT_DIR_TYPE) {
            src.dirs.push(item.id)
          } else {
            src.items.push(item.id)
          }
        })
        CloudApi.deleteObjects(src, {
          onSuccess: () => {
            const deletedIds = new Set<string>(items.map((item: ObjectInfo) => item.id))
            items.forEach((item: ObjectInfo) => {
              this.deletedObjectIds.add(item.id)
              if (item.type === Constant.OBJECT_DIR_TYPE) {
                this.deletedDirectoryPaths.add(CloudApi.getTotalPath(item))
              }
            })
            this.currentObjects =
              this.currentObjects.filter((item: ObjectInfo) => !deletedIds.has(item.id))
            this.globalObjects =
              this.globalObjects.filter((item: ObjectInfo) => !deletedIds.has(item.id))
            this.selectedObjects =
              this.selectedObjects.filter((item: ObjectInfo) => !deletedIds.has(item.id))
            this.applySearch()
            if (this.selectedObjects.length === 0) {
              this.exitMultiSelectMode()
            }
            this.routeParam?.onChanged?.()
            showToast($r('app.string.delete_success'))
          },
          onFailure: (msg: string) => {
            AppLogger.error(TAG, `delete search results failed: ${msg}`)
            showToast(msg)
          }
        })
      }
    })
  }

  private openResult(item: ObjectInfo): void {
    if (item.type === Constant.OBJECT_DIR_TYPE) {
      return
    }
    const fileType = CommonUtil.getFileType(item.name)
    const fileExtension = CommonUtil.getFileExtention(item.name)
    if (fileType === FileType.IMAGE) {
      CloudRouter.push(Constant.IAMGE_PREVIEW_PAGE, this.buildImagePreviewParam(item, fileExtension))
    } else if (fileType === FileType.VIDEO) {
      CloudRouter.push(Constant.VIDEO_PREVIEW_PAGE, new VideoPreview(item.name, item.id, fileExtension))
    } else if (CommonUtil.isTextViewable(fileType)) {
      TextPreviewEntry.open(item)
    } else {
      showToast('该类型不支持预览')
    }
  }

  private buildImagePreviewParam(item: ObjectInfo, fileExtension: string): ImagePreview {
    const images = this.results
      .filter((file: ObjectInfo) => file.type === Constant.OBJECT_FILE_TYPE &&
        CommonUtil.getFileType(file.name) === FileType.IMAGE)
      .map((file: ObjectInfo) => new PreviewFile(file.name, file.id, CommonUtil.getFileExtention(file.name)))
    const currentIndex = images.findIndex((file: PreviewFile) => file.fileId === item.id)
    return new ImagePreview(item.name, item.id, fileExtension, images, currentIndex >= 0 ? currentIndex : 0)
  }

  build() {
    HdsNavigation() {
      Column() {
        Stack({ alignContent: Alignment.Bottom }) {
          Column() {
            this.resultList()
          }
          .width('100%')
          .height('100%')
          .padding({
            bottom: this.isMultiSelectMode ? CloudThemeToken.rowHeight5xl + CloudThemeToken.spacingPage :
            CloudThemeToken.zero
          })

          if (this.isMultiSelectMode) {
            this.multiSelectActionBar()
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.getTitleBarHeight() + CloudThemeToken.spacingSection,
        bottom: this.bottomRectHeight + CloudThemeToken.spacingPage
      })
      .backgroundColor(CloudThemeToken.background)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideToolBar(true)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: ' '
        },
        backIcon: {
          icon: $r('app.media.ic_back'),
          action: () => {
            CloudRouter.pop()
          }
        },
        stackBuilder: () => {
          this.searchTitleStack()
        },
        divider: {
          showType: DividerShowType.OFF
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: CloudThemeToken.transparent
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: CloudThemeToken.textPrimary
            },
            backIconStyle: {
              backgroundColor: CloudThemeToken.surfaceSubtle,
              iconColor: CloudThemeToken.textPrimary
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder searchTitleStack() {
    Row() {
      Stack() {
        Row({ space: CloudThemeToken.spacingXs }) {
          Image($r('app.media.ic_search'))
            .width(CloudThemeToken.iconXl)
            .height(CloudThemeToken.iconXl)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)

          TextInput({ text: this.searchKeyword, placeholder: '搜索文件、文件夹' })
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontColor(CloudThemeToken.textPrimary)
            .placeholderColor(CloudThemeToken.textSecondary)
            .enterKeyType(EnterKeyType.Search)
            .backgroundColor(CloudThemeToken.transparent)
            .borderRadius(CloudThemeToken.inputInnerRadius)
            .height('100%')
            .layoutWeight(1)
            .padding({ left: CloudThemeToken.zero, right: CloudThemeToken.zero })
            .defaultFocus(true)
            .onChange((value: string) => {
              this.searchKeyword = value
            })
            .onSubmit(() => {
              this.executeSearch()
            })

          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.ic_global_search'))
              .width(CloudThemeToken.iconLg)
              .height(CloudThemeToken.iconLg)
              .fillColor(this.searchScope === FileSearchScope.ALL_FILES ?
                CloudThemeToken.primary : CloudThemeToken.textPrimary)
              .draggable(false)
          }
          .width(CloudThemeToken.iconBoxXs)
          .height(CloudThemeToken.iconBoxXs)
          .borderRadius(CloudThemeToken.controlRadiusRoundMd)
          .backgroundColor(this.searchScope === FileSearchScope.ALL_FILES ?
            CloudThemeToken.primarySoft : CloudThemeToken.transparent)
          .stateEffect(false)
          .bindTips(this.getGlobalSearchTip())
          .accessibilityText(this.getGlobalSearchTip())
          .onClick(() => {
            this.changeSearchScope(this.searchScope === FileSearchScope.ALL_FILES ?
              FileSearchScope.CURRENT_DIRECTORY : FileSearchScope.ALL_FILES)
          })

          Divider()
            .vertical(true)
            .height(CloudThemeToken.iconXl)
            .strokeWidth(CloudThemeToken.lineWidth)
            .color(CloudThemeToken.line)
            .margin({ left: CloudThemeToken.spacingXs, right: CloudThemeToken.spacingXs })

          Button('搜索', { type: ButtonType.Normal })
            .height(CloudThemeToken.iconBoxXs)
            .padding({ left: CloudThemeToken.spacingMd, right: CloudThemeToken.spacingMd })
            .fontSize(CloudThemeToken.textSizeBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.primary)
            .borderRadius(CloudThemeToken.controlRadiusRoundMd)
            .backgroundColor(CloudThemeToken.transparent)
            .accessibilityText('执行搜索')
            .onClick(() => {
              this.executeSearch()
            })
        }
        .width('100%')
        .height('100%')
        .padding({
          left: CloudThemeToken.spacingCard,
          right: CloudThemeToken.spacingCard
        })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(CloudThemeToken.transparent)
      }
        .borderRadius(CloudThemeToken.controlRadius)
        .height(CloudThemeToken.iconButtonSize)
        .layoutWeight(1)
        .backgroundColor(CloudThemeToken.transparent)
        .backgroundEffect({
          radius: CloudThemeToken.refreshShadowRadius,
          saturation: CloudThemeToken.fullOpacity,
          brightness: CloudThemeToken.fullOpacity,
          color: CloudThemeToken.searchGlass
        })
        .border({
          width: CloudThemeToken.searchBorderWidth,
          color: {
            top: CloudThemeToken.searchBorderHighlight,
            right: CloudThemeToken.glassHighlight,
            bottom: CloudThemeToken.searchBorderLowlight,
            left: CloudThemeToken.searchBorderHighlight
          }
        })
        .shadow({
          radius: CloudThemeToken.controlRadiusSm,
          color: CloudThemeToken.searchBorderShadow,
          offsetY: CloudThemeToken.refreshShadowOffsetY
        })
        .visualEffect(this.getSearchFieldEffect())
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.getSearchFieldLeftInset(),
      right: CloudThemeToken.filesTitleHorizontalPadding
    })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.End)
  }

  // 宽屏（PC/平板自由窗口）下 HDS 返回按钮更宽且贴近窗口边缘，
  // 预留宽度需要在手机基准上再加一段间隙，否则搜索框会顶到返回按钮。
  private getSearchFieldLeftInset(): number {
    const base = CloudThemeToken.filesTitleHorizontalPadding + CloudThemeToken.iconButtonSize
    return base + (CloudThemeToken.isWideWidth(this.windowWidthVp)
      ? CloudThemeToken.spacingPage : CloudThemeToken.spacingMd)
  }

  private getGlobalSearchTip(): string {
    if (this.searchScope !== FileSearchScope.ALL_FILES) {
      return '开启全局搜索'
    }
    return this.isLoadingGlobalObjects ? '正在全局搜索，点击关闭' : '关闭全局搜索'
  }

  @Builder resultList() {
    if (this.activeSearchKeyword.trim().length === 0) {
      this.searchHistoryPanel()
    } else if (this.results.length > CloudThemeToken.zero) {
      if (this.getShowType() === ShowType.SHOW_ICON) {
        Grid() {
          ForEach(this.getResultDirs(), (item: ObjectInfo, index: number) => {
            GridItem() {
              this.resultRow(item, index)
            }
          }, (item: ObjectInfo) => item.id)

          ForEach(this.getFolderPaddingItems(), (item: number) => {
            GridItem() {
              Row()
                .width('100%')
                .height(CloudThemeToken.objectGridFolderHeight)
            }
          }, (item: number) => `folder-padding-${item}`)

          ForEach(this.getResultFiles(), (item: ObjectInfo, index: number) => {
            GridItem() {
              this.resultRow(item, index)
            }
          }, (item: ObjectInfo) => item.id)
        }
        .width('100%')
        .height('100%')
        .maxCount(this.getGridColumns())
        .columnsTemplate(this.getGridColumnsTemplate())
        .columnsGap(CloudThemeToken.gridGap)
        .rowsGap(CloudThemeToken.gridGap)
        .padding({
          left: CloudThemeToken.spacingCard,
          right: CloudThemeToken.spacingCard
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const width = Number(newArea.width)
          if (!Number.isNaN(width) &&
            Math.abs(width - this.gridWidth) >= CloudThemeToken.layoutChangeThreshold) {
            this.gridWidth = width
          }
        })
      } else {
        List({ space: CloudThemeToken.zero }) {
          ForEach(this.getResultDirs(), (item: ObjectInfo, index: number) => {
            ListItem() {
              this.resultRow(item, index)
            }
          }, (item: ObjectInfo) => item.id)

          ForEach(this.getResultFiles(), (item: ObjectInfo, index: number) => {
            ListItem() {
              this.resultRow(item, index)
            }
          }, (item: ObjectInfo) => item.id)
        }
        .width('100%')
        .height('100%')
        .cachedCount(CloudThemeToken.compactListCachedCount)
        .divider({
          strokeWidth: CloudThemeToken.lineWidth,
          color: CloudThemeToken.line,
          startMargin: CloudThemeToken.filesTitleHorizontalPadding + CloudThemeToken.objectListIconSize +
          CloudThemeToken.objectItemGap,
          endMargin: CloudThemeToken.filesTitleHorizontalPadding
        })
      }
    } else {
      Column({ space: CloudThemeToken.spacingCard }) {
        if (this.isLoadingGlobalObjects && this.activeSearchKeyword.trim().length > 0) {
          LoadingProgress()
            .width(CloudThemeToken.icon3xl)
            .height(CloudThemeToken.icon3xl)
            .color(CloudThemeToken.primary)
          Text('正在搜索全部文件…')
            .fontSize(CloudThemeToken.textSizeBody)
            .fontColor(CloudThemeToken.textSecondary)
        } else if (this.activeSearchKeyword.trim().length > 0) {
          Text('未找到匹配文件')
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontColor(CloudThemeToken.textSecondary)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder searchHistoryChip(historyValue: string, compact: boolean) {
    Button(this.getHistoryKeyword(historyValue), { type: ButtonType.Normal })
      .height(CloudThemeToken.rowHeightSm)
      .fontSize(CloudThemeToken.textSizeBody)
      .fontColor(CloudThemeToken.textPrimary)
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .backgroundColor(CloudThemeToken.surfaceSubtle)
      .margin({
        right: CloudThemeToken.spacingXl,
        bottom: compact ? CloudThemeToken.zero : CloudThemeToken.spacingXl
      })
      .onClick(() => {
        this.useSearchHistory(historyValue)
      })
  }

  @Builder searchHistoryPanel() {
    if (this.searchHistory.length > 0) {
      Column({ space: CloudThemeToken.spacingSection }) {
        Row() {
          Text('搜索历史')
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .layoutWeight(1)

          Button('清空', { type: ButtonType.Normal })
            .height(CloudThemeToken.rowHeightSm)
            .fontSize(CloudThemeToken.textSizeSmallPlus)
            .fontColor(CloudThemeToken.textSecondary)
            .borderRadius(CloudThemeToken.controlRadiusRoundMd)
            .backgroundColor(CloudThemeToken.transparent)
            .onClick(() => {
              this.clearSearchHistory()
            })

          if (this.shouldShowSearchHistoryToggle()) {
            Button({ type: ButtonType.Normal }) {
              Image($r('app.media.ic_chevron_down'))
                .width(CloudThemeToken.iconMd)
                .height(CloudThemeToken.iconMd)
                .fillColor(CloudThemeToken.textSecondary)
                .rotate({ angle: this.searchHistoryExpanded ? 180 : 0 })
                .draggable(false)
            }
            .width(CloudThemeToken.iconBoxXs)
            .height(CloudThemeToken.iconBoxXs)
            .borderRadius(CloudThemeToken.controlRadiusRoundMd)
            .backgroundColor(CloudThemeToken.transparent)
            .stateEffect(false)
            .accessibilityText(this.searchHistoryExpanded ? '收起搜索历史' : '展开搜索历史')
            .onClick(() => {
              this.toggleSearchHistory()
            })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.searchHistoryExpanded) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
            ForEach(this.searchHistory, (historyValue: string) => {
              this.searchHistoryChip(historyValue, false)
            }, (historyValue: string) => historyValue)
          }
          .width('100%')
        } else {
          Scroll() {
            Row() {
              ForEach(this.searchHistory, (historyValue: string) => {
                this.searchHistoryChip(historyValue, true)
              }, (historyValue: string) => historyValue)
            }
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.searchHistoryContentWidth = Number(newArea.width)
            })
          }
          .width('100%')
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .align(Alignment.Start)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.searchHistoryViewportWidth = Number(newArea.width)
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: CloudThemeToken.filesTitleHorizontalPadding,
        right: CloudThemeToken.filesTitleHorizontalPadding,
        top: CloudThemeToken.spacingMd
      })
      .alignItems(HorizontalAlign.Start)
    } else {
      Column({ space: CloudThemeToken.spacingCard }) {
        Image($r('app.media.ic_search'))
          .width(CloudThemeToken.icon4xl)
          .height(CloudThemeToken.icon4xl)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)

        Text(this.searchScope === FileSearchScope.ALL_FILES ?
          '输入关键词搜索全部文件' : '输入关键词搜索当前目录')
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder resultRow(item: ObjectInfo, index: number) {
    ObjectItem({
      index: index,
      item: item,
      showType: this.getShowType(),
      multiSelectMode: this.isMultiSelectMode,
      selected: this.isObjectSelected(item),
      onMenuClick: (menuItem: ObjectInfo, type: FileMenuType) => {
        this.dispatchMenuClick(menuItem, type)
      }
    })
    .onClick(() => {
      if (this.isMultiSelectMode) {
        this.toggleObjectSelection(item)
      } else {
        this.dispatchOpenResult(item)
      }
    })
    .onVisibleAreaChange([0.01], (isVisible: boolean) => {
      if (isVisible) {
        this.requestThumb(item)
      }
    })
  }

  @Builder multiSelectActionBar() {
    Row() {
      Button(this.areAllResultsSelected() ? '取消全选' : '全选')
        .fontColor(CloudThemeToken.textPrimary)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        .onClick(() => {
          this.toggleSelectAll()
        })

      Text(`已选 ${this.selectedObjects.length} 项`)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .fontSize(CloudThemeToken.textSizeBody)
        .fontColor(CloudThemeToken.textPrimary)

      Button('删除')
        .fontColor(CloudThemeToken.danger)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        .enabled(this.selectedObjects.length > 0)
        .onClick(() => {
          this.confirmDelete(this.selectedObjects.slice())
        })

      Button('取消')
        .fontColor(CloudThemeToken.textPrimary)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        .onClick(() => {
          this.exitMultiSelectMode()
        })
    }
    .width('100%')
    .height(CloudThemeToken.rowHeight5xl)
    .padding({
      left: CloudThemeToken.spacingPage,
      right: CloudThemeToken.spacingPage
    })
    .backgroundColor(CloudThemeToken.surface)
    .border({
      width: { top: CloudThemeToken.lineWidth },
      color: CloudThemeToken.line
    })
  }
}
