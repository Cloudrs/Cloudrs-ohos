import { webview } from '@kit.ArkWeb'
import { CloudThemeToken } from '../model/CloudTheme'
import AppLogger from '../utils/AppLogger'

const TAG: string = 'CodeEditor'

/** 注入到网页 window 上的对象名，JS 侧按这个名字回调 */
const BRIDGE_NAME: string = 'cloudrsBridge'
/**
 * 按"网络协议"黑名单拦截，而不是按"本地协议"白名单放行。
 * rawfile 页面实际用什么 scheme 由系统决定，白名单一旦猜错就把自己的资源也挡了、整页空白；
 * 黑名单则无论本地资源走哪种 scheme 都能加载，同时该拦的外联一个都跑不掉。
 */
const BLOCKED_SCHEMES: string[] = ['http://', 'https://', 'ws://', 'wss://', 'ftp://', 'blob:']

export enum EditorThemeMode {
  LIGHT = 'light',
  DARK = 'dark'
}

/**
 * 供上层命令式驱动编辑器。
 * ArkTS 拿不到子组件实例，用 Scroller 那种控制器对象转一手。
 */
export class CodeEditorController {
  requestSave: () => void = () => {}
  markSaved: () => void = () => {}
  focusEditor: () => void = () => {}
  openSearch: () => void = () => {}
  gotoLine: () => void = () => {}
  markdownAction: (action: string) => void = () => {}
}

/**
 * JS → ArkTS 的桥。
 * 正文只经由 loadContent 的返回值和 saveContent 的入参流动，
 * 绝不拼进 runJavaScript 的脚本串里——文件内容是不可信数据。
 */
class EditorBridge {
  onReady: () => void = () => {}
  provideContent: () => string = () => ''
  onSave: (text: string) => void = () => {}
  onDirty: (dirty: boolean) => void = () => {}
  onCursor: (line: number, column: number) => void = () => {}
  onCopyText: (text: string) => void = () => {}
  onRequestEdit: () => void = () => {}

  ready(): void {
    this.onReady()
  }

  copyText(text: string): void {
    this.onCopyText(text)
  }

  requestEdit(): void {
    this.onRequestEdit()
  }

  /**
   * 必须是同步方法：registerJavaScriptProxy 的异步方法拿不到返回值，
   * 注册成异步时网页侧调用返回的不是 thenable，正文永远取不回来。
   * 代价是取正文期间会占住网页线程，也因此正文大小上限不能放开太多。
   */
  loadContent(): string {
    return this.provideContent()
  }

  saveContent(text: string): void {
    this.onSave(text)
  }

  notifyDirty(dirty: boolean): void {
    this.onDirty(dirty)
  }

  notifyCursor(line: number, column: number): void {
    this.onCursor(line, column)
  }

  log(level: string, message: string): void {
    if (level === 'error') {
      AppLogger.error(TAG, `web: ${message}`)
    } else if (level === 'warn') {
      AppLogger.warn(TAG, `web: ${message}`)
    } else {
      AppLogger.info(TAG, `web: ${message}`)
    }
  }
}

/**
 * CodeMirror 6 编辑器容器。
 * 对外只暴露 ArkTS 侧的属性与回调，上层不需要知道里面是个 WebView。
 */
@Component
export struct CodeEditor {
  /** 内容就绪时自增，驱动一次下发；正文本身走 contentProvider 拉取，不进装饰器 */
  @Prop @Watch('pushContent') contentRevision: number = 0
  @Prop @Watch('pushLanguage') language: string = ''
  @Prop @Watch('pushReadOnly') readOnly: boolean = true
  @Prop @Watch('pushTheme') themeMode: string = EditorThemeMode.LIGHT
  @Prop @Watch('pushLineWrap') lineWrap: boolean = true
  @Prop @Watch('pushFontSize') fontSize: number = 13
  @Prop @Watch('pushPreview') previewMode: boolean = false
  contentProvider: () => string = () => ''
  controller?: CodeEditorController
  onEditorReady?: () => void
  onDirtyChange?: (dirty: boolean) => void
  onCursorChange?: (line: number, column: number) => void
  onSaveContent?: (text: string) => void
  onCopyText?: (text: string) => void
  onRequestEdit?: () => void

