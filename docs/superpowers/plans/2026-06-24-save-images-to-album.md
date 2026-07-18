# 下载图片直存系统相册 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 文件列表的图片"下载"改为直接存入系统相册（原文件名、图库可见），预览页保存修复原文件名；非图片维持现状。

**Architecture:** 新增 `PhotoSaveUtil`（http 下原图 → `createAssetWithShortTermPermission` 短时授权 → `fileIo` 写入媒体库 uri），由 `TabFiles` 的单张/多选入口调用；纯函数 `sanitizeAlbumTitle`/`isAllImages` 放 `CommonUtil`；不触碰传输列表与 `RequestDownload`。

**Tech Stack:** ArkTS、`@kit.MediaLibraryKit`(photoAccessHelper)、`@kit.NetworkKit`(http)、`@kit.CoreFileKit`(fileIo)、内置 `LoadingProgress`、`@ohos/hypium`(测试)。

## Global Constraints

- 仅图片（`CommonUtil.getFileType(name) === FileType.IMAGE`）走相册；其它类型走原下载（`DocumentPickerMode.DOWNLOAD` 静默直存 `Download/包名/`）。
- 授权用 `createAssetWithShortTermPermission`（首次弹一次、5 分钟免弹）；**不**用 SaveButton 改造按钮、**不**用 `WRITE_IMAGEVIDEO`。
- `title` 规则：不含扩展名、长度 1~255、禁止字符 `. \ / : * ? " ' \` < > | { } [ ]`；`fileNameExtension` 不含点（`CommonUtil.getFileExtention` 已是此格式）。
- 反馈：`LoadingProgress` 遮罩 + `showToast`；不进传输列表。
- 改完用 `devecocli build` 通过 ArkTS 编译（参见 [[feedback_compile_before_done]]）。

---

### Task 1: `CommonUtil.sanitizeAlbumTitle` 与 `isAllImages`（纯函数 + 单测）

**Files:**
- Modify: `entry/src/main/ets/utils/CommonUtil.ets`（在 `CommonUtil` 类内新增两个 static 方法）
- Test: `entry/src/ohosTest/ets/test/CommonUtil.test.ets`（新建）并在 `entry/src/ohosTest/ets/test/List.test.ets` 注册

**Interfaces:**
- Produces:
  - `CommonUtil.sanitizeAlbumTitle(name: string): string`
  - `CommonUtil.isAllImages(names: string[]): boolean`

- [ ] **Step 1: 写失败测试** `CommonUtil.test.ets`

```ts
import { describe, it, expect } from '@ohos/hypium'
import { CommonUtil } from '../../../../main/ets/utils/CommonUtil'

export default function commonUtilTest() {
  describe('CommonUtil_album', () => {
    it('sanitize_stripsExtension', 0, () => {
      expect(CommonUtil.sanitizeAlbumTitle('photo.jpg')).assertEqual('photo')
    })
    it('sanitize_removesIllegalChars', 0, () => {
      expect(CommonUtil.sanitizeAlbumTitle('a/b:c*?.png')).assertEqual('abc')
    })
    it('sanitize_emptyFallback', 0, () => {
      expect(CommonUtil.sanitizeAlbumTitle('.jpg')).assertEqual('image')
      expect(CommonUtil.sanitizeAlbumTitle('')).assertEqual('image')
    })
    it('sanitize_truncates255', 0, () => {
      const long = 'a'.repeat(300) + '.jpg'
      expect(CommonUtil.sanitizeAlbumTitle(long).length).assertEqual(255)
    })
    it('isAllImages_trueWhenAllImages', 0, () => {
      expect(CommonUtil.isAllImages(['a.jpg', 'b.png'])).assertTrue()
    })
    it('isAllImages_falseWhenMixedOrEmpty', 0, () => {
      expect(CommonUtil.isAllImages(['a.jpg', 'c.pdf'])).assertFalse()
      expect(CommonUtil.isAllImages([])).assertFalse()
    })
  })
}
```

- [ ] **Step 2: 注册测试** 在 `List.test.ets` 加 `commonUtilTest()`（import 后调用，与现有 `photoGalleryModelTest()` 同样方式）。

