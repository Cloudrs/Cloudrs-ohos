# Text Editing Support Plan

Date: 2026-07-28

Last updated: 2026-07-29

Status: P1a and P1b done and verified against a real V4 server — files open in CodeMirror 6 inside
an ArkWeb `Web` component, and UTF-8 files can be edited and saved back. P2 not started.

## Goal

Let users open a cloud text file in the app, read it, edit it, and save it back, with syntax
highlighting and full Markdown editing. Today `TabFiles.onItemClick` only routes images and videos;
every other type falls through to `showToast('该类型不支持预览')` at
`entry/src/main/ets/pages/tabs/TabFiles.ets:3035`, so opening a `.json`, `.log`, or `.conf` file is
a dead end.

No new native (Rust) API is required at any phase.

## Existing Building Blocks

| Capability | Location | Reuse |
|---|---|---|
| Text-ish file type detection | `utils/CommonUtil.ets:112` | `TXT / JSON / XML / YAML / TOML / CONF / MARKDOWN / CODE` are already classified; deciding "is this editable" is free |
| Fetch file bytes into memory | `pages/ImagePreview.ets:72` | `getDownloadUri` → `http.request(ARRAY_BUFFER, maxLimit)` is proven in image preview; text reuses it verbatim |
| Overwrite upload | `model/net/CloudApi.ets:238`, `:247` | Both `getUploadUri` and `uploadLocalFile` already take an `overwrite` flag |
| Create empty file | `model/net/CloudApi.ets:182` | `newObject(path, false)` already has a UI entry, enabling "create then edit" |
| Page routing | `pages/Index.ets:327`, `:360` | Overlay builder + `NavDestination` builder; adding a page is template work |
| Keyboard avoidance | `Constant.KEYBOARD_HEIGHT_VP:144` | Global keyboard height is already tracked and published |
| Local temp files | `utils/FileSystemUtil.ets` | Write / delete / mtime helpers are all present |

## Constraints

- `cloudreve-api-native/` is an uninitialized submodule, the `.so` files are checked-in prebuilt
  artifacts, and `build-ohos.ps1` is a Windows PowerShell script that depends on a local
  `cloudreve-api` crate. Any design that needs a new native function becomes disproportionately
  expensive. This plan stays inside the existing native surface.
- ArkUI has no virtualized text editing control. `TextArea` renders the whole document, which caps
  the file sizes an ArkUI-native implementation can serve.
- ArkUI text selection cannot span component boundaries. Any layout that splits the document across
  components to gain virtualization loses cross-line selection.
- `TextArea` cannot colorize text, so syntax highlighting is out of reach without `RichEditor`.

Together these three make "unlimited size + line numbers + cross-line selection + syntax
highlighting" unreachable in ArkUI without hand-writing a selection model and a tokenizer. That is
what pushes the editor into a WebView; see the architecture section below.

## Design

These three pieces are engine-independent: they were built in P0 and survive the move to CodeMirror
unchanged. The rendering half of the design lives in the P1 architecture section below.

### Routing

Registered the same way `VIDEO_PREVIEW_PAGE` is — done in P0:

- `model/Constant.ets` — `TEXT_PREVIEW_PAGE` plus the size cap.
- `model/Params.ets` — `TextPreviewParam(fileName, fileId, fileSize)`; gains a `readOnly` flag in P1b.
- `pages/Index.ets` — one branch in `overlayBuilder`, one in `destinationBuilder`.
- `pages/tabs/TabFiles.ets` and `pages/FileSearchPage.ets` — dispatch through
  `utils/TextPreviewEntry.ets` so the size gate lives in one place. A `FileMenuType.EDIT` entry can
  be added in P1b; the existing "预览" menu item already reaches the page.

### Read path

`getDownloadUri(fileId)` → `http` GET as `ARRAY_BUFFER` with an explicit `maxLimit` → decode through
`utils/TextFileCodec.ets` → hand to the editor over the bridge.

### Write path

Encode the buffer, restoring the original BOM and line endings → `FileSystemUtil.writeArrayBuffer`
into `cacheDir` → upload with `overwrite = true` → delete the cache file → refresh the directory
listing.

## Risks And Decisions

### 1. Which upload path saves the file

