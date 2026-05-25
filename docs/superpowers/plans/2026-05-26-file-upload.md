# 文件上传功能完善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完整实现文件上传功能：两个入口（更多菜单 + FAB）、并发队列控制、同名冲突弹框、上传后自动刷新目录。

**Architecture:** 新建 `UploadManager` 单例管理上传队列和并发，TabFiles 负责 UI 触发与文件选择，TabMine 提供最大并发数设置项。上传通过 `CloudApi.uploadLocalFile`（Rust native）执行，`TransportObject` 的 `@Trace` 字段驱动传输列表 UI 更新。

**Tech Stack:** ArkTS, `@pura/harmony-utils` (FileUtil), `@ohos.file.fs` (fs), `@kit.CoreFileKit` (fileUri), `@pura/harmony-dialog` (DialogHelper)

**Design Spec:** `docs/superpowers/specs/2026-05-26-file-upload-design.md`

---

## 文件清单

| 操作 | 路径 |
|---|---|
| **新建** | `entry/src/main/ets/utils/UploadManager.ets` |
| **修改** | `entry/src/main/ets/model/Constant.ets` |
| **修改** | `entry/src/main/resources/base/element/string.json` |
| **修改** | `entry/src/main/resources/zh_CN/element/string.json` |
| **修改** | `entry/src/main/resources/en_US/element/string.json` |
| **修改** | `entry/src/main/ets/pages/tabs/TabFiles.ets` |
| **修改** | `entry/src/main/ets/pages/tabs/TabMine.ets` |

---

### Task 1: 新增字符串资源和常量

**Files:**
- Modify: `entry/src/main/ets/model/Constant.ets`
- Modify: `entry/src/main/resources/base/element/string.json`
- Modify: `entry/src/main/resources/zh_CN/element/string.json`
- Modify: `entry/src/main/resources/en_US/element/string.json`

- [ ] **Step 1: 在 Constant.ets 末尾、closing `}` 之前新增常量**

  在 `TASK_NET_RESUME_MSG: number = -4;` 之后、`}` 之前添加：

  ```typescript
    UPLOAD_MAX_CONCURRENT: string = 'upload_max_concurrent';
  ```

  完整修改后最后几行：
  ```typescript
    TASK_PAUSE_MSG: number = -1;
    TASK_RESUME_MSG: number = -2;
    TASK_NET_PAUSE_MSG: number = -3;
    TASK_NET_RESUME_MSG: number = -4;
    UPLOAD_MAX_CONCURRENT: string = 'upload_max_concurrent';
  }
  ```

- [ ] **Step 2: 在 base/element/string.json 末尾追加四条字符串**

  在最后一个 `}` 前（`"name": "select_file_title"` 条目之后）追加：

  ```json
    ,
    {
      "name": "upload_conflict_title",
      "value": "文件已存在"
    },
    {
      "name": "upload_skip_existing",
      "value": "跳过已有"
    },
    {
      "name": "upload_overwrite_all",
      "value": "全部覆盖"
    },
    {
      "name": "upload_max_concurrent",
      "value": "最大上传并发数"
    }
  ```

  最终文件末尾应为：
  ```json
      {
        "name": "select_file_title",
        "value": "添加到文件"
      },
      {
        "name": "upload_conflict_title",
        "value": "文件已存在"
      },
      {
        "name": "upload_skip_existing",
        "value": "跳过已有"
      },
      {
        "name": "upload_overwrite_all",
        "value": "全部覆盖"
      },
      {
        "name": "upload_max_concurrent",
        "value": "最大上传并发数"
      }
    ]
  }
  ```

- [ ] **Step 3: 在 zh_CN/element/string.json 末尾同样追加（内容相同）**

  在 `"name": "select_file_title"` 条目之后追加（同 Step 2 内容）。

- [ ] **Step 4: 在 en_US/element/string.json 末尾追加英文版本**

  在最后一个条目之后追加：

  ```json
    ,
    {
      "name": "upload_conflict_title",
      "value": "File Already Exists"
    },
    {
      "name": "upload_skip_existing",
      "value": "Skip Existing"
    },
    {
      "name": "upload_overwrite_all",
      "value": "Overwrite All"
    },
    {
      "name": "upload_max_concurrent",
      "value": "Max Upload Concurrency"
    }
  ```

