import { EditorState, Compartment } from '@codemirror/state'
import {
  EditorView, lineNumbers, highlightActiveLine, highlightActiveLineGutter,
  drawSelection, rectangularSelection, keymap
} from '@codemirror/view'
import {
  defaultKeymap, history, historyKeymap, indentWithTab, undo, redo, indentMore, indentLess
} from '@codemirror/commands'
import {
  searchKeymap, highlightSelectionMatches, search, openSearchPanel, gotoLine
} from '@codemirror/search'
import { marked } from 'marked'
import {
  HighlightStyle, syntaxHighlighting, indentUnit, StreamLanguage,
  bracketMatching, foldGutter, foldKeymap
} from '@codemirror/language'
import { tags as t, highlightTree } from '@lezer/highlight'
import { shell } from '@codemirror/legacy-modes/mode/shell'
import { toml } from '@codemirror/legacy-modes/mode/toml'

import { markdown } from '@codemirror/lang-markdown'
import { json } from '@codemirror/lang-json'
import { xml } from '@codemirror/lang-xml'
import { html } from '@codemirror/lang-html'
import { css } from '@codemirror/lang-css'
import { javascript } from '@codemirror/lang-javascript'
import { yaml } from '@codemirror/lang-yaml'
import { python } from '@codemirror/lang-python'
import { java } from '@codemirror/lang-java'
import { cpp } from '@codemirror/lang-cpp'
import { rust } from '@codemirror/lang-rust'
import { go } from '@codemirror/lang-go'
import { sql } from '@codemirror/lang-sql'

// 语言 id 由 ArkTS 侧按扩展名给出，认不出就是纯文本、不高亮。
const LANGUAGES = {
  markdown: markdown,
  json: json,
  xml: xml,
  html: html,
  css: css,
  javascript: () => javascript(),
  typescript: () => javascript({ typescript: true }),
  yaml: yaml,
  python: python,
  java: java,
  cpp: cpp,
  rust: rust,
  go: go,
  sql: sql,
  shell: () => StreamLanguage.define(shell),
  toml: () => StreamLanguage.define(toml)
}

/**
 * ``` 围栏后面写的语言名 → LANGUAGES 的键。
 * 认不出的语言不报错，按纯文本渲染即可。
 */
const FENCE_ALIASES = {
  c: 'cpp', 'c++': 'cpp', cc: 'cpp', cpp: 'cpp', h: 'cpp', hpp: 'cpp', cxx: 'cpp', objc: 'cpp',
  cs: 'cpp', csharp: 'cpp',
  rs: 'rust', rust: 'rust',
  go: 'go', golang: 'go',
  py: 'python', python: 'python', python3: 'python',
  js: 'javascript', javascript: 'javascript', mjs: 'javascript', cjs: 'javascript', node: 'javascript',
  jsx: 'javascript',
  ts: 'typescript', typescript: 'typescript', tsx: 'typescript', ets: 'typescript',
  java: 'java', kt: 'java', kotlin: 'java',
  json: 'json', json5: 'json',
  yaml: 'yaml', yml: 'yaml',
  toml: 'toml', ini: 'toml', conf: 'toml',
  xml: 'xml', svg: 'xml', plist: 'xml',
  html: 'html', htm: 'html', vue: 'html',
  css: 'css', scss: 'css', sass: 'css', less: 'css',
  sql: 'sql', mysql: 'sql', postgres: 'sql', postgresql: 'sql',
  sh: 'shell', bash: 'shell', zsh: 'shell', shell: 'shell', console: 'shell', powershell: 'shell',
  ps1: 'shell', bat: 'shell', dockerfile: 'shell', makefile: 'shell',
  md: 'markdown', markdown: 'markdown'
}

const languageConf = new Compartment()
const themeConf = new Compartment()
const readOnlyConf = new Compartment()
const wrapConf = new Compartment()