`CloudApi.uploadLocalFile()` (the non-chunked direct upload) currently has **zero callers** in the
app, so it is unverified code. `UploadManager.enqueue` (`utils/UploadManager.ets:52`) is the proven
path but it is heavy: chunked session, `TransferDatabase` record, and an entry in the transfer list
UI, which reads oddly for saving a 2KB config file.

Decision: verify `uploadLocalFile` against both V3 and V4 backends first. If it does not hold up, add
a `uploadSmallFileSilently()` to `UploadManager` that reuses the proven chunked path without
registering a transfer-list entry.

### 2. Encoding

`util.TextDecoder` supports `gbk`, `gb18030`, `big5`, and the UTF-16 variants — confirmed against the
API reference and exercised on a HarmonyOS 6.1.1 emulator by `TextFileCodec.test.ets`. P0 therefore
detects encoding rather than assuming UTF-8: BOM first, then strict UTF-8, then strict GBK, and
anything that fails all three is reported as non-text instead of being rendered with replacement
characters.

Decision for P1: if the detected encoding is not UTF-8, keep the file **read-only** and say so.
Writing UTF-8 back over a GBK file corrupts user data, which is far worse than refusing to edit.
`TextDecodeResult.hasBom` already carries what a future write path needs to restore the BOM.

CRLF must be round-tripped as-is; normalizing line endings turns one save into a whole-file diff.

### 3. File size

`TextArea` renders the entire document, and there is no virtualized alternative in ArkUI.

Decision: hard thresholds — under 512KB editable, 512KB to 2MB read-only, over 2MB no entry point at
all. Very large files have no cheap solution and are explicitly out of scope.

P0 first tried to dodge this with a `List` + `LazyForEach` of per-line `Text` components, which
renders only visible lines. That was reverted after testing: text selection in ArkUI cannot span
component boundaries, so a line-per-component layout makes cross-line mouse selection impossible —
a basic capability for a viewer, and not worth trading away for render volume. The viewer now puts
the whole document in one `Text`, which makes `TEXT_PREVIEW_MAX_BYTES` a genuine full-render budget:
if large files feel sluggish, that constant is the dial to turn down.

Note for whoever wires up selection elsewhere: `copyOption` alone is not enough. Mouse drag
selection and Ctrl+C also need `textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)`.

**Superseded for P1.** Once the document renders in CodeMirror, virtualization and selection stop
being a trade-off against each other, so the size ceiling is set by the in-memory download and by
how much text the bridge can hand across at once — not by rendering. Re-measure and raise
`TEXT_PREVIEW_MAX_BYTES` after the editor lands, rather than carrying the ArkUI-era number forward
unexamined.

### 4. Concurrent overwrite

`overwrite = true` blindly replaces whatever is on the server. The native layer does not expose
Cloudreve V4 version control.

Decision: before saving, call `getObjectDetail(id)` and compare size/mtime against what was loaded.
On a mismatch, prompt the user to overwrite or save as a new file.

### 5. Save atomicity and drafts

`utils/UploadManager.ets:340` carries a comment about a failed upload leaving a 0KB placeholder on
the server, so this failure mode has already been observed in this project. For text editing the same
failure means **direct loss of user-authored content**.

Decision: on save failure, persist the buffer as a draft under `filesDir` and restore it when the
page reopens. This is mandatory for phase P1, not a nice-to-have.

### 6. Back navigation and 2in1

The unsaved-changes guard must cover both exits: `CloudRouter.pop()` in overlay mode and
`NavDestination.onBackPressed` in phone mode. On 2in1, Ctrl+S should save — the project already has a
precedent for external keyboard handling (commit `f37919a`, enter key on the login page).

### 7. Syntax highlighting

`TextArea` cannot colorize. `RichEditor` can, but its performance and caret behavior are poor for
this use and it would require writing a tokenizer.

Decision: out of scope for the ArkUI-native P0, and the reason P1 moves to CodeMirror rather than
growing the ArkUI implementation. Highlighting and Markdown then come from language packages instead
of hand-written tokenizers.

## P1 Architecture: CodeMirror 6 Inside ArkWeb

### Why a WebView

The requirements that arrived after P0 — editing, save, full Markdown editing, syntax highlighting —
each individually have no cheap ArkUI answer, and together they add up to writing a text editor
engine: a virtualized viewport, a selection model, an undo stack, and a tokenizer. CodeMirror 6 is
that engine, already written and hardened, and it brings virtualization, its own selection model,
line numbers, find/replace, and language modes as one package.