- [ ] **Step 5: 提交**

  ```bash
  git add entry/src/main/ets/model/Constant.ets \
          entry/src/main/resources/base/element/string.json \
          entry/src/main/resources/zh_CN/element/string.json \
          entry/src/main/resources/en_US/element/string.json
  git commit -m "feat(upload): add upload constants and string resources"
  ```

---

### Task 2: 新建 UploadManager.ets

**Files:**
- Create: `entry/src/main/ets/utils/UploadManager.ets`

- [ ] **Step 1: 创建文件，写入完整实现**

  ```typescript
  import fs from '@ohos.file.fs';
  import { fileUri } from '@kit.CoreFileKit';
  import { common } from '@kit.AbilityKit';
  import { FileUtil } from '@pura/harmony-utils';
  import { CloudApi } from '../model/net/CloudApi';
  import { FileModelState } from '../model/FileModel';
  import { ObjectInfo } from '../model/net/ApiTypes';
  import { TransportObject } from '../model/TransportObject';
  import LazyDataSource from './LazyDataSource';
  import UserPreferences from '../model/UserPreferences';
  import Constant from '../model/Constant';

  const TAG = 'UploadManager';

  interface UploadTask {
    uri: string
    remotePath: string
    overwrite: boolean
    context: common.UIAbilityContext
    transportObject: TransportObject
    onDirChanged: () => void
    onTaskEnd?: () => void
  }

  class UploadManager {
    private pendingQueue: UploadTask[] = [];
    private _activeCount: number = 0;

    extractFileName(uri: string): string {
      try {
        return new fileUri.FileUri(uri).name;
      } catch {
        return `upload_${new Date().getTime()}`;
      }
    }

    enqueue(
      uris: string[],
      remoteDirPath: string,
      overwrite: boolean,
      context: common.UIAbilityContext,
      uploadObjects: LazyDataSource<TransportObject>,
      onDirChanged: () => void,
      onTaskEnd?: () => void
    ): void {
      uris.forEach(uri => {
        const fileName = this.extractFileName(uri);
        const sep = remoteDirPath.endsWith('/') ? '' : '/';
        const remotePath = `${remoteDirPath}${sep}${fileName}`;
        const fakeItem: ObjectInfo = {
          id: '', name: fileName, path: remoteDirPath,
          thumb: false, size: 0, type: 'file',
          date: '', create_date: '', source_enabled: false
        };
        const to = new TransportObject(fakeItem, uri, remotePath);
        to.state = FileModelState.WAITING;
        uploadObjects.pushData(to);
        this.pendingQueue.push({
          uri, remotePath, overwrite, context,
          transportObject: to, onDirChanged, onTaskEnd
        });
      });
      this._tryFlush();
    }

    private _tryFlush(): void {
      const raw = UserPreferences.getSync(
        Constant.USER_PREFERENCES,
        Constant.UPLOAD_MAX_CONCURRENT,
        3
      );
      const maxConcurrent = (typeof (raw as number) === 'number' ? (raw as number) : 3) || 3;
      while (this._activeCount < maxConcurrent && this.pendingQueue.length > 0) {
        const task = this.pendingQueue.shift()!;
        this._runTask(task);
      }
    }

    private async _runTask(task: UploadTask): Promise<void> {
      this._activeCount++;
      const { uri, remotePath, overwrite, context, transportObject, onDirChanged, onTaskEnd } = task;
      const fileName = this.extractFileName(uri);
      const cachePath = `${context.cacheDir}/upload_${new Date().getTime()}_${fileName}`;

      try {
        const source = await FileUtil.open(uri, fs.OpenMode.READ_ONLY);
        try {
          await FileUtil.copyFile(source.fd, cachePath);
        } finally {
          await FileUtil.close(source.fd);
        }
      } catch (err) {
        console.error(TAG, `copy to cache failed: ${(err as Error)?.message ?? err}`);
        transportObject.state = FileModelState.FAILED;
        this._finish(onTaskEnd);
        return;
      }

      transportObject.state = FileModelState.RUNNING;

      CloudApi.uploadLocalFile(cachePath, remotePath, overwrite, {
        onSuccess: () => {
          transportObject.state = FileModelState.COMPLETED;
          transportObject.progress = 100;
          fs.unlink(cachePath).catch(() => {});
          onDirChanged();
          this._finish(onTaskEnd);
        },
        onFailure: (msg: string) => {
          console.error(TAG, `upload failed: ${msg}`);
          transportObject.state = FileModelState.FAILED;
          fs.unlink(cachePath).catch(() => {});
          this._finish(onTaskEnd);
        }
      });
    }

    private _finish(onTaskEnd?: () => void): void {
      this._activeCount--;
      if (onTaskEnd) {
        onTaskEnd();
      }
      this._tryFlush();
    }
  }

  export const uploadManager = new UploadManager();
  ```