/** 高亮配色跟着 editor.css 的 CSS 变量走，明暗两套共用一份 tag 映射 */
function buildHighlightStyle() {
  const c = (name) => `var(${name})`
  return HighlightStyle.define([
    { tag: [t.keyword, t.moduleKeyword, t.controlKeyword], color: c('--cm-keyword') },
    { tag: [t.string, t.special(t.string)], color: c('--cm-string') },
    { tag: [t.number, t.bool, t.null], color: c('--cm-number') },
    { tag: [t.comment, t.lineComment, t.blockComment], color: c('--cm-comment'), fontStyle: 'italic' },
    { tag: [t.propertyName, t.attributeName], color: c('--cm-property') },
    { tag: [t.typeName, t.className, t.namespace], color: c('--cm-type') },
    { tag: [t.function(t.variableName), t.function(t.propertyName)], color: c('--cm-function') },
    { tag: [t.operator, t.punctuation, t.separator], color: c('--cm-operator') },
    { tag: [t.tagName], color: c('--cm-tag') },
    { tag: [t.heading], color: c('--cm-heading'), fontWeight: 'bold' },
    { tag: [t.link, t.url], color: c('--cm-link'), textDecoration: 'underline' },
    { tag: [t.emphasis], fontStyle: 'italic' },
    { tag: [t.strong], fontWeight: 'bold' },
    { tag: [t.invalid], color: c('--cm-invalid') }
  ])
}

/**
 * 单例：编辑器和 Markdown 预览共用同一份高亮样式。
 * 类名由它生成、CSS 由编辑器挂载，预览里复用同样的类名就能得到一致的配色。
 */
const highlightStyle = buildHighlightStyle()

function buildTheme() {
  return EditorView.theme({
    '&': {
      color: 'var(--cm-fg)',
      backgroundColor: 'var(--cm-bg)',
      height: '100%',
      fontSize: 'var(--cm-font-size)'
    },
    '.cm-content': {
      fontFamily: 'var(--cm-font-family)',
      caretColor: 'var(--cm-caret)'
    },
    '.cm-gutters': {
      backgroundColor: 'var(--cm-gutter-bg)',
      color: 'var(--cm-gutter-fg)',
      border: 'none'
    },
    '.cm-activeLine': { backgroundColor: 'var(--cm-active-line)' },
    '.cm-activeLineGutter': { backgroundColor: 'var(--cm-active-line)' },
    '.cm-selectionBackground, &.cm-focused .cm-selectionBackground, .cm-content ::selection': {
      backgroundColor: 'var(--cm-selection)'
    },
    '.cm-cursor, .cm-dropCursor': { borderLeftColor: 'var(--cm-caret)' },
    '.cm-scroller': { overflow: 'auto' },
    // 查找面板默认是浏览器原生控件样式，嵌在应用里很突兀
    '.cm-panels': {
      backgroundColor: 'var(--cm-bg)',
      color: 'var(--cm-fg)',
      borderBottom: '1px solid var(--cm-gutter-fg)'
    },
    '.cm-panel.cm-search': { padding: '8px 10px' },
    '.cm-panel.cm-search input, .cm-panel.cm-search button, .cm-panel.cm-search label': {
      fontFamily: 'inherit',
      fontSize: '13px'
    },
    // 查找框没有 type 属性，只能按 CodeMirror 自己的 class 选
    '.cm-panel.cm-search .cm-textfield': {
      padding: '5px 8px',
      borderRadius: '6px',
      border: '1px solid var(--cm-gutter-fg)',
      backgroundColor: 'var(--cm-bg)',
      color: 'var(--cm-fg)'
    },
    '.cm-panel.cm-search button': {
      padding: '4px 10px',
      marginLeft: '4px',
      borderRadius: '6px',
      border: '1px solid var(--cm-gutter-fg)',
      backgroundColor: 'var(--cm-bg)',
      color: 'var(--cm-fg)',
      backgroundImage: 'none'
    },
    '.cm-searchMatch': { backgroundColor: 'var(--cm-selection)' },
    '.cm-searchMatch-selected': { backgroundColor: 'var(--cm-caret)', color: 'var(--cm-bg)' }
  })
}

/** ArkTS 侧注入的对象；未注入时用空实现兜底，方便浏览器里单独调页面 */
function bridge() {
  return window.cloudrsBridge ?? {
    ready: () => {},
    loadContent: () => '',
    saveContent: () => {},
    notifyDirty: () => {},
    notifyCursor: () => {},
    copyText: () => {},
    requestEdit: () => {},
    log: () => {}
  }
}

function report(level, message) {
  try {
    bridge().log(level, String(message))
  } catch (_) {
    // 桥不可用时不能再抛，否则整个编辑器初始化就断了
  }
}