Note the shape of the argument: a WebView rendering hand-written HTML would *not* solve the size
problem, because windowing the DOM breaks selection exactly the way splitting ArkUI components does.
The win comes from the editor library's own selection model, not from the browser.

Rejected alternatives: Monaco (multi-MB, desktop-oriented, poor touch/IME on mobile); Ace (drop-in
prebuilt, no build step, but a much older codebase and weaker mobile input); hand-rolled ArkUI
selection (estimated 2–3 days plus indefinite interaction polish, and it still leaves syntax
highlighting and Markdown unsolved).

### Asset layout and build

CodeMirror 6 ships as ESM packages and needs a bundler. Bundle it **once, offline**, and commit the
product — the same convention the repo already uses for the prebuilt Rust `.so` files in
`entry/libs/`, which are deliberately version-controlled so day-to-day builds need no extra
toolchain.

```
web-editor/                             bundler sources, not part of the HAP
  package.json                          pinned CodeMirror 6 deps + lockfile, committed
  rollup.config.mjs
  src/main.js                           editor construction + the JS half of the bridge
entry/src/main/resources/rawfile/editor/
  index.html                            shell, no inline content
  editor.js                             committed build product
  editor.css                            theme variables
```

Rules: the build output is committed and must not be added to `.gitignore`; dependency versions are
pinned and the lockfile committed so the bundle is reproducible; `THIRD_PARTY_NOTICES.md` gains the
CodeMirror 6 entry (MIT). Bundle size depends on which language packages are included — measure
after the first build and treat the language list as the size dial.

Initial language set: markdown, json, xml, html, css, javascript/typescript, yaml, python, java,
c/cpp, rust, go, sql. Everything else falls back to plain text with no highlighting.

Measured after the first build: **872KB** minified for the full set. hvigor stores `rawfile` assets
**uncompressed**, so that is a straight 872KB of app size — roughly 4% on top of the current 22.8MB
HAP. The grammars dominate; by installed package size the largest are markdown, cpp, javascript,
rust, and java. Dropping the long tail (rust, go, java, cpp, sql, python) would cut this
substantially and is the dial to turn if app size matters more than highlighting breadth.

### Component structure

- `components/CodeEditor.ets` — owns the `Web` component and its `WebviewController`, and exposes a
  narrow ArkTS API (`setTheme`, `setReadOnly`, `setLanguage`, `requestSave`, `focus`). Nothing above
  it needs to know a WebView exists.
- `pages/TextPreview.ets` — keeps its current job: routing param, header, status bar, load/error
  states, save orchestration. Its single-`Text` body is replaced by `CodeEditor`.
- `utils/TextFileCodec.ets` — unchanged for reading; gains `encode()` for the write path.
- `utils/TextPreviewEntry.ets` — unchanged, but the size gate can be raised once CodeMirror's
  virtualization is confirmed on device. The cap then only bounds the in-memory download, not
  rendering.

### Bridge contract

The one rule that shapes this contract: **document content never travels inside a script string.**
`runJavaScript` carries control messages only. Content moves as a proxy call argument or return
value, so no amount of adversarial file content can escape into executable code.

ArkTS → JS, via `runJavaScript` (control only, all arguments are enums/booleans):

| Call | Purpose |
|---|---|
| `cmSetTheme('light' \| 'dark')` | follow the app appearance preference |
| `cmSetReadOnly(boolean)` | non-UTF-8 files and oversize files open read-only |
| `cmSetLanguage(id)` | language mode from the file extension |
| `cmRequestSave()` | ask the editor to hand the current document back |
| `cmFocus()` | focus after the page settles |

JS → ArkTS, via `registerJavaScriptProxy` on an object named `cloudrsBridge`:

| Call | Direction of data | Purpose |
|---|---|---|
| `ready()` | — | editor constructed; ArkTS then pushes theme/language/read-only |
| `loadContent()` | ArkTS → JS, async | the editor **pulls** the decoded document; keeps content out of script strings |
| `saveContent(text)` | JS → ArkTS | response to `cmRequestSave()`, and to Ctrl+S pressed inside the editor |
| `notifyDirty(boolean)` | JS → ArkTS | drives the unsaved-changes guard and the save button state |
| `notifyCursor(line, column)` | JS → ArkTS | status bar |
| `log(level, message)` | JS → ArkTS | routes editor-side errors into `AppLogger` |

