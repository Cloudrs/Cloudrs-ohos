# 下载图片直存系统相册 — 设计文档（简化版）

- 日期：2026-06-24
- 状态：待实现（设计待用户审阅）
- 设计取向：**最小改动**——不触碰传输列表 / `RequestDownload` / 下载状态机，全程前台操作。
- 关联代码：`ImagePreview.ets`、`TabFiles.ets`、`ObjectItem.ets`、`utils/CommonUtil.ets`、`utils/FileSystemUtil.ets`、新增 `utils/PhotoSaveUtil.ets`

## 1. 背景与目标

1. 修复预览页保存使用**原始文件名**（当前 `createAssetRequest` 未传 `title`，系统自动命名）。
2. 文件列表**图片"保存到相册"**（原文件名、图库可见）：单张菜单 + 多选（全图片时）。
3. 反馈用 **loading + 结果 Toast**，**不进传输列表、不改下载逻辑**，把改动量降到最小。

## 2. 交互决策（已与用户确认）

- **单张长按菜单**：图片 → 菜单项文案显示"保存到相册"→ 存相册；非图片 → "下载"，原下载流程。
- **多选**：选中项**全部为图片** → 保存到相册（loading + Toast）；**否则**（含非图片）→ **完全保持原下载**（当前为 `DocumentPickerMode.DOWNLOAD`，跳过选择界面、静默直存 `Download/包名/`，无弹窗；混合里的图片也随之下到该目录）。不拆分混合。
- **预览页**：保留 `SaveButton` 安全控件，仅修复文件名。
- **反馈**：loading + 结果 Toast；不进传输列表。
- **授权**：`createAssetWithShortTermPermission`（首次弹一次、5 分钟内免弹）。

## 3. 技术选型（已查证 HarmonyOS 官方文档）

> **⚠️ 实现修正（落地后，经两次调整）**：①原定 `createAssetWithShortTermPermission`（短时授权）依赖 `ohos.permission.SHORT_TERM_WRITE_IMAGEVIDEO`（APL 高、当前签名无法授予）**导致安装失败**，弃用。②改用 `showAssetsCreationDialog`（弹窗授权、免权限）可安装，但**每次保存都弹确认框**，体验差。③**最终采用 `WRITE_IMAGEVIDEO` 运行时申请 + `applyChanges` 静默写入**：`abilityAccessCtrl.requestPermissionsFromUser` 首次弹一次系统权限框，授予后所有保存零弹窗；文件名用 `CreateOptions.title`。代价：WRITE_IMAGEVIDEO 受限，发布需 ACL 审批（module.json5 早已声明）。**实际实现以③为准**，下文 short-term/dialog 描述作废。

> **关键约束**：当前普通下载用 `DocumentPickerMode.DOWNLOAD`（跳过选择界面、静默直存 `Download/包名/`，无弹窗）。但官方明确：通过 Picker 保存的文件**与图库隔离、系统图库看不到**；要让图库可见，**必须**走媒体库 API（需一次授权）。这是图片不能沿用普通下载的根本原因。

保存到图库**免 `ohos.permission.WRITE_IMAGEVIDEO` 权限**。采用 **`createAssetWithShortTermPermission`（API 12+）**：

```ts
createAssetWithShortTermPermission(photoCreationConfig: PhotoCreationConfig): Promise<string>
```

- 首次调用拉起授权框；用户同意后返回**已创建并授权的媒体库 uri**，应用用 `fileIo` 写入数据。
- 用户同意后 **5 分钟内**同一应用再调用**免弹框**；退出应用结束授权。
- `PhotoCreationConfig`：`{ title, fileNameExtension, photoType: IMAGE, subtype: DEFAULT }`。

**为何不用 SaveButton 安全控件**：

- 单张菜单项是 `MenuItem`，非安全控件，无法承载 SaveButton，单张必然走弹框授权。
- 多选按钮虽可改成 SaveButton，但其授权窗口仅 **1 分钟**（API 19 及之前 10 秒）；本场景"先下载网络图片再保存"耗时不可控，批量易超窗导致部分失败。
- 短时授权同样"首次弹一次、后续免弹"，窗口 5 分钟更稳，且**无需把按钮改成安全控件**（改动更小）。

文件名规则（`title`）：**不含扩展名**，长度 1~255，禁止字符 `. \ / : * ? " ' \` < > | { } [ ]`；`fileNameExtension` 无点（如 `jpg`）。

预览页保留 `SaveButton`，仅补 `title`（避免无谓弹框）。

## 4. 详细设计

### 4.1 新增 `utils/PhotoSaveUtil.ets`