let view = null
let baselineDoc = ''
let dirty = false
let previewActive = false

function resolveLanguage(id) {
  const factory = LANGUAGES[id]
  if (!factory) {
    return []
  }
  try {
    return factory()
  } catch (err) {
    report('warn', `language ${id} failed: ${err}`)
    return []
  }
}

/** 光标位置与脏标记都要回传，状态栏和"未保存"拦截靠它 */
const changeListener = EditorView.updateListener.of((update) => {
  if (update.docChanged) {
    const nowDirty = update.state.doc.toString() !== baselineDoc
    if (nowDirty !== dirty) {
      dirty = nowDirty
      try {
        bridge().notifyDirty(dirty)
      } catch (err) {
        report('warn', `notifyDirty failed: ${err}`)
      }
    }
  }
  if (update.selectionSet || update.docChanged) {
    const head = update.state.selection.main.head
    const line = update.state.doc.lineAt(head)
    try {
      bridge().notifyCursor(line.number, head - line.from + 1)
    } catch (err) {
      report('warn', `notifyCursor failed: ${err}`)
    }
  }
})

function createView() {
  const state = EditorState.create({
    doc: '',
    extensions: [
      lineNumbers(),
      highlightActiveLineGutter(),
      highlightActiveLine(),
      foldGutter(),
      drawSelection(),
      rectangularSelection(),
      bracketMatching(),
      highlightSelectionMatches(),
      history(),
      indentUnit.of('  '),
      EditorState.allowMultipleSelections.of(true),
      wrapConf.of([EditorView.lineWrapping]),
      search({ top: true }),
      // Ctrl/Cmd+S 在网页内直接触发保存，2in1 外接键盘才有编辑器该有的手感。
      // Mod 由 CodeMirror 按 UA 决定映射到 Ctrl 还是 Cmd，这里两个都显式绑上，
      // 不赌 WebView 的 UA 判断结果。
      keymap.of(['Mod-s', 'Ctrl-s'].map((key) => ({
        key,
        preventDefault: true,
        run: () => {
          window.cmRequestSave()
          return true
        }
      }))),
      keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap, ...foldKeymap, indentWithTab]),
      changeListener,
      syntaxHighlighting(highlightStyle),
      buildTheme(),
      languageConf.of([]),
      themeConf.of([]),
      readOnlyConf.of([EditorState.readOnly.of(true), EditorView.editable.of(false)])
    ]
  })
  return new EditorView({ state, parent: document.getElementById('editor') })
}

function setDoc(text) {
  baselineDoc = text
  dirty = false
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text }
  })
  // 预览可能在正文到达之前就被打开了（ArkTS 侧下发顺序不保证），
  // 那时渲染的是空文档，正文一到必须重渲染一次，否则就是一片空白
  if (previewActive) {
    renderPreview()
  }
}

// ---- ArkTS → JS。只收控制指令，正文一律走 loadContent 拉取 ----

window.cmContentReady = function () {
  // 同步注册的代理方法直接返回字符串；用 Promise.resolve 兜住两种形态，
  // 不赌宿主到底给的是值还是 thenable
  try {
    Promise.resolve(bridge().loadContent())
      .then((text) => {
        setDoc(typeof text === 'string' ? text : '')
      })
      .catch((err) => {
        report('error', `loadContent failed: ${err}`)
      })
  } catch (err) {
    report('error', `loadContent threw: ${err}`)
  }
}

window.cmSetLanguage = function (id) {
  view.dispatch({ effects: languageConf.reconfigure(resolveLanguage(id)) })
}

window.cmSetTheme = function (mode) {
  document.documentElement.setAttribute('data-theme', mode === 'dark' ? 'dark' : 'light')
}

window.cmSetReadOnly = function (flag) {
  const on = flag === true || flag === 'true'
  view.dispatch({
    effects: readOnlyConf.reconfigure([
      EditorState.readOnly.of(on),
      EditorView.editable.of(!on)
    ])
  })
}

window.cmRequestSave = function () {
  try {
    bridge().saveContent(view.state.doc.toString())
  } catch (err) {
    report('error', `saveContent failed: ${err}`)
  }
}