**`loadContent` must be registered as a synchronous method.** Async proxy methods cannot return
values — the API reference states it twice ("异步JavaScript任务无法返回值", "异步方法无法获取返回值").
Registering it as async makes the page-side call return a non-thenable, so the document never
arrives and the editor renders empty. That means fetching the document blocks the web thread for the
duration of the call, which is a real argument for keeping the size cap conservative rather than
raising it aggressively.

`deleteJavaScriptRegister` must be called on teardown — the API reference explicitly warns that
skipping it leaks.

### Security rules

`registerJavaScriptProxy` exposes ArkTS methods to every frame in the page, and the API reference
warns to use it only on trusted URLs. Our page is local `rawfile` content, which qualifies — but the
*file being edited* is untrusted data that lands inside that trusted page. Hence:

- Never concatenate file content into HTML or into a `runJavaScript` script string. Use the bridge.
- Register the proxy only after confirming the loaded page is our own rawfile URL; unregister on exit.
- Deny network from the page: intercept via `onInterceptRequest`. Block by **network scheme
  deny-list** (`http/https/ws/wss/ftp/blob`), not by a local-scheme allow-list — a wrong guess about
  the local scheme silently blocks the app's own assets. (The rawfile page in fact loads as
  `resource://rawfile/editor/index.html`, but the deny-list does not depend on that.) Without this
  block, a crafted Markdown file with a remote image URL turns a preview into a tracking beacon that
  leaks the fact and timing of a file being opened.
- Keep the page's meta CSP permissive for `script-src`/`style-src` on local schemes. A `'self'`-only
  policy risks being evaluated against an opaque origin and blocking `editor.js` itself; the
  exfiltration-relevant directives (`connect-src 'none'`, `img-src 'none'`) carry the real weight,
  backed by the native-side block.
- Wire up `onConsole`, `onPageBegin`, and `onPageEnd`. Without the page's own errors surfaced into
  `AppLogger`, a blank WebView is undiagnosable from the ArkTS side.
- Keep `fileAccess`, `domStorageAccess`, `onlineImageAccess`, and mixed content off; `javaScriptAccess`
  is the only capability the editor actually needs.
- The P2 Markdown preview must sanitize rendered HTML and keep the same network denial.

### Theme and appearance

The app already persists a light/dark preference (`Constant.APP_THEME_MODE`). Push it via
`cmSetTheme` on `ready()` and on every change, and drive the page's colors from CSS variables so the
editor matches the surrounding UI instead of looking like an embedded browser.

### Cold start

A `Web` instance costs noticeably more to create than a `Text`. Opening a small `.conf` will feel
slower than the P0 viewer does today. Create the component lazily (only when a text file is opened)
and tear it down on exit. If the delay is objectionable in practice, the documented mitigation is
ArkWeb's offline/pre-created `Web` component (`开发指南/ArkWeb/使用离线Web组件`), which builds the
instance ahead of time so display is immediate.

### Line endings and BOM

CodeMirror normalizes line endings to `\n` internally. The original line ending and BOM therefore
have to be reapplied by ArkTS on save, from the `TextDecodeResult.lineEnding` and `hasBom` values
that `TextFileCodec` already records at load time. Without this, opening and saving a CRLF file
rewrites every line.

## Phases

| Phase | Content | Estimate | Risk |
|---|---|---|---|
| P0 read-only viewer (ArkUI) | **Done.** Decoding, routing, dispatch, single-`Text` body | ~1 day | Very low, no writes |
| P1a editor shell, read-only | `web-editor/` bundle, rawfile assets, `CodeEditor.ets`, bridge, theme, network denial | 1–1.5 days | Medium — first WebView in the app |
| P1b editing and save | **Done.** `encode()` with BOM/EOL restore, upload path, conflict check, dirty guard, draft recovery | 1.5–2 days | Medium — upload path still unverified |
| P2 | **Done.** Markdown preview, find/replace, goto line, font size, soft-wrap toggle, encoding switch, create-then-edit | 0.5–1 day each | Low |

Split P1 deliberately. P1a swaps the rendering engine while the feature stays read-only, so the
WebView, the bridge, the theme, the cold-start cost, and large-file behavior all get proven with no
way to damage a user's file. P1b then adds writes on top of a shell already known to work, which
keeps the two genuinely risky things — a new rendering stack and a first-ever write path — from
failing at the same time.

