# 文件上传功能完善设计文档

**日期**：2026-05-26  
**状态**：已批准，待实现

---

## 背景

Cloudrs 的文件上传功能尚未完整接通：`SelectFileSheet`（文件选择器）和 `CloudApi.uploadLocalFile`（Rust native 上传）均已实现，但两者之间缺乏连接。`TabFiles.onMoreClick` 的 `UPLOAD_FILE` 分支为空，没有上传入口能真正触发上传流程。

---

## 目标

1. 提供两个上传入口：更多菜单（已有但为空）+ FAB 浮动按钮（新增）
2. 并行上传，最大并发数可在设置中配置（默认 3）
3. 同名文件冲突时弹框询问覆盖或跳过
4. 每个文件上传完成后自动刷新当前目录

---

## 架构

```
用户点击 (更多菜单 UPLOAD_FILE / FAB)
      ↓
SelectFileSheet → onSelectFinished(uris[])
      ↓
TabFiles.startUpload(uris, currentPath)
  ├─ 检查同名冲突 → DialogHelper.showAlertDialog → 确定 overwrite 策略
  └─ uploadManager.enqueue(tasks[], remoteDirPath, overwrite, onDirChanged)
            ↓
      UploadManager (utils/UploadManager.ets)
      ├─ URI → cache 路径复制（FileUtil.open + copyFile）
      ├─ 并发控制（maxConcurrent 读自 UserPreferences，动态生效）
      └─ CloudApi.uploadLocalFile(cachePath, remotePath, overwrite, callback)
            ├─ onStart  → TransportObject.state = RUNNING
            ├─ onSuccess → state = COMPLETED → 删 cache → onDirChanged()
            └─ onFailure → state = FAILED → 删 cache
```

---

## 涉及文件

| 文件 | 变更 |
|---|---|
| `utils/UploadManager.ets` | **新建** — 上传队列与并发控制 |
| `pages/tabs/TabFiles.ets` | 修改 — FAB、MoreMenu、SelectFileSheet 绑定、冲突对话框 |
| `model/UserPreferences.ets` | 修改 — 新增 `UPLOAD_MAX_CONCURRENT` 键（默认 3） |
| `pages/tabs/TabMine.ets` | 修改 — 新增最大上传并发数设置项 |

`RequestUpload.ets` 保持不变。

---

## UploadManager 详细设计

### 数据结构

```typescript
interface UploadTask {
  uri: string            // 原始 URI（datashare:// 或 file://）
  remotePath: string     // 服务端完整路径，如 /foo/bar/photo.jpg
  overwrite: boolean
  transportObject: TransportObject
  onDirChanged: () => void
}

class UploadManager {
  readonly tasks: LazyDataSource<TransportObject>  // 供 UI 绑定
  readonly runningCount: number                    // 供 badge 计数

  enqueue(uris: string[], remoteDirPath: string,
          overwrite: boolean, onDirChanged: () => void): void

  private pendingQueue: UploadTask[]
  private _activeCount: number
  private _tryFlush(): void
  private _runTask(task: UploadTask): void
}

export const uploadManager = new UploadManager()
```

### 并发控制

- `maxConcurrent`：每次 `_tryFlush()` 调用时从 `UserPreferences` 动态读取，无需重启生效。
- `_tryFlush()`：当 `_activeCount < maxConcurrent && pendingQueue.length > 0` 时，循环取出任务并调用 `_runTask()`。
- `_runTask()` 完成（无论成功失败）时 `_activeCount--`，再次调用 `_tryFlush()`。

### 单任务流程

1. 将 `TransportObject.state` 设为 `WAITING`，调用 `tasks.pushData(transportObject)`。
2. 进入 `_runTask` 后：
   - `FileUtil.open(uri, READ_ONLY)` + `FileUtil.copyFile(fd, cachePath)` 复制到 `cacheDir/upload_<timestamp>_<name>`。
   - `TransportObject.state = RUNNING`，`_activeCount++`。
   - 调用 `CloudApi.uploadLocalFile(cachePath, remotePath, overwrite, callback)`。
3. `onSuccess`：`state = COMPLETED` → `fs.unlink(cachePath)` → `onDirChanged()` → `_activeCount--` → `_tryFlush()`。
4. `onFailure`：`state = FAILED` → `fs.unlink(cachePath)` → `_activeCount--` → `_tryFlush()`。

### TransportObject 构造

上传场景无服务端 id，构造临时 `ObjectInfo`：

```typescript
const fakeItem: ObjectInfo = {
  id: '',
  name: fileName,
  size: fileSize,  // 通过 fs.stat(cachePath) 获取，或 0（不影响功能）
  type: 'file',
  // 其余字段用默认值
}
const to = new TransportObject(fakeItem, cachePath, remotePath)
```

---

## TabFiles UI 变更

### FAB 按钮

将现有 `objectGrid()` 返回的 `Grid` 包裹在 `Stack` 中，叠加上传按钮：

```typescript
Stack(alignContent: Alignment.BottomEnd) {
  Grid(...) { ... }
  Button() {
    Image($r('app.media.ic_upload'))
      .width(24).height(24).fillColor(Color.White)
  }
  .width(52).height(52).borderRadius(26)
  .backgroundColor($r('app.color.primary'))
  .margin({ right: 16, bottom: this.tabBarHeight + 16 })
  .onClick(() => { this.showSelectFile = true })
}
```

### 更多菜单

`MoreMenuType.UPLOAD_FILE` 分支：

```typescript
case MoreMenuType.UPLOAD_FILE:
  this.showSelectFile = true
  break
```

### SelectFileSheet 绑定

在 `objectGrid()` 的外层容器加 `.bindSheet($$this.showSelectFile, this.selectFileSheetBuilder(), { detents: [SheetSize.FIT_CONTENT] })`。

`onSelectFinished` 回调中调用 `this.startUpload(uris)`。

### 冲突检测

`startUpload(uris)` 中：

1. 从 URI 列表提取文件名列表。
2. 与 `this.objectsInfo.fileObjects` 中的现有文件名比对（本地已加载数据，无需额外请求）。
3. 若有重名文件 → 弹一次确认框（列出所有冲突文件名），用户选择「全部覆盖」或「跳过已有」。
4. 根据选择设置 `overwrite` 标志后调用 `uploadManager.enqueue(...)`。

---

## 设置项

### UserPreferences

```typescript
static readonly UPLOAD_MAX_CONCURRENT = 'upload_max_concurrent'
// get/set 方法，默认返回 3，有效范围 1–10
```

### TabMine 设置行

在设置列表适当位置新增：

- 标题：「最大上传并发数」
- 控件：`Select` 或数字步进，选项 1–10
- 变更时写入 `UserPreferences.setUploadMaxConcurrent(n)`

---

## 边界情况

| 场景 | 处理方式 |
|---|---|
| URI 复制到 cache 失败 | `TransportObject.state = FAILED`，不进入上传队列 |
| 上传过程中切换目录 | 上传继续，`onDirChanged` 只刷新当时的目录路径（闭包捕获） |
| 选择 0 个文件 | `onSelectFinished` 不触发，无操作 |
| cache 文件删除失败 | 仅 log，不影响主流程 |
| 同名冲突且用户选「跳过」 | 只移除冲突文件，其余文件正常上传 |