  private webController: webview.WebviewController = new webview.WebviewController()
  private bridge: EditorBridge = new EditorBridge()
  private bridgeRegistered: boolean = false
  private pageReady: boolean = false

  aboutToAppear(): void {
    if (this.controller) {
      this.controller.requestSave = () => this.requestSave()
      this.controller.markSaved = () => this.markSaved()
      this.controller.focusEditor = () => this.focusEditor()
      this.controller.openSearch = () => this.runScript('cmOpenSearch()')
      this.controller.gotoLine = () => this.runScript('cmGotoLine()')
      this.controller.markdownAction =
        (action: string) => this.runScript(`cmMarkdownAction('${this.sanitizeToken(action)}')`)
    }
    this.bridge.provideContent = () => this.contentProvider()
    this.bridge.onReady = () => {
      this.pageReady = true
      AppLogger.info(TAG, 'editor ready')
      // 顺序要紧：先配语言/主题/只读，再让网页来拉正文
      this.pushLanguage()
      this.pushTheme()
      this.pushReadOnly()
      this.pushLineWrap()
      this.pushFontSize()
      this.pushContent()
      // 内容就绪前设过的 previewMode 只存在 ArkTS 侧，这里必须补发一次
      this.pushPreview()
      this.onEditorReady?.()
    }
    this.bridge.onSave = (text: string) => this.onSaveContent?.(text)
    this.bridge.onDirty = (dirty: boolean) => this.onDirtyChange?.(dirty)
    this.bridge.onCursor = (line: number, column: number) => this.onCursorChange?.(line, column)
    this.bridge.onCopyText = (text: string) => this.onCopyText?.(text)
    this.bridge.onRequestEdit = () => this.onRequestEdit?.()
  }

  aboutToDisappear(): void {
    this.pageReady = false
    if (!this.bridgeRegistered) {
      return
    }
    // 文档明确要求与 registerJavaScriptProxy 配对，否则泄漏
    try {
      this.webController.deleteJavaScriptRegister(BRIDGE_NAME)
    } catch (err) {
      AppLogger.warn(TAG, `deleteJavaScriptRegister failed: ${(err as Error)?.message ?? err}`)
    }
    this.bridgeRegistered = false
  }

  build() {
    Web({ src: $rawfile('editor/index.html'), controller: this.webController })
      .width('100%')
      .height('100%')
      .backgroundColor(CloudThemeToken.background)
      .javaScriptAccess(true)
      // 编辑器只需要跑本地脚本，其余能力一律关掉，缩小不可信内容的可用面
      .fileAccess(false)
      .domStorageAccess(false)
      .imageAccess(false)
      .onlineImageAccess(false)
      .databaseAccess(false)
      .geolocationAccess(false)
      .zoomAccess(false)
      .mixedMode(MixedMode.None)
      .horizontalScrollBarAccess(false)
      .darkMode(WebDarkMode.Off)
      // 资源全在包内，缓存没有收益；应用升级后 URL 不变，缓存反而可能让旧的 js/css 留下来
      .cacheMode(CacheMode.None)
      .onControllerAttached(() => {
        this.registerBridge()
      })
      .onInterceptRequest((event) => {
        return this.interceptRequest(event?.request)
      })
      .onErrorReceive((event) => {
        AppLogger.warn(TAG, `web error: ${event?.error?.getErrorInfo() ?? ''}`)
      })
      // 网页自己的报错(脚本异常、CSP 拦截)不接出来的话，页面白屏时无从查起
      .onConsole((event) => {
        const message = event?.message
        if (!message) {
          return false
        }
        AppLogger.info(TAG, `console[${message.getMessageLevel()}] ${message.getMessage()} @${message.getSourceId()}:${message.getLineNumber()}`)
        return false
      })
      .onPageBegin((event) => {
        AppLogger.info(TAG, `page begin: ${event?.url ?? ''}`)
      })
      .onPageEnd((event) => {
        AppLogger.info(TAG, `page end: ${event?.url ?? ''}`)
      })
  }