- [ ] **Step 2: 确认编译通过**

  在 DevEco Studio 中执行 Build → Clean Project，再 Build → Build Hap(s)/APP(s)，确认无编译错误。

- [ ] **Step 3: 提交**

  ```bash
  git add entry/src/main/ets/utils/UploadManager.ets
  git commit -m "feat(upload): add UploadManager with concurrent queue"
  ```

---

### Task 3: TabFiles — 上传入口、SelectFileSheet 绑定与 startUpload

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabFiles.ets`

- [ ] **Step 1: 在 import 区域末尾补充两行缺失的导入**

  在现有 import 块末尾（`import { FileModel, FileModelState } from '...'` 之后）添加：

  ```typescript
  import { fileUri } from '@kit.CoreFileKit';
  import { SelectFileSheet } from '../../components/SelectFileSheet';
  import { uploadManager } from '../../utils/UploadManager';
  ```

- [ ] **Step 2: 在 TabFiles 组件的 @State 区域新增 showSelectFile 状态**

  在 `@State uploadObjects` 声明之后添加：

  ```typescript
  @State showSelectFile: boolean = false
  ```

- [ ] **Step 3: 实现 startUpload 方法**

  在 `itemDownload` 方法之后、`build()` 方法之前插入：

  ```typescript
  startUpload(uris: string[]): void {
    if (uris.length === 0) return;

    const context = getContext(this) as common.UIAbilityContext;
    const onDirChanged = () => { this.getFileList(true, this.currentPath); };
    const onTaskEnd = () => { this.uploadingCount--; };

    const existingNames = new Set<string>(this.objectsInfo.fileObjects.map(f => f.name));
    const conflictNames = uris
      .map(uri => { try { return uploadManager.extractFileName(uri); } catch { return ''; } })
      .filter(name => name.length > 0 && existingNames.has(name));

    if (conflictNames.length === 0) {
      this.uploadingCount += uris.length;
      uploadManager.enqueue(uris, this.currentPath, false, context, this.uploadObjects, onDirChanged, onTaskEnd);
      return;
    }

    DialogHelper.showAlertDialog({
      primaryTitle: $r('app.string.upload_conflict_title'),
      content: conflictNames.join('\n'),
      primaryButton: { value: $r('app.string.upload_skip_existing') },
      secondaryButton: { value: $r('app.string.upload_overwrite_all') },
      onAction: (action: number, _dialogId: string) => {
        if (action == DialogAction.TWO) {
          this.uploadingCount += uris.length;
          uploadManager.enqueue(uris, this.currentPath, true, context, this.uploadObjects, onDirChanged, onTaskEnd);
        } else {
          const conflictSet = new Set<string>(conflictNames);
          const filteredUris = uris.filter(uri => {
            try { return !conflictSet.has(uploadManager.extractFileName(uri)); } catch { return true; }
          });
          if (filteredUris.length > 0) {
            this.uploadingCount += filteredUris.length;
            uploadManager.enqueue(filteredUris, this.currentPath, false, context, this.uploadObjects, onDirChanged, onTaskEnd);
          }
        }
      }
    });
  }
  ```

- [ ] **Step 4: 在 onMoreClick 的 UPLOAD_FILE 分支填入逻辑**

  找到：
  ```typescript
        case MoreMenuType.UPLOAD_FILE:
          break
  ```
  替换为：
  ```typescript
        case MoreMenuType.UPLOAD_FILE:
          this.showSelectFile = true
          break
  ```

- [ ] **Step 5: 新增 selectFileSheetBuilder**

  在 `@Builder detailSheet()` 之后添加：

  ```typescript
  @Builder selectFileSheetBuilder() {
    SelectFileSheet({
      onSelectFinished: (uris: string[]) => {
        this.showSelectFile = false;
        this.startUpload(uris);
      }
    })
  }
  ```

- [ ] **Step 6: 在 build() 的外层 Column 上追加 showSelectFile 的 bindSheet**

  找到：
  ```typescript
      .bindSheet($$this.showObjectDetail, this.detailSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        backgroundColor: Color.White,
        title: {title: $r('app.string.detail_title')},
      })
  ```
  在其后追加：
  ```typescript
      .bindSheet($$this.showSelectFile, this.selectFileSheetBuilder(), {
        detents: [SheetSize.FIT_CONTENT],
        showClose: true,
      })
  ```

- [ ] **Step 7: 确认编译通过，手动验证更多菜单上传入口**

  - Build → Build Hap，确认无错误
  - 在真机/模拟器上运行，进入文件页，点击右上角更多菜单 → "上传文件"
  - 验证：底部弹出文件选择 Sheet（含「本地文件」「本地图片」「本地视频」三项）
  - 选择一个文件，观察传输列表中出现上传任务，目录刷新后可见新文件

- [ ] **Step 8: 提交**

  ```bash
  git add entry/src/main/ets/pages/tabs/TabFiles.ets
  git commit -m "feat(upload): connect SelectFileSheet, startUpload, and conflict dialog in TabFiles"
  ```

---

### Task 4: TabFiles — FAB 浮动上传按钮

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabFiles.ets`

