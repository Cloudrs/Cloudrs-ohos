import { http } from '@kit.NetworkKit'
import { pasteboard } from '@kit.BasicServicesKit'
import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { CloudApi } from '../model/net/CloudApi'
import { TextPreviewParam } from '../model/Params'
import { common } from '@kit.AbilityKit'
import { CloudIconButton } from '../components/CloudIconButton'
import { CodeEditor, CodeEditorController, EditorThemeMode } from '../components/CodeEditor'
import { MarkdownToolbar } from '../components/MarkdownToolbar'
import { EmptyState } from '../components/EmptyState'
import UserPreferences from '../model/UserPreferences'
import { ObjectDetail } from '../model/net/ApiTypes'
import { CloudRouter } from '../utils/CloudRouter'
import { CommonUtil } from '../utils/CommonUtil'
import { FileSystemUtil } from '../utils/FileSystemUtil'
import { TextDraftStore } from '../utils/TextDraftStore'
import { showCloudConfirmDialog } from '../utils/CloudDialogUtil'
import { showToast } from '../utils/ToastUtil'
import {
  TextDecodeFailure, TextDecodeResult, TextEncodeOptions, TextFileCodec, TextLineEnding
} from '../utils/TextFileCodec'
import AppLogger from '../utils/AppLogger'

const TAG: string = 'TextPreview'
/** 与 CommonUtil.getEditorLanguage 的返回值一致，只有它才给 Markdown 预览入口 */
const EDITOR_LANGUAGE_MARKDOWN: string = 'markdown'

enum TextLoadState {
  LOADING,
  READY,
  FAILED
}