  private static isNetworkUrl(url: string): boolean {
    const lower = url.toLowerCase()
    return BLOCKED_SCHEMES.some((scheme: string) => lower.startsWith(scheme))
  }

  private registerBridge(): void {
    if (this.bridgeRegistered) {
      return
    }
    try {
      this.webController.registerJavaScriptProxy(
        this.bridge,
        BRIDGE_NAME,
        // loadContent 要有返回值，只能进同步列表
        ['ready', 'loadContent', 'saveContent', 'notifyDirty', 'notifyCursor',
          'copyText', 'requestEdit', 'log']
      )
      this.bridgeRegistered = true
    } catch (err) {
      AppLogger.error(TAG, `registerJavaScriptProxy failed: ${(err as Error)?.message ?? err}`)
    }
  }

  /**
   * 掐断页面的外联能力。
   * 放开网络等于给"一个精心构造的文本文件"留了外联信道——
   * 比如 Markdown 里的远程图片，能把"某文件何时被打开"发出去。
   */
  private interceptRequest(request?: WebResourceRequest): WebResourceResponse | null {
    const url = request?.getRequestUrl() ?? ''
    if (url.length === 0 || !CodeEditor.isNetworkUrl(url)) {
      return null
    }
    AppLogger.warn(TAG, `blocked network request: ${url}`)
    const response = new WebResourceResponse()
    response.setResponseCode(403)
    response.setReasonMessage('blocked')
    response.setResponseData('')
    response.setResponseMimeType('text/plain')
    response.setResponseEncoding('utf-8')
    return response
  }

  private pushContent(): void {
    // 只发信号，正文由网页反过来调 loadContent 取
    this.runScript('cmContentReady()')
  }

  private pushLanguage(): void {
    this.runScript(`cmSetLanguage('${this.sanitizeToken(this.language)}')`)
  }

  private pushTheme(): void {
    this.runScript(`cmSetTheme('${this.sanitizeToken(this.themeMode)}')`)
  }

  private pushReadOnly(): void {
    this.runScript(`cmSetReadOnly(${this.readOnly ? 'true' : 'false'})`)
  }

  private pushLineWrap(): void {
    this.runScript(`cmSetLineWrap(${this.lineWrap ? 'true' : 'false'})`)
  }

  private pushFontSize(): void {
    // 只允许整数，跟着模板串进脚本的值必须是可控的
    this.runScript(`cmSetFontSize(${Math.round(this.fontSize)})`)
  }

  private pushPreview(): void {
    this.runScript(`cmSetPreview(${this.previewMode ? 'true' : 'false'})`)
  }

  /** 保存成功后调用，把网页里的脏标记基线挪到当前内容 */
  markSaved(): void {
    this.runScript('cmMarkSaved()')
  }

  requestSave(): void {
    this.runScript('cmRequestSave()')
  }

  focusEditor(): void {
    this.runScript('cmFocus()')
  }

  /** 下发脚本里只允许出现枚举化的短标识，杜绝拼接注入 */
  private sanitizeToken(value: string): string {
    return value.replace(/[^a-zA-Z0-9_-]/g, '')
  }

  private runScript(script: string): void {
    if (!this.pageReady) {
      return
    }
    try {
      this.webController.runJavaScript(script).catch((err: Error) => {
        AppLogger.warn(TAG, `runJavaScript failed: ${script}, ${err.message ?? err}`)
      })
    } catch (err) {
      AppLogger.warn(TAG, `runJavaScript threw: ${script}, ${(err as Error)?.message ?? err}`)
    }
  }
}