The P0 ArkUI viewer is not kept as a fallback. Two rendering paths for one feature would double the
maintenance for a case that should instead surface as an honest error.

## What P0 Shipped

- `utils/TextFileCodec.ets` — BOM detection, strict UTF-8 → strict GBK encoding probe, NUL-byte
  binary rejection, line-ending detection, line splitting.
- `pages/TextPreview.ets` — read-only viewer: the whole document in a single `Text`, a
  copy-whole-file action, and a status bar showing encoding, line ending, line count, and size.
- `utils/TextPreviewEntry.ets` — the shared entry point holding the size gate, used by both the file
  list and search results so the threshold cannot drift between them.
- `CommonUtil.isTextViewable` — which `FileType` values get the viewer.
- Route registration in `Constant`, `Params`, and both builders in `pages/Index.ets`.

Verified: `devecocli build` clean with no new warnings; `TextFileCodec.test.ets` 13/13 and the full
`entry@ohosTest` suite 34/34 on a HarmonyOS 6.1.1 emulator; app launches without regression. The
viewer's own UI has not been exercised end-to-end — that needs a logged-in Cloudreve server.

Incidental fix: the three pre-existing `ohosTest` files imported `../../../../main/ets/...`, one
level too deep, so the whole test module failed to compile on master. Corrected to `../../../main/`.

## What P1a Shipped

- `web-editor/` — CodeMirror 6 sources, pinned deps, rollup config. `npm run build` emits straight
  into `rawfile/editor/`.
- `entry/src/main/resources/rawfile/editor/` — `index.html` (with a restrictive CSP), `editor.css`
  (light/dark variables), and the committed `editor.js` bundle.
- `components/CodeEditor.ets` — `Web` host, bridge registration and teardown, capability lockdown,
  non-local request blocking, and the control-only script pushers.
- `pages/TextPreview.ets` — body swapped from the single `Text` to `CodeEditor`; the editor mounts
  during download so WebView warm-up overlaps the network fetch; status bar gained a cursor readout.
- `CommonUtil.getEditorLanguage` — extension → language id, kept in step with the JS `LANGUAGES` map.

Measured in a desktop browser against the built bundle (the in-app path still needs a logged-in
server):

- A **17MB / 200,000-line** document loads in roughly 0.4s and renders **73 line elements / 610 DOM
  nodes total**. Virtualization is doing exactly what the architecture bet on: DOM cost is bound by
  viewport, not by file size.
- Scrolling deep into that document keeps the rendered element count flat at 73, though a jump to an
  arbitrary far offset costs a few hundred ms of main-thread work.
- A single mouse drag selected **11 lines** in one gesture — the capability that ArkUI could not
  provide and that motivated the whole move.
- Line numbers, JS/Markdown highlighting, dark theme switching, `contenteditable=false` read-only
  enforcement, and the cursor callback all verified working.

## What P1b Shipped

- `TextFileCodec.encode()` + `isWritableEncoding()` — restores the original line endings and BOM on
  write. `MIXED` line endings fall back to LF, since there is no faithful original to restore.
- `utils/TextDraftStore.ets` — failed saves persist the buffer under `filesDir/text_drafts/`, and
  reopening the same file offers to restore it.
- `pages/TextPreview.ets` — an explicit 编辑 / 保存 toggle rather than always-editable, so a remote
  file cannot be modified by an accidental tap; conflict check against a baseline captured at load;
  save → encode → cache file → overwrite upload → clear draft → refresh baseline → notify the file
  list to refresh.
- `CloudRouter.setExitGuard` / `popForced` / `interceptBack` — one guard covering all three exits
  (page back button, system back in overlay mode, `NavDestination.onBackPressed` in phone mode).
- `CodeEditorController` — lets the page drive the editor imperatively (request save, mark saved,
  focus), since ArkTS cannot call methods on a child component instance.
- Ctrl/Cmd+S inside the editor. Both are bound explicitly rather than relying on CodeMirror's
  `Mod` key resolving correctly from the WebView's user agent.
- `ic_pencil.svg` — the icon set had no pencil; authored to match `ic_copy.svg`'s style.

Verified: 42/42 in `entry@ohosTest` on a HarmonyOS 6.1.1 emulator, including six new encode
round-trip tests (CRLF restored, BOM restored and not duplicated into the body, CR, MIXED→LF).
In the browser, against the real bundle: typing raises `dirty:true`, Ctrl+S delivers the edited text
through `saveContent`, and `cmMarkSaved()` clears the dirty flag.