- [ ] **Step 1: 将 build() 中的 Refresh 替换为 Stack(Refresh + FAB)**

  找到 `build()` 方法中：
  ```typescript
        Refresh({refreshing: $$this.isRefreshing}) {
          this.objectGrid()
        }
        .margin({ top: 20 })
        .layoutWeight(1)
        .refreshOffset(77)
        .pullToRefresh(true)
        .onRefreshing(async () => {
          await this.getFileList(true, this.currentPath);
        })
  ```

  替换为：
  ```typescript
        Stack(alignContent: Alignment.BottomEnd) {
          Refresh({refreshing: $$this.isRefreshing}) {
            this.objectGrid()
          }
          .width('100%')
          .height('100%')
          .refreshOffset(77)
          .pullToRefresh(true)
          .onRefreshing(async () => {
            await this.getFileList(true, this.currentPath);
          })

          Button() {
            Image($r('app.media.ic_arrowshape_up'))
              .width(24)
              .height(24)
              .fillColor(Color.White)
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .backgroundColor('#007AFF')
          .margin({ right: 16, bottom: this.tabBarHeight + 16 })
          .onClick(() => { this.showSelectFile = true })
        }
        .margin({ top: 20 })
        .layoutWeight(1)
  ```

- [ ] **Step 2: 确认编译通过，手动验证 FAB**

  - Build → Build Hap，确认无错误
  - 运行 app，进入文件页，观察右下角出现蓝色圆形上传按钮
  - 点击 FAB，验证同样弹出文件选择 Sheet
  - 选择文件后，观察上传任务和目录刷新行为一致

- [ ] **Step 3: 提交**

  ```bash
  git add entry/src/main/ets/pages/tabs/TabFiles.ets
  git commit -m "feat(upload): add FAB upload button to file list"
  ```

---