/** 保存成功后把基线挪到当前内容，脏标记才会归零 */
window.cmMarkSaved = function () {
  baselineDoc = view.state.doc.toString()
  if (dirty) {
    dirty = false
    try {
      bridge().notifyDirty(false)
    } catch (err) {
      report('warn', `notifyDirty failed: ${err}`)
    }
  }
}

window.cmFocus = function () {
  view.focus()
}

window.cmOpenSearch = function () {
  openSearchPanel(view)
}

window.cmGotoLine = function () {
  gotoLine(view)
}

window.cmSetLineWrap = function (flag) {
  const on = flag === true || flag === 'true'
  view.dispatch({ effects: wrapConf.reconfigure(on ? [EditorView.lineWrapping] : []) })
}

window.cmSetFontSize = function (px) {
  const size = Number(px)
  if (!Number.isFinite(size) || size <= 0) {
    return
  }
  document.documentElement.style.setProperty('--cm-font-size', `${size}px`)
  view.requestMeasure()
}

/**
 * Markdown 预览。
 * 渲染结果不用 innerHTML 直接塞，先解析成游离文档再按白名单重建节点——
 * 正文是不可信数据，marked 的输出里可能带有源文件写进去的原始 HTML。
 */
window.cmSetPreview = function (flag) {
  previewActive = flag === true || flag === 'true'
  renderPreview()
}

function renderPreview() {
  const host = document.getElementById('preview')
  const editorHost = document.getElementById('editor')
  if (!host || !editorHost) {
    return
  }
  if (!previewActive) {
    host.style.display = 'none'
    editorHost.style.display = ''
    host.replaceChildren()
    return
  }
  try {
    const html = marked.parse(view.state.doc.toString(), { async: false, gfm: true, breaks: false })
    const fragment = sanitizeToFragment(html)
    decorateCodeBlocks(fragment)
    host.replaceChildren(fragment)
    editorHost.style.display = 'none'
    host.style.display = ''
    host.scrollTop = 0
  } catch (err) {
    report('error', `markdown preview failed: ${err}`)
  }
}

/** 行内包裹类：已包裹则取消，未包裹则加上；无选区时插入标记并把光标放中间 */
function toggleInlineMark(mark) {
  const state = view.state
  const changes = []
  let cursorTarget = null
  for (const range of state.selection.ranges) {
    const before = state.sliceDoc(Math.max(0, range.from - mark.length), range.from)
    const after = state.sliceDoc(range.to, Math.min(state.doc.length, range.to + mark.length))
    if (before === mark && after === mark) {
      changes.push({ from: range.from - mark.length, to: range.from, insert: '' })
      changes.push({ from: range.to, to: range.to + mark.length, insert: '' })
      continue
    }
    changes.push({ from: range.from, insert: mark })
    changes.push({ from: range.to, insert: mark })
    if (range.empty) {
      cursorTarget = range.from + mark.length
    }
  }
  const spec = { changes }
  if (cursorTarget !== null) {
    spec.selection = { anchor: cursorTarget }
  }
  view.dispatch(spec)
}