@Component
export struct TextPreviewPage {
  routeParam?: TextPreviewParam
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.WINDOW_WIDTH_VP) windowWidthVp: number = 0
  @State loadState: TextLoadState = TextLoadState.LOADING
  @State failedTitle: string = ''
  @State failedDescription: string = ''
  @State encodingLabel: string = ''
  @State lineEnding: TextLineEnding = TextLineEnding.LF
  @State lineCount: number = 0
  /** 自增即触发一次下发；正文本身不进装饰器，由编辑器反向拉取 */
  @State contentRevision: number = 0
  @State editorLanguage: string = ''
  @State editorTheme: string = EditorThemeMode.LIGHT
  @State cursorLine: number = 1
  @State cursorColumn: number = 1
  /** 编码可写且未超限才允许进编辑态 */
  /** 服务端实际大小；路由参数里的 size 保存后就过期了，状态栏不能再用它 */
  @State currentSize: number = -1
  @State canEdit: boolean = false
  @State editMode: boolean = false
  @State dirty: boolean = false
  @State saving: boolean = false
  @State lineWrap: boolean = true
  @State fontSize: number = Constant.TEXT_EDITOR_FONT_SIZE_DEFAULT
  @State previewMode: boolean = false
  private content: string = ''
  /** 原始字节留着，手动切换编码时重新解码，不用再下载一次 */
  private rawBuffer?: ArrayBuffer
  private hasBom: boolean = false
  private editorController: CodeEditorController = new CodeEditorController()
  // 保存前比对用的服务端基线，检测他端改动
  private baselineSize: number = -1
  private baselineUpdatedAt: string = ''
  /** 正在进行的基线刷新；保存前要等它，否则拿旧基线比会误报冲突 */
  private baselinePending?: Promise<void>

  aboutToAppear(): void {
    AppLogger.info(TAG, `open text preview, name=${this.routeParam?.fileName ?? ''}, size=${this.routeParam?.fileSize ?? 0}`)
    this.editorLanguage = CommonUtil.getEditorLanguage(this.routeParam?.fileName ?? '')
    this.editorTheme = this.resolveThemeMode()
    // 存量偏好可能落在当前上下限之外（阈值调整过），读出来要收敛一次
    this.fontSize = TextPreviewPage.clampFontSize(UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.TEXT_EDITOR_FONT_SIZE, Constant.TEXT_EDITOR_FONT_SIZE_DEFAULT) as number)
    this.lineWrap = UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.TEXT_EDITOR_LINE_WRAP, true) as boolean
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (context) {
      TextDraftStore.init(context)
    }
    // 未保存内容的离开拦截，覆盖返回键/手势/页内返回三条路径
    CloudRouter.setExitGuard(() => this.guardExit())
    this.loadContent()
  }

  aboutToDisappear(): void {
    CloudRouter.setExitGuard(undefined)
  }

  /** 返回 true 表示拦下本次离开 */
  private guardExit(): boolean {
    if (!this.dirty || this.saving) {
      return false
    }
    showCloudConfirmDialog(this.getUIContext(), {
      title: '有未保存的修改',
      message: '离开将丢失这些修改，确定放弃吗？',
      confirmText: '放弃修改',
      onConfirm: () => {
        this.dirty = false
        CloudRouter.setExitGuard(undefined)
        CloudRouter.popForced()
      }
    })
    return true
  }

  private resolveThemeMode(): string {
    const mode = UserPreferences.getSync(
      Constant.USER_PREFERENCES, Constant.APP_THEME_MODE, Constant.APP_THEME_LIGHT) as string
    return mode === Constant.APP_THEME_DARK ? EditorThemeMode.DARK : EditorThemeMode.LIGHT
  }

  build() {
    Column() {
      this.header()
      if (this.loadState === TextLoadState.READY && this.editorLanguage === EDITOR_LANGUAGE_MARKDOWN) {
        MarkdownToolbar({
          previewMode: this.previewMode,
          editMode: this.editMode && !this.previewMode,
          onTogglePreview: () => {
            this.toggleMarkdownPreview()
          },
          onAction: (action: string) => {
            this.editorController.markdownAction(action)
          }
        })
      }
      this.body()
      if (this.loadState === TextLoadState.READY) {
        this.statusBar()
      }
      Blank().height(this.bottomRectHeight)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder header() {
    Column() {
      Blank().height(CloudThemeToken.getSafeTopInset(this.topRectHeight))

      Row({ space: CloudThemeToken.spacingSection }) {
        CloudIconButton({
          icon: $r('app.media.ic_back'),
          buttonBackground: CloudThemeToken.surfaceSubtle,
          buttonRadius: CloudThemeToken.actionRadiusForWidth(this.windowWidthVp, CloudThemeToken.controlRadius),
          onAction: () => {
            CloudRouter.pop()
          }
        })

        Text(this.routeParam?.fileName ?? '')
          .fontColor(CloudThemeToken.textPrimary)
          .fontSize(CloudThemeToken.textPreviewTitleSize)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        CloudIconButton({
          icon: $r('app.media.ic_copy'),
          buttonBackground: CloudThemeToken.surfaceSubtle,
          buttonRadius: CloudThemeToken.actionRadiusForWidth(this.windowWidthVp, CloudThemeToken.controlRadius),
          isEnabled: this.loadState === TextLoadState.READY,
          onAction: () => {
            this.copyAll()
          }
        })

        CloudIconButton({
          icon: $r('app.media.ic_square_more'),
          buttonBackground: CloudThemeToken.surfaceSubtle,
          buttonRadius: CloudThemeToken.actionRadiusForWidth(this.windowWidthVp, CloudThemeToken.controlRadius),
          isEnabled: this.loadState === TextLoadState.READY
        })
          .bindMenu(this.toolMenu())

        if (this.editMode) {
          CloudIconButton({
            icon: $r('app.media.ic_save'),
            buttonBackground: CloudThemeToken.primarySoft,
            buttonRadius: CloudThemeToken.actionRadiusForWidth(this.windowWidthVp, CloudThemeToken.controlRadius),
            iconColor: CloudThemeToken.primary,
            isEnabled: this.dirty && !this.saving,
            onAction: () => {
              this.startSave()
            }
          })
        } else if (this.canEdit) {
          CloudIconButton({
            icon: $r('app.media.ic_pencil'),
            buttonBackground: CloudThemeToken.surfaceSubtle,
            buttonRadius: CloudThemeToken.actionRadiusForWidth(this.windowWidthVp, CloudThemeToken.controlRadius),
            isEnabled: this.loadState === TextLoadState.READY,
            onAction: () => {
              this.enterEditMode()
            }
          })
        }
      }
      .height(CloudThemeToken.titleBarHeight)
      .width('100%')
      .padding({ left: CloudThemeToken.spacingXs, right: CloudThemeToken.spacingXs })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: CloudThemeToken.spacingSection, right: CloudThemeToken.spacingSection })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder body() {
    Stack() {
      if (this.loadState === TextLoadState.FAILED) {
        Column() {
          EmptyState({
            icon: $r('app.media.ic_warn_circle'),
            title: this.failedTitle,
            description: this.failedDescription,
            actionText: '重试',
            onAction: () => {
              this.loadContent()
            }
          })
        }
        .width('100%')
        .padding({ left: CloudThemeToken.pagePadding, right: CloudThemeToken.pagePadding })
      } else {
        // 下载和 WebView 冷启动并行：编辑器在加载态就挂上，正文到位后再下发
        this.textBody()

        if (this.loadState === TextLoadState.LOADING) {
          Column() {
            LoadingProgress()
              .width(CloudThemeToken.iconBox2xl)
              .height(CloudThemeToken.iconBox2xl)
              .color(CloudThemeToken.primary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(CloudThemeToken.background)
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignContent(Alignment.Center)
  }

  /**
   * 正文交给 CodeMirror。
   * 它自带虚拟视口和自己的选区模型，行号、跨行选中、大文件三者才不再互斥——
   * 这在 ArkUI 原生组件上做不到，详见 docs/text-edit-plan.md。
   */
  @Builder textBody() {
    CodeEditor({
      contentRevision: this.contentRevision,
      language: this.editorLanguage,
      readOnly: !this.editMode,
      themeMode: this.editorTheme,
      contentProvider: (): string => this.content,
      controller: this.editorController,
      lineWrap: this.lineWrap,
      fontSize: this.fontSize,
      previewMode: this.previewMode,
      onCursorChange: (line: number, column: number) => {
        this.cursorLine = line
        this.cursorColumn = column
      },
      onDirtyChange: (dirty: boolean) => {
        this.dirty = dirty
      },
      onSaveContent: (text: string) => {
        this.performSave(text)
      },
      onCopyText: (text: string) => {
        this.copyToClipboard(text, '代码已复制')
      },
      onRequestEdit: () => {
        this.enterEditByGesture()
      }
    })
      .width('100%')
      .height('100%')
  }

  @Builder toolMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: '查找 / 替换' })
          .onClick(() => {
            this.previewMode = false
            this.editorController.openSearch()
          })
        MenuItem({ content: '跳转到行' })
          .onClick(() => {
            this.previewMode = false
            this.editorController.gotoLine()
          })
      }

      MenuItemGroup() {
        MenuItem({ content: this.lineWrap ? '关闭自动换行' : '开启自动换行' })
          .onClick(() => {
            this.lineWrap = !this.lineWrap
            UserPreferences.putSync(
              Constant.USER_PREFERENCES, Constant.TEXT_EDITOR_LINE_WRAP, this.lineWrap)
          })
        MenuItem({ content: '增大字号' })
          .enabled(this.fontSize < Constant.TEXT_EDITOR_FONT_SIZE_MAX)
          .onClick(() => {
            this.applyFontSize(this.fontSize + Constant.TEXT_EDITOR_FONT_SIZE_STEP)
          })
        MenuItem({ content: '减小字号' })
          .enabled(this.fontSize > Constant.TEXT_EDITOR_FONT_SIZE_MIN)
          .onClick(() => {
            this.applyFontSize(this.fontSize - Constant.TEXT_EDITOR_FONT_SIZE_STEP)
          })
      }

      if (this.editorLanguage === EDITOR_LANGUAGE_MARKDOWN) {
        MenuItemGroup() {
          MenuItem({ content: this.previewMode ? '退出预览' : 'Markdown 预览' })
            .onClick(() => {
              this.previewMode = !this.previewMode
            })
        }
      }

      MenuItemGroup() {
        ForEach(TextFileCodec.supportedEncodings(), (encoding: string) => {
          MenuItem({ content: `按 ${encoding} 重新解码` })
            .enabled(!this.dirty)
            .onClick(() => {
              this.reopenWithEncoding(encoding)
            })
        }, (encoding: string) => encoding)
      }
    }
  }

  private static clampFontSize(size: number): number {
    if (!Number.isFinite(size)) {
      return Constant.TEXT_EDITOR_FONT_SIZE_DEFAULT
    }
    return Math.min(Constant.TEXT_EDITOR_FONT_SIZE_MAX,
      Math.max(Constant.TEXT_EDITOR_FONT_SIZE_MIN, Math.round(size)))
  }

  private applyFontSize(size: number): void {
    this.fontSize = TextPreviewPage.clampFontSize(size)
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.TEXT_EDITOR_FONT_SIZE, this.fontSize)
  }

  /**
   * 用另一种编码重新解释已下载的字节。
   * 有未保存修改时不允许切——重新解码会整个换掉正文，改动就没了。
   */
  private reopenWithEncoding(encoding: string): void {
    const buffer = this.rawBuffer
    if (!buffer) {
      showToast('原始内容已释放，请重新打开文件')
      return
    }
    const decoded = TextFileCodec.decodeAs(buffer, encoding)
    if (!decoded.ok) {
      // 宁可拒绝也不显示乱码：放行的乱码会被当成可编辑内容，保存即覆盖原文件
      showToast(`该文件不是 ${encoding} 编码，已保持原样`)
      return
    }
    this.previewMode = false
    this.editMode = false
    this.applyDecoded(decoded, false)
    showToast(`已按 ${encoding} 重新解码`)
  }

  @Builder statusBar() {
    Row({ space: CloudThemeToken.spacingSection }) {
      Text(this.buildStatusText())
        .fontSize(CloudThemeToken.textPreviewMetaSize)
        .fontColor(CloudThemeToken.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(CloudThemeToken.textPreviewStatusBarHeight)
    .padding({ left: CloudThemeToken.pagePadding, right: CloudThemeToken.pagePadding })
    .alignItems(VerticalAlign.Center)
    .border({ width: { top: CloudThemeToken.lineWidth }, color: CloudThemeToken.line })
  }

  private buildStatusText(): string {
    const size = CommonUtil.formatBytes(
      this.currentSize >= CloudThemeToken.zero ? this.currentSize : (this.routeParam?.fileSize ?? 0))
    const position = `${this.cursorLine}:${this.cursorColumn}`
    let mode = '只读'
    if (this.saving) {
      mode = '保存中'
    } else if (this.editMode) {
      mode = this.dirty ? '未保存' : '编辑中'
    } else if (!this.canEdit && TextFileCodec.isWritableEncoding(this.encodingLabel)) {
      mode = '只读'
    } else if (!this.canEdit) {
      mode = '只读（该编码不支持编辑）'
    }
    return `${this.encodingLabel} · ${this.lineEnding} · ${this.lineCount} 行 · ${position} · ${size} · ${mode}`
  }

  private loadContent(): void {
    const param = this.routeParam
    if (!param || param.fileId.length === CloudThemeToken.zero) {
      this.markFailed('无法打开', '缺少文件信息，请返回文件列表重试')
      return
    }
    if (param.fileSize > Constant.TEXT_PREVIEW_MAX_BYTES) {
      this.markFailed('文件过大', `文本预览最大支持 ${CommonUtil.formatBytes(Constant.TEXT_PREVIEW_MAX_BYTES)}`)
      return
    }

    this.loadState = TextLoadState.LOADING
    CloudApi.getDownloadUri(param.fileId, {
      onSuccess: (url: string) => {
        this.fetchText(url)
      },
      onFailure: (msg: string) => {
        AppLogger.warn(TAG, `get download uri failed: ${msg}`)
        this.markFailed('加载失败', msg.length > CloudThemeToken.zero ? msg : '获取文件地址失败，请重试')
      }
    })
  }

  private async fetchText(url: string): Promise<void> {
    const resolvedUrl = (url.startsWith(Constant.PROTOCOL_HTTP_SCHEME) ||
      url.startsWith(Constant.PROTOCOL_HTTPS_SCHEME)) ? url : CloudApi.getBaseURL() + url
    const req = http.createHttp()
    try {
      const resp = await req.request(resolvedUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: Constant.TEXT_PREVIEW_MAX_BYTES
      })
      if (resp.responseCode !== Constant.HTTP_STATUS_OK) {
        AppLogger.warn(TAG, `download text failed, code=${resp.responseCode}`)
        this.markFailed('加载失败', `服务器返回 ${resp.responseCode}`)
        return
      }
      this.rawBuffer = resp.result as ArrayBuffer
      this.applyDecoded(TextFileCodec.decode(this.rawBuffer))
    } catch (err) {
      AppLogger.error(TAG, `download text threw: ${(err as Error)?.message ?? err}`)
      this.markFailed('加载失败', '网络异常，请检查连接后重试')
    } finally {
      req.destroy()
    }
  }

  /**
   * @param initialLoad 首次加载才决定初始视图模式。
   *   手动切换编码时复用本方法，但那时用户已经明确要看源码，
   *   不能再把 Markdown 拽回预览。
   */
  private applyDecoded(decoded: TextDecodeResult, initialLoad: boolean = true): void {
    if (!decoded.ok) {
      const isBinary = decoded.failure === TextDecodeFailure.BINARY
      AppLogger.warn(TAG, `decode failed, failure=${decoded.failure}`)
      this.markFailed(
        isBinary ? '不是文本文件' : '无法解码',
        isBinary ? '该文件包含二进制内容，或使用了不支持的文本编码' : '文件编码无法识别'
      )
      return
    }

    const lineCount = TextFileCodec.splitLines(decoded.text).length
    this.content = decoded.text
    this.encodingLabel = decoded.encoding
    this.lineEnding = decoded.lineEnding
    this.hasBom = decoded.hasBom
    this.lineCount = lineCount
    // 非 UTF-8 一律只读：用 UTF-8 覆盖回去等于把用户的文件写坏
    this.canEdit = TextFileCodec.isWritableEncoding(decoded.encoding) &&
      (this.routeParam?.fileSize ?? 0) <= Constant.TEXT_PREVIEW_MAX_BYTES
    this.loadState = TextLoadState.READY
    if (initialLoad) {
      // 空文件没什么可读的，多半是刚新建出来的，直接进编辑态省一次点击
      if (this.canEdit && decoded.text.length === CloudThemeToken.zero) {
        this.editMode = true
        this.previewMode = false
      } else if (this.editorLanguage === EDITOR_LANGUAGE_MARKDOWN) {
        // Markdown 默认渲染后的样子，源码要看再切
        this.previewMode = true
      }
    }
    // 编辑器可能已经就绪在等内容，这里自增触发下发
    this.contentRevision++
    this.refreshBaseline()
    this.offerDraftRestore()
    AppLogger.info(TAG, `text ready, encoding=${decoded.encoding}, lines=${lineCount}`)
  }

  /**
   * 双击（鼠标双击 / 触屏连点两下）请求进入编辑。
   * 来源有两处：Markdown 预览区，以及任意文本类型的只读编辑器。
   * 不可编辑时要给个说法——双击没反应会让人以为功能坏了。
   */
  private enterEditByGesture(): void {
    if (this.editMode && !this.previewMode) {
      return
    }
    if (this.loadState !== TextLoadState.READY) {
      return
    }
    if (!this.canEdit) {
      showToast(TextFileCodec.isWritableEncoding(this.encodingLabel)
        ? '该文件不支持编辑' : `${this.encodingLabel} 编码暂不支持编辑`)
      return
    }
    this.previewMode = false
    this.editMode = true
    this.editorController.focusEditor()
    AppLogger.info(TAG, 'enter edit mode by double click')
  }

  /** 预览与编辑互斥：退出预览时若可编辑就直接进编辑态，少点一次铅笔 */
  private toggleMarkdownPreview(): void {
    const next = !this.previewMode
    this.previewMode = next
    if (!next && this.canEdit) {
      this.editMode = true
    }
  }

  private enterEditMode(): void {
    this.previewMode = false
    this.editMode = true
    this.editorController.focusEditor()
    AppLogger.info(TAG, `enter edit mode, file=${this.routeParam?.fileName ?? ''}`)
  }

  /** 保存的第一步：向编辑器要当前正文，回来后走 performSave */
  private startSave(): void {
    if (this.saving || !this.dirty) {
      return
    }
    this.editorController.requestSave()
  }

  private async performSave(text: string): Promise<void> {
    if (this.saving) {
      return
    }
    // 守卫必须在这里，不能只靠按钮显隐：编辑器里的 Ctrl+S 会绕开所有 UI
    // 直接送到这条路径上，只读文件一旦放行就会被按 UTF-8 重写。
    if (!this.canEdit) {
      showToast(TextFileCodec.isWritableEncoding(this.encodingLabel)
        ? '该文件不支持编辑' : `${this.encodingLabel} 编码不支持编辑，未做任何修改`)
      AppLogger.warn(TAG, `save rejected: canEdit=false, encoding=${this.encodingLabel}`)
      return
    }
    const param = this.routeParam
    if (!param || param.filePath.length === CloudThemeToken.zero) {
      showToast('缺少文件路径，无法保存')
      return
    }
    this.saving = true
    try {
      const changed = await this.detectRemoteChange()
      if (changed) {
        this.saving = false
        this.confirmOverwrite(text)
        return
      }
      await this.uploadText(text)
    } catch (err) {
      AppLogger.error(TAG, `save failed: ${(err as Error)?.message ?? err}`)
      this.handleSaveFailure(text, (err as Error)?.message ?? '保存失败')
    } finally {
      this.saving = false
    }
  }

  private confirmOverwrite(text: string): void {
    showCloudConfirmDialog(this.getUIContext(), {
      title: '文件已被改动',
      message: '服务端的这个文件在你打开之后发生过变化，继续保存会覆盖对方的修改。',
      confirmText: '仍然覆盖',
      onConfirm: () => {
        this.saving = true
        this.uploadText(text)
          .catch((err: Error) => {
            AppLogger.error(TAG, `overwrite save failed: ${err.message ?? err}`)
            this.handleSaveFailure(text, err.message ?? '保存失败')
          })
          .then(() => {
            this.saving = false
          })
      }
    })
  }

  /**
   * 比对服务端基线，检测打开之后是否有他端改动。
   * 拿不到详情时按"没变"处理——不能因为一次查询失败就堵住用户保存。
   */
  private async detectRemoteChange(): Promise<boolean> {
    // 首帧基线可能还在路上，等它一下；否则这次检查会被静默跳过
    if (this.baselinePending) {
      await this.baselinePending
    }
    const fileId = this.routeParam?.fileId ?? ''
    if (fileId.length === CloudThemeToken.zero || this.baselineSize < CloudThemeToken.zero) {
      return Promise.resolve(false)
    }
    return new Promise<boolean>((resolve) => {
      CloudApi.getObjectDetail(fileId, false, {
        onSuccess: (detail: ObjectDetail) => {
          const changed = detail.size !== this.baselineSize ||
            (detail.updated_at.length > CloudThemeToken.zero && detail.updated_at !== this.baselineUpdatedAt)
          resolve(changed)
        },
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `conflict check failed, continue saving: ${msg}`)
          resolve(false)
        }
      })
    })
  }

  private async uploadText(text: string): Promise<void> {
    const param = this.routeParam
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (!param || !context) {
      throw new Error('保存环境不可用')
    }
    const buffer = TextFileCodec.encode(text, new TextEncodeOptions(this.lineEnding, this.hasBom))
    AppLogger.info(TAG, `saving to ${param.filePath}, ${buffer.byteLength} bytes, eol=${this.lineEnding}, bom=${this.hasBom}`)
    const cachePath = `${context.cacheDir}/text_save_${new Date().getTime()}_${CommonUtil.getFileName(param.filePath)}`
    await FileSystemUtil.writeArrayBuffer(cachePath, buffer)
    try {
      await this.uploadCacheFile(cachePath, param.filePath)
    } finally {
      FileSystemUtil.unlinkIfExists(cachePath)
    }

    this.content = text
    this.editorController.markSaved()
    this.dirty = false
    this.lineCount = TextFileCodec.splitLines(text).length
    TextDraftStore.clear(param.fileId)
    // 不等它：真等下去，一旦 getObjectDetail 卡住，文件其实已保存成功，
    // 界面却停在"保存中"、成功提示也不出来。
    // 连续保存的误报由 detectRemoteChange 等 baselinePending 来挡。
    this.refreshBaseline()
    param.onSaved?.()
    showToast('已保存')
    AppLogger.info(TAG, `saved ${param.filePath}, ${buffer.byteLength} bytes`)
  }

  private uploadCacheFile(cachePath: string, remotePath: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      CloudApi.uploadLocalFile(cachePath, remotePath, true, new Date().getTime(), {
        onSuccess: () => resolve(),
        onFailure: (msg: string) => reject(new Error(msg))
      })
    })
  }

  /**
   * 保存失败必须先把正文落到本地草稿。
   * 这时用户刚写的内容只在内存里，退出页面就没了。
   */
  private handleSaveFailure(text: string, message: string): void {
    const fileId = this.routeParam?.fileId ?? ''
    const kept = TextDraftStore.save(fileId, text)
    showToast(kept ? `保存失败：${message}，内容已存为本地草稿` : `保存失败：${message}`)
  }

  /**
   * 拉取服务端基线。返回 Promise 以便保存前等待——
   * 保存成功后若不等它就发起下一次保存，会拿保存前的旧基线跟新的服务端比，
   * 结果是对着用户自己刚做的修改弹"文件已被改动"。
   */
  private refreshBaseline(): Promise<void> {
    const fileId = this.routeParam?.fileId ?? ''
    if (fileId.length === CloudThemeToken.zero) {
      return Promise.resolve()
    }
    const pending = new Promise<void>((resolve) => {
      CloudApi.getObjectDetail(fileId, false, {
        onSuccess: (detail: ObjectDetail) => {
          this.baselineSize = detail.size
          this.baselineUpdatedAt = detail.updated_at
          this.currentSize = detail.size
          resolve()
        },
        onFailure: (msg: string) => {
          AppLogger.warn(TAG, `refresh baseline failed: ${msg}`)
          // 基线拿不到就置为未知，让冲突检测明确跳过，
          // 而不是留着一份过期数据去比对
          this.baselineSize = -1
          this.baselineUpdatedAt = ''
          resolve()
        }
      })
    })
    this.baselinePending = pending
    return pending
  }

  /** 上次保存失败留下的草稿，问一次要不要接着改 */
  private offerDraftRestore(): void {
    const fileId = this.routeParam?.fileId ?? ''
    if (fileId.length === CloudThemeToken.zero) {
      return
    }
    const draft = TextDraftStore.load(fileId)
    if (draft === undefined || draft === this.content) {
      return
    }
    showCloudConfirmDialog(this.getUIContext(), {
      title: '发现未保存的草稿',
      message: '上次保存失败，本地留有一份未提交的修改。要恢复它吗？',
      confirmText: '恢复草稿',
      cancelText: '丢弃',
      onConfirm: () => {
        this.content = draft
        this.contentRevision++
        this.editMode = this.canEdit
        this.dirty = true
        showToast('已恢复草稿，保存后才会写回云端')
      },
      onCancel: () => {
        TextDraftStore.clear(fileId)
      }
    })
  }

  private markFailed(title: string, description: string): void {
    this.failedTitle = title
    this.failedDescription = description
    this.loadState = TextLoadState.FAILED
  }

  private copyAll(): void {
    if (this.loadState !== TextLoadState.READY) {
      return
    }
    this.copyToClipboard(this.content, '已复制全文')
  }

  /** 预览里代码块的复制也走这里：网页侧 clipboard API 在本地 scheme 下不保证可用 */
  private copyToClipboard(text: string, successTip: string): void {
    if (text.length === CloudThemeToken.zero) {
      return
    }
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      showToast(successTip)
    }).catch((err: Error) => {
      AppLogger.warn(TAG, `copy failed: ${err.message ?? err}`)
      showToast('复制失败')
    })
  }
}