单张与多选共用一个入口：

```ts
interface SaveAlbumResult { success: number; failed: number; canceled: boolean }
type SaveProgress = (done: number, total: number) => void

saveImagesToAlbum(
  items: ObjectInfo[],
  context: common.UIAbilityContext,
  onProgress?: SaveProgress
): Promise<SaveAlbumResult>
```

流程（逐张、串行降低内存峰值）：

1. `getDownloadUri(item.id)` 取直链（相对则拼 `getBaseURL()`，与预览页一致）。
2. `http` 下载**原图**为 `ArrayBuffer`（不设 `maxLimit`）。
3. `createAssetWithShortTermPermission({ title: sanitizeAlbumTitle(item.name), fileNameExtension, photoType: IMAGE, subtype: DEFAULT })` → 媒体库 uri（**首张弹一次授权**，后续 5 分钟内免弹）。
4. `fileIo.openSync(uri, READ_WRITE)` → `fileIo.write(fd, arrayBuffer)` → `closeSync`。**无需沙箱临时文件**（直接内存写入授权 uri）。
5. `onProgress(done, total)`；单张失败计入 `failed`，不中断其余。
6. 首张授权被拒 → `canceled=true`，中止整批。
7. 返回统计。

### 4.2 命名清洗 `CommonUtil.sanitizeAlbumTitle(name)`

预览页与 `PhotoSaveUtil` 共用：去扩展名 → 过滤非法字符 → 截断 255 → 为空回退常量（如 `image`）。

### 4.3 预览页 `ImagePreview.saveImage()`

- `createAssetRequest(context, IMAGE, extension, { title: CommonUtil.sanitizeAlbumTitle(previewItem.fileName) })`，其余不变（`addResource(ArrayBuffer)` + `applyChanges` + `SaveButton`）。
- 确保 `extension` 不含点。

### 4.4 单张菜单文案与分流

- `ObjectItem.fileMenu`：`FileMenuType.DOWNLOAD` 项文案按类型动态——图片用 `app.string.save_to_gallery`（"保存到相册"，已存在），非图片用 `app.string.file_download`。判断用 `CommonUtil.getFileType`（`ObjectItem` 已 import `CommonUtil`）。
- `TabFiles` 处理 `FileMenuType.DOWNLOAD`：图片 → loading + `PhotoSaveUtil.saveImagesToAlbum([item])` → Toast；非图片 → 原下载流程（`itemDownload`，`DocumentPickerMode.DOWNLOAD` 静默直存 `Download/包名/`，无弹窗）。

### 4.5 多选 `downloadSelectedObjects()`

- `selectedFiles` = 选中非目录项。
- 若**全部** `getFileType==IMAGE` → loading + `PhotoSaveUtil.saveImagesToAlbum(selectedFiles, onProgress)` → 结果 Toast → `exitMultiSelectMode`。
- 否则 → **保持原逻辑**（`DocumentPickerMode.DOWNLOAD` 静默直存 `Download/包名/` → 各 `enqueueDownloadTask`）。

### 4.6 反馈

- loading：用现有 dialog/spinkit，文案"正在保存到相册 done/total"。
- 结果 Toast：全成功"已保存 N 张到相册"；部分失败"已保存 X 张，Y 张失败"；取消"已取消保存"。

## 5. 错误处理

- `getDownloadUri`/`http`/写入任一失败：该张计 `failed`，继续其余。
- 首张授权被拒：中止整批，Toast 提示。
- 全程前台操作（菜单/多选按钮点击触发），无后台无法弹框问题。

## 6. 边界与约束

- 仅图片（`FileType.IMAGE`）进相册；视频/文档/音频走下载。
- 多选混合不拆分，整体走原下载。
- 大图：`http` ArrayBuffer 串行下载，降低内存峰值。
- 短时授权 5 分钟窗口；超大批量跨 5 分钟可能再弹一次授权（可接受）。
- loading 期间假定用户在前台等待（简单方案取舍）。

## 7. 测试

- 单元（ohosTest）：`sanitizeAlbumTitle`（非法/超长/空）；多选"全图片"判定；菜单文案选择。
- 手动：单图菜单"保存到相册"→ 授权 → 相册可见且原名；多选全图（仅首张弹授权）；多选混合走原下载；预览页保存原名；拒绝授权。

## 8. 不做（YAGNI）

- 不进传输列表 / 不改 `RequestDownload` / 不改下载状态机。
- 视频/其他类型进相册。
- 多选混合分流（图片单独抽出存相册）。
- 用 SaveButton 改造菜单/多选按钮。
- 预览页改用短时授权 / `showAssetsCreationDialog`。