/** 行首前缀类：整行加/去前缀，多行选区逐行处理 */
function toggleLinePrefix(prefixFor) {
  const state = view.state
  const changes = []
  const seen = new Set()
  for (const range of state.selection.ranges) {
    const startLine = state.doc.lineAt(range.from).number
    const endLine = state.doc.lineAt(range.to).number
    for (let n = startLine; n <= endLine; n++) {
      if (seen.has(n)) {
        continue
      }
      seen.add(n)
      const line = state.doc.line(n)
      const prefix = prefixFor(n - startLine + 1)
      // 去掉时要连同同族的其它前缀一起匹配，避免 "- " 与 "1. " 叠加
      const existing = line.text.match(/^(\s*)([-*+]\s\[[ xX]\]\s|[-*+]\s|\d+\.\s|>\s|#{1,6}\s)?/)
      const indent = existing ? existing[1] : ''
      const current = existing && existing[2] ? existing[2] : ''
      const body = line.text.slice(indent.length + current.length)
      const next = current === prefix ? body : `${prefix}${body}`
      changes.push({ from: line.from, to: line.to, insert: `${indent}${next}` })
    }
  }
  view.dispatch({ changes })
}

function insertBlock(text) {
  const range = view.state.selection.main
  const line = view.state.doc.lineAt(range.to)
  const needsLeading = line.text.trim().length > 0
  const insert = `${needsLeading ? '\n' : ''}${text}\n`
  view.dispatch({
    changes: { from: line.to, insert },
    selection: { anchor: line.to + insert.length }
  })
}

function wrapCodeBlock() {
  const range = view.state.selection.main
  const selected = view.state.sliceDoc(range.from, range.to)
  const insert = `\`\`\`\n${selected}\n\`\`\``
  view.dispatch({
    changes: { from: range.from, to: range.to, insert },
    // 空选区时把光标放进围栏里，直接可以敲代码
    selection: { anchor: range.from + 4 + selected.length }
  })
}

function insertLink() {
  const range = view.state.selection.main
  const selected = view.state.sliceDoc(range.from, range.to)
  const insert = `[${selected}](url)`
  view.dispatch({
    changes: { from: range.from, to: range.to, insert },
    // 选中 url 占位符，接着输入即可替换
    selection: { anchor: range.from + selected.length + 3, head: range.from + selected.length + 6 }
  })
}

function insertImage() {
  const range = view.state.selection.main
  const selected = view.state.sliceDoc(range.from, range.to)
  const insert = `![${selected}](url)`
  view.dispatch({
    changes: { from: range.from, to: range.to, insert },
    selection: { anchor: range.from + selected.length + 4, head: range.from + selected.length + 7 }
  })
}

const TABLE_TEMPLATE = '| 列一 | 列二 |\n| --- | --- |\n|  |  |'

const MARKDOWN_ACTIONS = {
  bold: () => toggleInlineMark('**'),
  italic: () => toggleInlineMark('*'),
  strike: () => toggleInlineMark('~~'),
  code: () => toggleInlineMark('`'),
  h1: () => toggleLinePrefix(() => '# '),
  h2: () => toggleLinePrefix(() => '## '),
  h3: () => toggleLinePrefix(() => '### '),
  quote: () => toggleLinePrefix(() => '> '),
  ul: () => toggleLinePrefix(() => '- '),
  ol: () => toggleLinePrefix((index) => `${index}. `),
  task: () => toggleLinePrefix(() => '- [ ] '),
  codeblock: () => wrapCodeBlock(),
  link: () => insertLink(),
  image: () => insertImage(),
  table: () => insertBlock(TABLE_TEMPLATE),
  hr: () => insertBlock('---'),
  indent: () => indentMore(view),
  outdent: () => indentLess(view),
  undo: () => undo(view),
  redo: () => redo(view)
}

/** Markdown 工具条的统一入口，动作名由 ArkTS 侧按钮给出 */
window.cmMarkdownAction = function (action) {
  const run = MARKDOWN_ACTIONS[action]
  if (!run) {
    report('warn', `unknown markdown action: ${action}`)
    return
  }
  if (view.state.readOnly) {
    return
  }
  try {
    run()
    view.focus()
  } catch (err) {
    report('error', `markdown action ${action} failed: ${err}`)
  }
}

const ALLOWED_TAGS = new Set([
  'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'P', 'BR', 'HR', 'EM', 'STRONG', 'DEL', 'CODE', 'PRE',
  'BLOCKQUOTE', 'UL', 'OL', 'LI', 'TABLE', 'THEAD', 'TBODY', 'TR', 'TH', 'TD', 'A', 'SPAN', 'DIV'
])

/** 白名单重建：只保留认识的标签，属性一律丢弃，链接只留文字 */
function sanitizeToFragment(html) {
  const parsed = new DOMParser().parseFromString(html, 'text/html')
  const fragment = document.createDocumentFragment()
  parsed.body.childNodes.forEach((node) => {
    const clean = sanitizeNode(node)
    if (clean) {
      fragment.appendChild(clean)
    }
  })
  return fragment
}

const SVG_NS = 'http://www.w3.org/2000/svg'
/** 与 ic_copy.svg 同形，保持和应用内其它复制入口一致 */
const ICON_COPY = [
  'M8 7.5C8 6.1 9.1 5 10.5 5H18C19.4 5 20.5 6.1 20.5 7.5V15C20.5 16.4 19.4 17.5 18 17.5H10.5C9.1 17.5 8 16.4 8 15V7.5ZM10.5 6.8C10.1 6.8 9.8 7.1 9.8 7.5V15C9.8 15.4 10.1 15.7 10.5 15.7H18C18.4 15.7 18.7 15.4 18.7 15V7.5C18.7 7.1 18.4 6.8 18 6.8H10.5Z',
  'M3.5 10C3.5 8.6 4.6 7.5 6 7.5H6.6V9.3H6C5.6 9.3 5.3 9.6 5.3 10V17.5C5.3 17.9 5.6 18.2 6 18.2H13.5C13.9 18.2 14.2 17.9 14.2 17.5V16.9H16V17.5C16 18.9 14.9 20 13.5 20H6C4.6 20 3.5 18.9 3.5 17.5V10Z'
]
const ICON_CHECK = ['M9.3 16.2L4.8 11.7L6.4 10.1L9.3 13L17.6 4.7L19.2 6.3L9.3 16.2Z']

/** 用 DOM API 构图标，preview 里坚持不出现 innerHTML */
function buildIcon(paths) {
  const svg = document.createElementNS(SVG_NS, 'svg')
  svg.setAttribute('viewBox', '0 0 24 24')
  svg.setAttribute('width', '15')
  svg.setAttribute('height', '15')
  svg.setAttribute('aria-hidden', 'true')
  paths.forEach((d) => {
    const path = document.createElementNS(SVG_NS, 'path')
    path.setAttribute('d', d)
    path.setAttribute('fill', 'currentColor')
    svg.appendChild(path)
  })
  return svg
}

/**
 * 给预览里的代码块加"复制"按钮。
 * 按钮由这里自己创建，不经过正文——所以它在白名单之外也是安全的。
 * 复制走 ArkTS 的 pasteboard，不用网页 clipboard API：
 * 本地 scheme 下那套 API 是否可用没保证，而桥是已经验证过的通路。
 */
/**
 * 用编辑器同款语法树给预览里的代码块着色。
 * 复用已打包的 Lezer 语法，不额外引高亮库，配色也自然和编辑器一致。
 */
function highlightCodeBlock(code) {
  const match = (code.getAttribute('class') ?? '').match(/^language-([\w+#-]+)$/)
  if (!match) {
    return
  }
  const id = FENCE_ALIASES[match[1].toLowerCase()]
  const factory = id ? LANGUAGES[id] : undefined
  if (!factory) {
    return
  }
  const text = code.textContent ?? ''
  if (text.length === 0) {
    return
  }
  try {
    // lang-* 返回 LanguageSupport（.language 里才是 Language），
    // StreamLanguage.define 直接返回 Language 本身，两种都要认
    const support = factory()
    const language = support.language ?? support
    const tree = language.parser.parse(text)
    const fragment = document.createDocumentFragment()
    let pos = 0
    const emit = (from, to, className) => {
      if (from > pos) {
        fragment.appendChild(document.createTextNode(text.slice(pos, from)))
      }
      const span = document.createElement('span')
      if (className) {
        span.className = className
      }
      span.textContent = text.slice(from, to)
      fragment.appendChild(span)
      pos = to
    }
    highlightTree(tree, highlightStyle, emit)
    if (pos < text.length) {
      fragment.appendChild(document.createTextNode(text.slice(pos)))
    }
    code.replaceChildren(fragment)
  } catch (err) {
    report('warn', `highlight ${match[1]} failed: ${err}`)
  }
}

function decorateCodeBlocks(fragment) {
  fragment.querySelectorAll('pre code').forEach((code) => {
    highlightCodeBlock(code)
  })
  fragment.querySelectorAll('pre').forEach((pre) => {
    const wrapper = document.createElement('div')
    wrapper.className = 'code-wrap'
    const button = document.createElement('button')
    button.className = 'code-copy'
    button.type = 'button'
    // 图标没有文字说明，留个原生 title 作为悬停提示
    button.title = '复制代码'
    button.replaceChildren(buildIcon(ICON_COPY))
    let restoreTimer = 0
    button.addEventListener('click', () => {
      const code = pre.textContent ?? ''
      try {
        bridge().copyText(code)
      } catch (err) {
        report('warn', `copyText failed: ${err}`)
        return
      }
      button.replaceChildren(buildIcon(ICON_CHECK))
      button.classList.add('copied')
      clearTimeout(restoreTimer)
      restoreTimer = setTimeout(() => {
        button.replaceChildren(buildIcon(ICON_COPY))
        button.classList.remove('copied')
      }, 1500)
    })
    pre.parentNode.insertBefore(wrapper, pre)
    wrapper.appendChild(button)
    wrapper.appendChild(pre)
  })
}

function sanitizeNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    return document.createTextNode(node.nodeValue)
  }
  if (node.nodeType !== Node.ELEMENT_NODE) {
    return null
  }
  // 不认识的标签(script/iframe/img/svg/事件属性宿主)整个丢掉，只把文字留下
  const tag = ALLOWED_TAGS.has(node.tagName) ? node.tagName : null
  if (!tag) {
    return document.createTextNode(node.textContent ?? '')
  }
  // a 标签降级成普通文本容器：页面禁网，可点的链接只会带来困惑
  const el = document.createElement(tag === 'A' ? 'SPAN' : tag)
  // 唯一保留的属性：code 上的 language-xxx。
  // 围栏语言得靠它传下来，而这个正则约束死了取值，构不成注入面。
  if (tag === 'CODE') {
    const cls = node.getAttribute('class') ?? ''
    if (/^language-[\w+#-]+$/.test(cls)) {
      el.setAttribute('class', cls)
    }
  }
  node.childNodes.forEach((child) => {
    const clean = sanitizeNode(child)
    if (clean) {
      el.appendChild(clean)
    }
  })
  return el
}

/** 双击（鼠标）/ 双指点两下（触屏）预览区，直接切到编辑态 */
const DOUBLE_TAP_INTERVAL_MS = 320
const DOUBLE_TAP_SLOP_PX = 30
const EDIT_REQUEST_COOLDOWN_MS = 500

let lastTapAt = 0
let lastTapX = 0
let lastTapY = 0
let lastEditRequestAt = 0

function requestEditMode(target) {
  // 复制按钮上的双击只是连点复制，不该顺带切走
  if (target && target.closest && target.closest('.code-copy')) {
    return
  }
  const now = Date.now()
  // dblclick 与触屏兜底可能对同一次操作都触发，这里去重
  if (now - lastEditRequestAt < EDIT_REQUEST_COOLDOWN_MS) {
    return
  }
  lastEditRequestAt = now
  try {
    bridge().requestEdit()
  } catch (err) {
    report('warn', `requestEdit failed: ${err}`)
  }
}

/**
 * 给一个容器绑「双击进编辑」。
 * enabled 是每次触发时再问的，因为编辑器可读可写状态会变——
 * 可编辑时双击是选词，不能被劫持。
 */
function bindDoubleTapToEdit(host, enabled) {
  if (!host) {
    return
  }
  // 鼠标：浏览器原生的双击事件
  host.addEventListener('dblclick', (event) => {
    if (enabled()) {
      requestEditMode(event.target)
    }
  })
  // 触屏：不赌引擎一定会把双击合成成 dblclick，自己按时间+位移判定
  host.addEventListener('pointerup', (event) => {
    if (event.pointerType !== 'touch' || !enabled()) {
      return
    }
    const now = Date.now()
    const near = Math.abs(event.clientX - lastTapX) < DOUBLE_TAP_SLOP_PX &&
      Math.abs(event.clientY - lastTapY) < DOUBLE_TAP_SLOP_PX
    if (now - lastTapAt < DOUBLE_TAP_INTERVAL_MS && near) {
      lastTapAt = 0
      requestEditMode(event.target)
      return
    }
    lastTapAt = now
    lastTapX = event.clientX
    lastTapY = event.clientY
  })
}

function bindEditGestures() {
  // Markdown 预览区：任何时候双击都表示"我要改"
  bindDoubleTapToEdit(document.getElementById('preview'), () => true)
  // 编辑器：只在只读态生效。可编辑时双击是 CodeMirror 的选词，不能抢
  bindDoubleTapToEdit(document.getElementById('editor'), () => view != null && view.state.readOnly)
}

function boot() {
  try {
    view = createView()
  } catch (err) {
    report('error', `create editor failed: ${err}`)
    return
  }
  bindEditGestures()
  try {
    bridge().ready()
  } catch (err) {
    report('error', `ready failed: ${err}`)
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot)
} else {
  boot()
}