Verified on a live V4 server afterwards: edit → save → reopen returns the edited content. Two bugs
surfaced only at that stage, both from assuming an API's behaviour instead of checking it:

1. `loadContent` was registered in `asyncMethodList`, and async proxy methods cannot return values,
   so the editor always rendered an empty document. Fixed by registering it synchronously.
2. The upload target was built with `CloudApi.getTotalPath(item)`, which returns the parent directory
   for files. The write landed on the folder and the server answered `40004 Object existed`.

The draft store proved its worth during that failure — the log shows the unsaved text was persisted
rather than lost.

Also fixed: the status bar read the file size from the route param, which goes stale the moment a
save succeeds. It now uses the size from the refreshed `getObjectDetail` baseline.

## What P2 Shipped

All seven items, reached from one overflow menu in the header:

- **Find / replace** and **goto line** — `@codemirror/search`, which was already bundled for its
  keymap. The panel ships with browser-default control styling, so it is themed to match the app;
  note its text field carries no `type` attribute and must be selected as `.cm-textfield`.
- **Soft-wrap toggle** and **font size** (10–22px) — both persisted through `UserPreferences`, so the
  choice survives reopening.
- **Double-click to edit** — bound to two hosts, not one: the Markdown preview, and the read-only
  editor, so it works for **every** text type rather than only Markdown. On the editor it is gated on
  `state.readOnly`, checked at trigger time — once editing, a double-click must stay CodeMirror's
  select-word and not be hijacked. Mouse double-click and touch double-tap both switch into edit
  mode. Two separate paths are wired rather than one: `dblclick` for the mouse, and
  a hand-rolled time+distance double-tap detector on `pointerup` for touch, because relying on the
  engine to synthesize `dblclick` from a tap sequence is an assumption worth not making. A 500ms
  cooldown keeps the two paths from both firing on one gesture. Double-clicks landing on a code
  block's copy button are excluded — that gesture means "copy twice", not "start editing". When the
  file is not editable the double-click answers with a toast naming the reason, since a gesture that
  silently does nothing reads as broken.