- [ ] **Step 3: 运行测试，确认失败**（方法未定义）。Run: `devecocli build --modules entry@ohosTest`（或 IDE 运行测试），Expected: 编译/断言失败。

- [ ] **Step 4: 实现** 在 `CommonUtil` 类内新增：

```ts
static sanitizeAlbumTitle(name: string): string {
  const dot = name.lastIndexOf('.')
  let base = dot > 0 ? name.substring(0, dot) : name
  base = base.replace(/[.\\/:*?"'`<>|{}\[\]]/g, '')
  if (base.length > 255) {
    base = base.substring(0, 255)
  }
  return base.length === 0 ? 'image' : base
}

static isAllImages(names: string[]): boolean {
  return names.length > 0 && names.every((n: string) => CommonUtil.getFileType(n) === FileType.IMAGE)
}
```

- [ ] **Step 5: 运行测试，确认通过**。
- [ ] **Step 6: 提交** `git add` 两个文件并 commit（`feat: add sanitizeAlbumTitle/isAllImages`）。

---

### Task 2: `PhotoSaveUtil.saveImagesToAlbum`（核心保存工具）

**Files:**
- Create: `entry/src/main/ets/utils/PhotoSaveUtil.ets`

**Interfaces:**
- Consumes: `CommonUtil.sanitizeAlbumTitle`、`CommonUtil.getFileExtention`、`CloudApi.getDownloadUri`、`CloudApi.getBaseURL`、`ObjectInfo`。
- Produces:
  - `interface SaveAlbumResult { success: number; failed: number; canceled: boolean }`
  - `type SaveProgress = (done: number, total: number) => void`
  - `saveImagesToAlbum(items: ObjectInfo[], context: common.UIAbilityContext, onProgress?: SaveProgress): Promise<SaveAlbumResult>`

- [ ] **Step 1: 实现文件**（系统 API 为主，靠编译 + 手动验证；无独立单测）

```ts
import { common } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { ObjectInfo } from '../model/net/ApiTypes'
import { CloudApi } from '../model/net/CloudApi'
import { CommonUtil } from './CommonUtil'
import Constant from '../model/Constant'
import AppLogger from './AppLogger'

export interface SaveAlbumResult { success: number; failed: number; canceled: boolean }
export type SaveProgress = (done: number, total: number) => void

const TAG = 'PhotoSaveUtil'