### Task 5: TabMine — 最大上传并发数设置项

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabMine.ets`

- [ ] **Step 1: 在 TabMine 的 @State 区域新增状态变量**

  在 `@State versionInfo: string = ''` 之后添加：

  ```typescript
  @State uploadMaxConcurrent: number = 3
  ```

- [ ] **Step 2: 在 aboutToAppear() 末尾加载持久化值**

  在 `aboutToAppear()` 方法末尾、closing `}` 之前添加：

  ```typescript
    const raw = UserPreferences.getSync(
      Constant.USER_PREFERENCES,
      Constant.UPLOAD_MAX_CONCURRENT,
      3
    );
    this.uploadMaxConcurrent = (typeof (raw as number) === 'number' ? (raw as number) : 3) || 3;
  ```

- [ ] **Step 3: 新增 rowWithSelect @Builder 方法**

  在 `rowWithNext` 方法之后、`settingButton` 方法之前插入：

  ```typescript
  @Builder rowWithSelect(icon: ResourceStr, bgColor: ResourceStr,
    title: ResourceStr, currentValue: number,
    options: SelectOption[], onChange: (val: number) => void) {
    Row({ space: 10 }) {
      Image(icon)
        .width(28).height(28).borderRadius(14).padding(5)
        .fillColor(Color.White).backgroundColor(bgColor)
        .draggable(false)

      Text(title)
        .fontSize(16)
        .layoutWeight(1)

      Select(options)
        .value(currentValue.toString())
        .selected(currentValue - 1)
        .onSelect((index: number) => { onChange(index + 1); })
        .width(70)
    }
    .width('100%')
    .height(50)
    .padding({ left: 10, right: 10 })
    .borderRadius(10)
    .backgroundColor($r('app.color.setting_button_background'))
    .alignItems(VerticalAlign.Center)
  }
  ```

- [ ] **Step 4: 在 settingButton() 中添加并发数设置行**

  找到 `settingButton()` 方法中的 `Column({space: 10})` 内容，在最后一个 `this.rowWithNext(...)` 之后追加：

  ```typescript
      this.rowWithSelect(
        $r('app.media.ic_more_setting'),
        $r('app.color.setting_icon_more_background'),
        $r('app.string.upload_max_concurrent'),
        this.uploadMaxConcurrent,
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => ({ value: n.toString() } as SelectOption)),
        (val: number) => {
          this.uploadMaxConcurrent = val;
          UserPreferences.putSync(
            Constant.USER_PREFERENCES,
            Constant.UPLOAD_MAX_CONCURRENT,
            val
          );
        }
      )
  ```

- [ ] **Step 5: 确认编译通过，手动验证设置项**

  - Build → Build Hap，确认无错误
  - 运行 app，进入「我的」标签页，滚动找到「最大上传并发数」设置行
  - 验证：显示下拉 Select，当前值为 3
  - 更改为 1，重新上传多个文件，观察同一时间只有 1 个任务处于 RUNNING 状态
  - 更改为 5，重新上传多个文件，观察最多 5 个任务同时 RUNNING

- [ ] **Step 6: 提交**

  ```bash
  git add entry/src/main/ets/pages/tabs/TabMine.ets
  git commit -m "feat(upload): add max concurrent upload setting in TabMine"
  ```

---

## 完整功能验证清单

完成所有任务后执行端到端验证：

- [ ] 更多菜单 → 上传文件 → 选本地文件 → 上传成功 → 目录刷新
- [ ] 更多菜单 → 上传文件 → 选图片 → 上传成功 → 目录刷新
- [ ] FAB 按钮 → 选多个文件 → 并行上传 → 传输列表显示进度 → 全部完成
- [ ] 上传同名文件 → 弹出冲突对话框 → 选「跳过已有」→ 其余文件正常上传
- [ ] 上传同名文件 → 弹出冲突对话框 → 选「全部覆盖」→ 文件被覆盖
- [ ] 在「我的」中将并发数改为 1 → 多文件上传时顺序执行
- [ ] 传输列表（右上角传输图标）→ 切换到「上传」Tab → 可见上传任务列表
- [ ] 上传失败时（断网）→ 任务显示 FAILED 状态