- **Fenced code highlighting in preview** — ` ```c `, ` ```shell `, ` ```rust ` and friends are
  colored using the **same Lezer grammars and the same `HighlightStyle` instance the editor uses**,
  so no highlighting library is pulled in and preview colors match the editor exactly. An alias table
  maps fence names onto the bundled set (`c`/`h`/`cpp`/`cs` → cpp, `sh`/`bash`/`zsh` → shell,
  `yml` → yaml, and so on); unknown fences render as plain text rather than failing.
  `@codemirror/legacy-modes` was added for shell and toml, which have no first-party package
  (+16KB). The fence language survives sanitization through the one attribute exception in the
  allowlist: `class` on `<code>`, and only when it matches `^language-[\w+#-]+$`.
  Note `StreamLanguage.define()` returns a `Language` while the `lang-*` packages return a
  `LanguageSupport` wrapper — the highlighter has to accept both or every legacy mode silently fails.
- **Markdown preview** — every fenced code block gets a 28px icon-only copy button in its top-right
  corner, revealed on hover and swapping to a checkmark for 1.5s after a copy. The hide-until-hover
  rule lives inside `@media (hover: hover)` so that **touch devices, which never hover, keep the
  button permanently visible** — otherwise it would be unreachable on a phone. Both icons are built
  with `createElementNS`, keeping the "no `innerHTML` anywhere in preview" rule absolute. The copy
  goes through the bridge to ArkTS `pasteboard` rather than the page's `clipboard` API, whose
  availability under a local scheme is not guaranteed. The `Web` component also sets
  `cacheMode(CacheMode.None)` — the assets are all in-package, so caching buys nothing, and since the
  URL does not change across app updates it could otherwise serve a stale `editor.js`.
- **Markdown preview** — `marked` renders, but the HTML is **never** assigned via `innerHTML`. It is
  parsed into a detached document and rebuilt through a tag allowlist, dropping all attributes and
  downgrading links to plain spans. Verified with a hostile document: an embedded `<script>` did not
  execute, and `<script>`/`<img>`/`<a>` produced zero elements while headings, tables, code blocks,
  lists and blockquotes rendered normally.
- **Encoding switch** — the downloaded bytes are retained so a file can be re-decoded as UTF-8 / GBK
  / UTF-16 LE / BE without another round trip. Disabled while there are unsaved edits, since
  re-decoding replaces the whole document.
- **Create-then-edit** — creating a text file now opens it in the editor immediately, and an empty
  document starts in edit mode. Creating an empty file with no way to fill it was a dead end.

### Markdown toolbar

Markdown files open **in preview** (an empty one still opens in edit mode — there is nothing to
render), and `components/MarkdownToolbar.ets` sits directly under the title bar with a preview/edit
toggle plus twenty formatting shortcuts in six divider-separated groups: undo/redo, H1–H3,
bold/italic/strikethrough, inline code and code block, quote and bulleted/numbered/task lists,
indent/outdent, and link/image/table/rule. The row scrolls horizontally, and the formatting buttons
are disabled outside edit mode. Every button carries a `bindTips` label — the API keeps showing the
tooltip even on a disabled component, which is what makes hover-to-learn work while read-only.

**Preview-on-open needed two fixes, not one.** `previewMode` is set when the download decodes, which
usually happens *before* the editor page signals ready — and `runScript` silently drops everything
until then, so `cmSetPreview` was never delivered and the file opened as source. `pushPreview()` is
now part of the on-ready sequence. That alone is still racy in the other direction: `cmSetPreview`
renders whatever the document holds at call time, so opening preview before the content lands would
render an empty page. `setDoc()` therefore re-renders the preview whenever content arrives while
preview is active. Both orderings are now covered.

The transforms live in the editor (`cmMarkdownAction`), operating through CodeMirror transactions
rather than string surgery, so undo and multi-cursor keep working. Inline marks toggle off when
already applied, and line prefixes swap within their family — applying "task" over an existing `- `
yields `- [ ] `, not `- - [ ] `.

The icon set had none of these glyphs, so twelve were authored in `ic_md_*.svg` matching the style
of `ic_copy.svg`. They were reviewed rendered large before wiring: the first strikethrough and task
attempts were illegible at toolbar size and were redrawn.

Bundle grew from 872KB to 915KB (`marked`). Tests: 46/46, including four new `decodeAs` cases.

## Open Questions To Verify

Server-side:

- **`ObjectInfo.path` is the parent directory for files, not the object's own path.**
  `CloudApi.getTotalPath()` only builds a full path for directories; for files it returns `path`
  unchanged. Using it as an upload target sends the write at the containing folder, and the server
  answers `40004 Object existed`. Build the remote path as `${item.path}/${item.name}`, the way
  `UploadManager.enqueue` does.
- ~~Does `uploadLocalFile` with `overwrite = true` replace an existing file on V4?~~ **Confirmed
  working** once the path was correct. Verified on a live V4 server: a 14-byte file saved as 28
  bytes, and reopening it returned the new content. No fallback to the `UploadManager` chunked path
  is needed.
- Same question for V3 — still untested.
- After an overwrite upload, does the object keep its `fileId`? This affects directory refresh and
  whether a second save targets the right object.

WebView-side — still open after P1a, because they can only be answered on a device with a real
server session:

- Cold-start cost of the first `Web` instance on a mid-range device. Mounting the editor during the
  download already hides part of it; the offline pre-created component is the next lever.
- How large a string `registerJavaScriptProxy` will carry in one `loadContent` call without stalling.
  This, not rendering, is what now sets the file size ceiling — CodeMirror itself handled 17MB.
  `TEXT_PREVIEW_MAX_BYTES` stays at 2MB until this is measured.
- Whether `onInterceptRequest` returning `null` for `resource://` correctly passes through the
  bundled assets on device, and that everything else is refused.
- Whether the soft keyboard inside a `Web` cooperates with the app's existing keyboard-avoidance
  (`Constant.KEYBOARD_HEIGHT_VP`) or needs its own handling. Matters from P1b onward.

## Non-Goals

- No changes to the Rust native layer.
- No editing of non-UTF-8 files — they open read-only rather than risking a corrupting rewrite.
- No collaborative or concurrent editing; conflict handling is detect-and-prompt, not merge.
- No loading CodeMirror or any asset from the network. The bundle is committed and served from
  `rawfile`, and the page is denied network access outright.
- No second rendering path kept as a fallback once the editor lands.