function resolveDownloadUrl(id: string): Promise<string> {
  return new Promise<string>((resolve, reject) => {
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

async function writeToAlbum(phAccessHelper: photoAccessHelper.PhotoAccessHelper,
  item: ObjectInfo, buffer: ArrayBuffer): Promise<void> {
  const config: photoAccessHelper.PhotoCreationConfig = {
    title: CommonUtil.sanitizeAlbumTitle(item.name),
    fileNameExtension: CommonUtil.getFileExtention(item.name) || 'jpg',
    photoType: photoAccessHelper.PhotoType.IMAGE,
    subtype: photoAccessHelper.PhotoSubtype.DEFAULT
  }
  const uri = await phAccessHelper.createAssetWithShortTermPermission(config)
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE)
  try {
    fileIo.writeSync(file.fd, buffer)
  } finally {
    fileIo.closeSync(file)
  }
}

export async function saveImagesToAlbum(items: ObjectInfo[], context: common.UIAbilityContext,
  onProgress?: SaveProgress): Promise<SaveAlbumResult> {
  const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context)
  let success = 0
  let failed = 0
  const total = items.length
  for (let i = 0; i < total; i++) {
    const item = items[i]
    try {
      const url = await resolveDownloadUrl(item.id)
      const buffer = await downloadArrayBuffer(url)
      try {
        await writeToAlbum(phAccessHelper, item, buffer)
        success++
      } catch (authErr) {
        // 授权步骤失败：首张失败基本是用户拒绝授权 → 后续都会失败，整批中止
        AppLogger.error(TAG, `album write failed: ${(authErr as Error)?.message ?? authErr}`)
        failed++
        if (i === 0) {
          return { success, failed, canceled: true }
        }
      }
    } catch (err) {
      AppLogger.error(TAG, `download failed: ${(err as Error)?.message ?? err}`)
      failed++
    } finally {
      if (onProgress) {
        onProgress(i + 1, total)
      }
    }
  }
  return { success, failed, canceled: false }
}
```

- [ ] **Step 2: 验证编译** Run: `devecocli build`，Expected: PASS（确认 `Constant.PROTOCOL_HTTP_SCHEME`/`HTTPS_SCHEME`/`HTTP_STATUS_OK` 存在，参考 `ImagePreview.ets` 同名用法；若名称不符以 `ImagePreview.ets` 为准）。
- [ ] **Step 3: 提交**（`feat: add PhotoSaveUtil.saveImagesToAlbum`）。

---

### Task 3: 预览页保存修复原文件名

**Files:**
- Modify: `entry/src/main/ets/pages/ImagePreview.ets`（`saveImage()`，当前在创建 `createAssetRequest` 处）

**Interfaces:** Consumes `CommonUtil.sanitizeAlbumTitle`。

- [ ] **Step 1: 改实现** 在 `saveImage()` 内，把
```ts
let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
  photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(context, photoType, extension);
```
改为：
```ts
let createOption: photoAccessHelper.CreateOptions = {
  title: CommonUtil.sanitizeAlbumTitle(previewItem.fileName)
};
let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
  photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(context, photoType, extension, createOption);
```
并在文件顶部 import `CommonUtil`（`import { CommonUtil } from "../utils/CommonUtil"`）。

- [ ] **Step 2: 验证编译** Run: `devecocli build`，Expected: PASS。
- [ ] **Step 3: 提交**（`fix: 预览页保存使用原文件名`）。

---

### Task 4: 单张菜单文案随类型变化

**Files:**
- Modify: `entry/src/main/ets/components/ObjectItem.ets`（`fileMenu` 里 `item.type == 'file'` 分组的 DOWNLOAD 菜单项）

**Interfaces:** Consumes `CommonUtil.getFileType`、`FileType`（`ObjectItem` 已 import `CommonUtil`；需补 import `FileType`）。

- [ ] **Step 1: 改菜单项** 把
```ts
if (item.type == 'file') {
  MenuItemGroup() {
    this.commonMenuItem($r('app.string.file_download'), FileMenuType.DOWNLOAD)
  }
}
```
改为按类型选文案：
```ts
if (item.type == 'file') {
  MenuItemGroup() {
    this.commonMenuItem(
      CommonUtil.getFileType(item.name) === FileType.IMAGE
        ? $r('app.string.save_to_gallery')
        : $r('app.string.file_download'),
      FileMenuType.DOWNLOAD)
  }
}
```
顶部 import 补 `FileType`：`import { CommonUtil } from "../utils/CommonUtil"` 改为 `import { CommonUtil, FileType } from "../utils/CommonUtil"`（确认 `FileType` 由 CommonUtil.ets 导出——是）。

- [ ] **Step 2: 验证编译** Run: `devecocli build`，Expected: PASS。
- [ ] **Step 3: 提交**（`feat: 图片菜单项显示"保存到相册"`）。

---

### Task 5: `TabFiles` 单张/多选分流 + loading 遮罩

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabFiles.ets`（`itemDownload`、`downloadSelectedObjects`，新增 loading 状态与遮罩、新增 `saveImagesFlow` 私有方法）

**Interfaces:** Consumes `saveImagesToAlbum`、`SaveAlbumResult`、`CommonUtil.isAllImages`、`CommonUtil.getFileType`。

- [ ] **Step 1: import 与状态** 顶部 import：
```ts
import { saveImagesToAlbum, SaveAlbumResult } from '../../utils/PhotoSaveUtil'
```
类内新增：
```ts
@State private albumSaving: boolean = false
@State private albumSaveText: string = ''
```

- [ ] **Step 2: 新增统一保存流程方法**（类内）

```ts
private async saveImagesFlow(context: common.UIAbilityContext, images: ObjectInfo[]): Promise<void> {
  if (images.length === 0) {
    return
  }
  this.albumSaving = true
  this.albumSaveText = `正在保存到相册 0/${images.length}`
  const result: SaveAlbumResult = await saveImagesToAlbum(images, context, (done: number, total: number) => {
    this.albumSaveText = `正在保存到相册 ${done}/${total}`
  })
  this.albumSaving = false
  if (result.canceled) {
    showToast('已取消保存')
  } else if (result.failed === 0) {
    showToast(`已保存 ${result.success} 张到相册`)
  } else {
    showToast(`已保存 ${result.success} 张，${result.failed} 张失败`)
  }
}
```

- [ ] **Step 3: 改 `itemDownload`** 在取得 `context` 后，最前面加图片分流：
```ts
if (CommonUtil.getFileType(item.name) === FileType.IMAGE) {
  this.saveImagesFlow(context, [item])
  return
}
```
（其余原 `documentViewPicker` 逻辑保持不变。确认 `CommonUtil`、`FileType` 已 import。）

- [ ] **Step 4: 改 `downloadSelectedObjects`** 在算出 `selectedFiles` 后、进入 `documentViewPicker` 之前加：
```ts
if (CommonUtil.isAllImages(selectedFiles.map((f: ObjectInfo) => f.name))) {
  this.saveImagesFlow(context, selectedFiles).then(() => this.exitMultiSelectMode())
  return
}
```
注意：`context` 当前在 try 块内获取，把上面判断放在 `context` 取得之后；其余原逻辑保持不变。

- [ ] **Step 5: 加 loading 遮罩** 在 `build()` 最外层容器（页面根 `Stack`/`Column`）末尾加条件遮罩：
```ts
if (this.albumSaving) {
  Column({ space: 12 }) {
    LoadingProgress().width(48).height(48).color(Color.White)
    Text(this.albumSaveText).fontColor(Color.White).fontSize(14)
  }
  .width('100%').height('100%')
  .justifyContent(FlexAlign.Center)
  .backgroundColor('rgba(0,0,0,0.45)')
  .position({ x: 0, y: 0 })
  .hitTestBehavior(HitTestMode.Block)
}
```
（插入位置：页面根容器内、覆盖全屏；若根是 `Stack` 直接作为最后子组件，若是 `Column` 用 `Stack` 包裹或 `position` 覆盖。实现时按 `TabFiles.build()` 实际根容器调整。）

- [ ] **Step 6: 验证编译** Run: `devecocli build`，Expected: PASS。
- [ ] **Step 7: 提交**（`feat: 文件列表图片下载改为存入系统相册`）。

---

### Task 6: 编译 + 设备验证

- [ ] **Step 1: 全量编译** Run: `devecocli build`，Expected: PASS。
- [ ] **Step 2: 安装运行**（有模拟器/设备时）Run: `devecocli run`（参考 [[reference_device_targets]]）。
- [ ] **Step 3: 手动验证**
  - 单张图片菜单显示"保存到相册"→ 点击 → 首次弹授权 → 同意 → 图库可见、名称为原文件名。
  - 多选全图片 → loading → 仅首张弹授权 → Toast"已保存 N 张到相册"。
  - 多选含非图片 → 走原下载（静默存 Download 目录）。
  - 预览页保存 → 图库名称为原文件名。
  - 拒绝授权 → Toast"已取消保存"。
- [ ] **Step 4: 最终提交/收尾**（如未分步提交则总提交）。

---

## Self-Review

- **Spec 覆盖**：预览页文件名(Task3)✓、单张图片存相册(Task4 文案 + Task5 分流)✓、多选全图存相册(Task5)✓、混合走原下载(Task5)✓、loading+toast(Task5)✓、短时授权(Task2)✓、命名清洗(Task1)✓、仅图片(Global + Task1 isAllImages)✓。
- **Placeholder**：无 TBD；tricky 代码均给出。`Constant` 常量名以 `ImagePreview.ets` 现有用法为准（Task2 Step2 已注明核对）。
- **类型一致**：`saveImagesToAlbum`/`SaveAlbumResult`/`SaveProgress`、`sanitizeAlbumTitle`/`isAllImages` 在各任务签名一致。
- **风险点**：`createAssetWithShortTermPermission` 拒绝授权的错误码未精确判定，用"首张失败即视为取消"近似（实现时如发现明确错误码可细化）；loading 遮罩插入点依 `build()` 实际根容器调整。
