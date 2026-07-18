# 相册 Tab 重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「相册」tab 从备份管理面板重构成本地照片相册浏览器（等高瀑布流 + 同步状态角标 + 顶部进度抽屉 + 大图预览信息条），并把全部备份设置迁移到「我的」页。

**Architecture:** 备份引擎逻辑保留在 `TabPictures` 内，不整体搬迁。新增一个轻量共享设置 store（`PhotoBackupSettingsStore`，基于 `UserPreferences` 持久化 + `AppStorage` 镜像）让「我的」设置 sheet 与相册页共享同一份设置；备份运行态仍归相册页。UI 拆成若干聚焦组件：进度抽屉、瀑布流网格、时间/相册分段、本地大图预览。

**Tech Stack:** ArkTS / ArkUI（HarmonyOS Next, API 22）、`@kit.MediaLibraryKit`（photoAccessHelper）、`@kit.ImageKit`、`WaterFlow`、`@ohos/hypium`（ohosTest 单元测试）。

> **验证方式说明（重要）**：本项目无 JVM 级单测，ohosTest（hypium）跑在设备/模拟器上。计划对**纯逻辑**（设置 store、日期/相册分组、状态→角标映射、瀑布流行布局算法）写真实 hypium 单测；对**纯 UI** 任务用「ArkTS 编译通过 + 真机安装运行目测」作为验证门（符合本项目既有工作流：`./hvigorw assembleHap` 编译，连真机时安装启动）。每个任务最后均要求编译通过再提交。

---

## 文件结构

**新建：**
- `entry/src/main/ets/model/PhotoBackupSettingsStore.ets` — 共享备份设置（读写 UserPreferences + 镜像 AppStorage）
- `entry/src/main/ets/model/PhotoGalleryModel.ets` — 相册页用的纯数据/枚举：分段维度、分组、状态→角标映射、瀑布流行布局算法
- `entry/src/main/ets/components/PhotoBackupDrawer.ets` — 顶部进度抽屉组件
- `entry/src/main/ets/components/PhotoGalleryGrid.ets` — 等高瀑布流网格（分组标题 + 状态角标）
- `entry/src/main/ets/components/PhotoGallerySegment.ets` — 时间/相册分段控件
- `entry/src/main/ets/components/PhotoBackupSettingsSheet.ets` — 「我的」页的备份设置 sheet 内容
- `entry/src/main/ets/pages/PhotoLocalPreview.ets` — 本地图大图预览页（信息条）
- `entry/src/ohosTest/ets/test/PhotoBackupSettingsStore.test.ets`
- `entry/src/ohosTest/ets/test/PhotoGalleryModel.test.ets`

**修改：**
- `entry/src/main/ets/pages/tabs/TabPictures.ets` — 重构 build()/Builder 层为新 UI，接入共享设置 store 与新组件；删除旧的 summaryCard/sections/settingsPanel UI
- `entry/src/main/ets/pages/tabs/TabMine.ets` — 新增「相册备份」设置行与 sheet 接入
- `entry/src/main/ets/model/Constant.ets` — 新增页面路由常量与（如需）AppStorage key 常量
- `entry/src/ohosTest/ets/test/List.test.ets` — 注册新测试套件

---

## Phase 0：共享设置 store（纯逻辑 + 单测）

### Task 1：PhotoBackupSettingsStore 读写与归一化

**Files:**
- Create: `entry/src/main/ets/model/PhotoBackupSettingsStore.ets`
- Test: `entry/src/ohosTest/ets/test/PhotoBackupSettingsStore.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**背景：** 现有 `PhotoBackupSettings`（`model/PhotoBackupModel.ets`）已有 `fromJson/toJson` 与字段（enabled/remotePath/wifiOnly/autoBackup/uploadConcurrent/lastScanAt）。本 store 负责：从 `UserPreferences`（key `Constant.PHOTO_BACKUP_SETTINGS`）读出、归一化并发数、写回，并把"是否开启 + 路径"镜像到 `AppStorage`，供两个页面观察。

- [ ] **Step 1: 写失败测试**

`entry/src/ohosTest/ets/test/PhotoBackupSettingsStore.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import { PhotoBackupSettingsStore } from '../../../../main/ets/model/PhotoBackupSettingsStore';

export default function photoBackupSettingsStoreTest() {
  describe('PhotoBackupSettingsStore', () => {
    it('normalizeConcurrent_clampsRange', 0, () => {
      expect(PhotoBackupSettingsStore.normalizeConcurrent(0)).assertEqual(1);
      expect(PhotoBackupSettingsStore.normalizeConcurrent(99)).assertEqual(10);
      expect(PhotoBackupSettingsStore.normalizeConcurrent(3)).assertEqual(3);
    });
    it('normalizeRemotePath_addsLeadingSlashAndTrimsTrailing', 0, () => {
      expect(PhotoBackupSettingsStore.normalizeRemotePath('Photos/Camera/')).assertEqual('/Photos/Camera');
      expect(PhotoBackupSettingsStore.normalizeRemotePath('')).assertEqual('/Photos/Camera');
    });
  });
}
```

- [ ] **Step 2: 注册测试套件**

修改 `entry/src/ohosTest/ets/test/List.test.ets`：

```ts
import abilityTest from './Ability.test';
import photoBackupSettingsStoreTest from './PhotoBackupSettingsStore.test';

export default function testsuite() {
  abilityTest();
  photoBackupSettingsStoreTest();
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `./hvigorw test -p module=entry@ohosTest`
Expected: FAIL（`PhotoBackupSettingsStore` 模块不存在 / 编译错误）

- [ ] **Step 4: 实现 store**

`entry/src/main/ets/model/PhotoBackupSettingsStore.ets`:

```ts
import UserPreferences from './UserPreferences';
import Constant from './Constant';
import { PhotoBackupSettings } from './PhotoBackupModel';

const CONCURRENT_MIN: number = 1;
const CONCURRENT_MAX: number = 10;
const DEFAULT_PATH: string = '/Photos/Camera';

/** AppStorage 镜像 key，供相册页/我的页通过 @StorageProp/@StorageLink 观察 */
export const PHOTO_BACKUP_ENABLED_KEY: string = 'photoBackupEnabledMirror';
export const PHOTO_BACKUP_PATH_KEY: string = 'photoBackupPathMirror';
export const PHOTO_BACKUP_REVISION_KEY: string = 'photoBackupSettingsRevision';

export class PhotoBackupSettingsStore {
  static normalizeConcurrent(value: number): number {
    if (typeof value !== 'number' || Number.isNaN(value)) {
      return 3;
    }
    return Math.min(Math.max(Math.floor(value), CONCURRENT_MIN), CONCURRENT_MAX);
  }

  static normalizeRemotePath(path: string): string {
    let value = (path ?? '').trim();
    if (value.length === 0) {
      return DEFAULT_PATH;
    }
    if (!value.startsWith('/')) {
      value = `/${value}`;
    }
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static load(): PhotoBackupSettings {
    const json = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS, '') as string;
    const settings = PhotoBackupSettings.fromJson(json ?? '');
    settings.uploadConcurrent = PhotoBackupSettingsStore.normalizeConcurrent(settings.uploadConcurrent);
    settings.remotePath = PhotoBackupSettingsStore.normalizeRemotePath(settings.remotePath);
    return settings;
  }

  static save(settings: PhotoBackupSettings): void {
    settings.uploadConcurrent = PhotoBackupSettingsStore.normalizeConcurrent(settings.uploadConcurrent);
    settings.remotePath = PhotoBackupSettingsStore.normalizeRemotePath(settings.remotePath);
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.PHOTO_BACKUP_SETTINGS, settings.toJson());
    PhotoBackupSettingsStore.mirror(settings);
  }

  /** 写入 AppStorage 镜像并自增 revision，触发两个页面刷新 */
  static mirror(settings: PhotoBackupSettings): void {
    AppStorage.setOrCreate(PHOTO_BACKUP_ENABLED_KEY, settings.enabled);
    AppStorage.setOrCreate(PHOTO_BACKUP_PATH_KEY, settings.remotePath);
    const rev = (AppStorage.get<number>(PHOTO_BACKUP_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(PHOTO_BACKUP_REVISION_KEY, rev);
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `./hvigorw test -p module=entry@ohosTest`
Expected: PASS（两条断言通过）

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/model/PhotoBackupSettingsStore.ets entry/src/ohosTest/ets/test/PhotoBackupSettingsStore.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(album): add shared photo backup settings store"
```

---

## Phase 1：相册页纯逻辑（分段/分组/角标/瀑布流算法）

### Task 2：状态→角标映射 + 分段枚举

**Files:**
- Create: `entry/src/main/ets/model/PhotoGalleryModel.ets`
- Test: `entry/src/ohosTest/ets/test/PhotoGalleryModel.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**背景：** 角标规则（设计稿 §3.4）：已备份→cloud；上传中→uploading；失败→failed；未备份→none。关闭备份时已备份仍显示 cloud，但不显示 uploading/waiting。映射输入为 `PhotoBackupStatus`（`model/PhotoBackupModel.ets` 现有枚举：WAITING/UPLOADING/COMPLETED/FAILED）+ 是否开启备份。

- [ ] **Step 1: 写失败测试**

`entry/src/ohosTest/ets/test/PhotoGalleryModel.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import { PhotoBadge, badgeForStatus, GallerySegment } from '../../../../main/ets/model/PhotoGalleryModel';
import { PhotoBackupStatus } from '../../../../main/ets/model/PhotoBackupModel';

export default function photoGalleryModelTest() {
  describe('PhotoGalleryModel', () => {
    it('completed_alwaysCloud_evenWhenDisabled', 0, () => {
      expect(badgeForStatus(PhotoBackupStatus.COMPLETED, true)).assertEqual(PhotoBadge.CLOUD);
      expect(badgeForStatus(PhotoBackupStatus.COMPLETED, false)).assertEqual(PhotoBadge.CLOUD);
    });
    it('uploading_failed_onlyWhenEnabled', 0, () => {
      expect(badgeForStatus(PhotoBackupStatus.UPLOADING, true)).assertEqual(PhotoBadge.UPLOADING);
      expect(badgeForStatus(PhotoBackupStatus.FAILED, true)).assertEqual(PhotoBadge.FAILED);
      expect(badgeForStatus(PhotoBackupStatus.UPLOADING, false)).assertEqual(PhotoBadge.NONE);
      expect(badgeForStatus(PhotoBackupStatus.FAILED, false)).assertEqual(PhotoBadge.NONE);
    });
    it('waiting_neverShowsBadge', 0, () => {
      expect(badgeForStatus(PhotoBackupStatus.WAITING, true)).assertEqual(PhotoBadge.NONE);
    });
    it('segmentEnum_hasTwoDimensions', 0, () => {
      expect(GallerySegment.TIME).assertEqual(0);
      expect(GallerySegment.ALBUM).assertEqual(1);
    });
  });
}
```

- [ ] **Step 2: 注册测试套件**

修改 `List.test.ets`，增加 import 与调用 `photoGalleryModelTest();`（保留 Task 1 的注册）。

- [ ] **Step 3: 运行确认失败**

Run: `./hvigorw test -p module=entry@ohosTest`
Expected: FAIL（模块不存在）

- [ ] **Step 4: 实现枚举与映射**

`entry/src/main/ets/model/PhotoGalleryModel.ets`:

```ts
import { PhotoBackupStatus } from './PhotoBackupModel';

export enum GallerySegment { TIME = 0, ALBUM = 1 }

export enum PhotoBadge { NONE = 'none', CLOUD = 'cloud', UPLOADING = 'uploading', FAILED = 'failed' }

/** 角标规则：已备份恒显示云；上传中/失败仅在备份开启时显示；待备份/其他不显示 */
export function badgeForStatus(status: PhotoBackupStatus, backupEnabled: boolean): PhotoBadge {
  if (status === PhotoBackupStatus.COMPLETED) {
    return PhotoBadge.CLOUD;
  }
  if (!backupEnabled) {
    return PhotoBadge.NONE;
  }
  if (status === PhotoBackupStatus.UPLOADING) {
    return PhotoBadge.UPLOADING;
  }
  if (status === PhotoBackupStatus.FAILED) {
    return PhotoBadge.FAILED;
  }
  return PhotoBadge.NONE;
}
```

- [ ] **Step 5: 运行确认通过**

Run: `./hvigorw test -p module=entry@ohosTest`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/model/PhotoGalleryModel.ets entry/src/ohosTest/ets/test/PhotoGalleryModel.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(album): add gallery segment enum and status-to-badge mapping"
```

### Task 3：按时间/相册分组

**Files:**
- Modify: `entry/src/main/ets/model/PhotoGalleryModel.ets`
- Modify: `entry/src/ohosTest/ets/test/PhotoGalleryModel.test.ets`

**背景：** 网格按当前分段维度分组。`PhotoBackupItem`（现有）含 `modifiedAt`(ms)、`name`。时间分组用本地日期字符串作 key（今天/昨天/YYYY-MM-DD）；相册分组用相册名（由调用方填入 item，本任务只按给定 `albumName` 字段分组）。为支持相册分组，给 `PhotoBackupItem` 增加可选 `albumName`。

- [ ] **Step 1: 给 PhotoBackupItem 增加 albumName 字段**

在 `entry/src/main/ets/model/PhotoBackupModel.ets` 的 `PhotoBackupItem` 类中新增字段（默认空串），并在 `toData/fromData` 中带上（与现有同样模式）。展示用，不参与去重逻辑。

```ts
// PhotoBackupItem 类内新增：
albumName: string = '';
```
（`toData()` 增加 `albumName: this.albumName`；`fromData()` 增加 `item.albumName = data.albumName ?? ''`；对应 `PhotoBackupItemData` 接口加 `albumName?: string`。）

- [ ] **Step 2: 写失败测试**

在 `PhotoGalleryModel.test.ets` 增加：

```ts
import { groupByDate, groupByAlbum, PhotoGroup } from '../../../../main/ets/model/PhotoGalleryModel';
import { PhotoBackupItem } from '../../../../main/ets/model/PhotoBackupModel';

// describe 内新增：
it('groupByAlbum_groupsAndPreservesOrder', 0, () => {
  const a = new PhotoBackupItem('u1', 'a.jpg', 1, 100); a.albumName = '相机';
  const b = new PhotoBackupItem('u2', 'b.jpg', 1, 200); b.albumName = '截图';
  const c = new PhotoBackupItem('u3', 'c.jpg', 1, 300); c.albumName = '相机';
  const groups: PhotoGroup[] = groupByAlbum([a, b, c]);
  expect(groups.length).assertEqual(2);
  expect(groups[0].title).assertEqual('相机');
  expect(groups[0].items.length).assertEqual(2);
});

it('groupByDate_sameDaySameGroup', 0, () => {
  const day = new Date(2024, 4, 24, 9, 0, 0).getTime();
  const day2 = new Date(2024, 4, 24, 20, 0, 0).getTime();
  const x = new PhotoBackupItem('u1', 'a.jpg', 1, day);
  const y = new PhotoBackupItem('u2', 'b.jpg', 1, day2);
  const groups: PhotoGroup[] = groupByDate([x, y], new Date(2024, 4, 25));
  expect(groups.length).assertEqual(1);
  expect(groups[0].items.length).assertEqual(2);
});
```

- [ ] **Step 3: 运行确认失败**

Run: `./hvigorw test -p module=entry@ohosTest`
Expected: FAIL

- [ ] **Step 4: 实现分组**

在 `PhotoGalleryModel.ets` 追加：

```ts
import { PhotoBackupItem } from './PhotoBackupModel';

export class PhotoGroup {
  title: string;
  items: PhotoBackupItem[];
  constructor(title: string, items: PhotoBackupItem[]) {
    this.title = title;
    this.items = items;
  }
}

function dateKey(ms: number): string {
  const d = new Date(ms);
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

function dateTitle(ms: number, today: Date): string {
  const d = new Date(ms);
  const isSameDay = d.getFullYear() === today.getFullYear() &&
    d.getMonth() === today.getMonth() && d.getDate() === today.getDate();
  if (isSameDay) {
    return '今天';
  }
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

/** 按日期分组，保持传入顺序（调用方已按 modifiedAt 降序） */
export function groupByDate(items: PhotoBackupItem[], today: Date): PhotoGroup[] {
  const order: string[] = [];
  const map: Map<string, PhotoBackupItem[]> = new Map();
  items.forEach((it: PhotoBackupItem) => {
    const key = dateKey(it.modifiedAt);
    if (!map.has(key)) {
      map.set(key, []);
      order.push(key);
    }
    map.get(key)!.push(it);
  });
  return order.map((key: string) => {
    const list = map.get(key)!;
    return new PhotoGroup(dateTitle(list[0].modifiedAt, today), list);
  });
}

/** 按相册名分组，保持首次出现顺序 */
export function groupByAlbum(items: PhotoBackupItem[]): PhotoGroup[] {
  const order: string[] = [];
  const map: Map<string, PhotoBackupItem[]> = new Map();
  items.forEach((it: PhotoBackupItem) => {
    const key = it.albumName && it.albumName.length > 0 ? it.albumName : '其他';
    if (!map.has(key)) {
      map.set(key, []);
      order.push(key);
    }
    map.get(key)!.push(it);
  });
  return order.map((key: string) => new PhotoGroup(key, map.get(key)!));
}
```

- [ ] **Step 5: 运行确认通过**

Run: `./hvigorw test -p module=entry@ohosTest`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/model/PhotoGalleryModel.ets entry/src/main/ets/model/PhotoBackupModel.ets entry/src/ohosTest/ets/test/PhotoGalleryModel.test.ets
git commit -m "feat(album): group photos by date and album"
```

### Task 4：等高瀑布流行布局算法

**Files:**
- Modify: `entry/src/main/ets/model/PhotoGalleryModel.ets`
- Modify: `entry/src/ohosTest/ets/test/PhotoGalleryModel.test.ets`

**背景：** 等高瀑布流（justified rows）：给定每张图宽高比、容器宽度、目标行高、间距，把一组图切成若干行，每行缩放到铺满容器宽度，得到统一行高与各图宽度。这是纯函数，便于单测；UI 任务直接用它算尺寸。

- [ ] **Step 1: 写失败测试**

在 `PhotoGalleryModel.test.ets` 增加：

```ts
import { justifyRows, JustifiedRow } from '../../../../main/ets/model/PhotoGalleryModel';

it('justifyRows_fillsContainerWidth', 0, () => {
  // 三张 1:1 图，容器 300，间距 0，目标行高 100 → 一行三张各 100 宽，行高 100
  const rows: JustifiedRow[] = justifyRows([1, 1, 1], 300, 100, 0);
  expect(rows.length).assertEqual(1);
  expect(Math.round(rows[0].height)).assertEqual(100);
  expect(Math.round(rows[0].widths[0])).assertEqual(100);
});

it('justifyRows_wrapsWhenExceedTarget', 0, () => {
  // 四张 1:1，容器 300，目标行高 100：每行约 3 张后换行
  const rows: JustifiedRow[] = justifyRows([1, 1, 1, 1], 300, 100, 0);
  expect(rows.length).assertEqual(2);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `./hvigorw test -p module=entry@ohosTest`
Expected: FAIL

- [ ] **Step 3: 实现行布局算法**

在 `PhotoGalleryModel.ets` 追加：

```ts
export class JustifiedRow {
  height: number;
  widths: number[];
  startIndex: number;
  constructor(height: number, widths: number[], startIndex: number) {
    this.height = height;
    this.widths = widths;
    this.startIndex = startIndex;
  }
}

/**
 * 把一组宽高比按等高瀑布流切行。
 * @param ratios 每张图 宽/高 比值（>0）
 * @param containerWidth 可用宽度
 * @param targetHeight 目标行高
 * @param gap 图间距
 */
export function justifyRows(ratios: number[], containerWidth: number, targetHeight: number, gap: number): JustifiedRow[] {
  const rows: JustifiedRow[] = [];
  let current: number[] = [];
  let start = 0;
  const flush = (isLast: boolean) => {
    if (current.length === 0) {
      return;
    }
    const sumRatio = current.reduce((s: number, r: number) => s + r, 0);
    const totalGap = gap * (current.length - 1);
    // 行内每张图宽 = ratio * rowHeight；令 sum(width) + gap = containerWidth
    let rowHeight = (containerWidth - totalGap) / sumRatio;
    if (isLast && rowHeight > targetHeight) {
      rowHeight = targetHeight; // 末行不放大
    }
    const widths = current.map((r: number) => r * rowHeight);
    rows.push(new JustifiedRow(rowHeight, widths, start));
    start += current.length;
    current = [];
  };
  ratios.forEach((ratio: number, i: number) => {
    current.push(ratio > 0 ? ratio : 1);
    const sumRatio = current.reduce((s: number, r: number) => s + r, 0);
    const totalGap = gap * (current.length - 1);
    const projectedHeight = (containerWidth - totalGap) / sumRatio;
    // 当投影行高 <= 目标行高，说明该行已够满，换行
    if (projectedHeight <= targetHeight) {
      flush(false);
    }
  });
  flush(true);
  return rows;
}
```

- [ ] **Step 4: 运行确认通过**

Run: `./hvigorw test -p module=entry@ohosTest`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/model/PhotoGalleryModel.ets entry/src/ohosTest/ets/test/PhotoGalleryModel.test.ets
git commit -m "feat(album): justified-rows layout algorithm for waterfall grid"
```

---

## Phase 2：设置迁移到「我的」页

### Task 5：备份设置 sheet 组件

**Files:**
- Create: `entry/src/main/ets/components/PhotoBackupSettingsSheet.ets`

**背景：** sheet 内容（设计稿 §4.2）：开启自动备份(开关)、备份路径(点开 `PathSelectSheet`)、仅 Wi-Fi(开关)、同时上传数量(步进器)。读写经 `PhotoBackupSettingsStore`。组件通过回调把"打开路径选择"交给宿主（`TabMine`）处理，避免 sheet 内嵌 sheet。

- [ ] **Step 1: 实现组件**

`entry/src/main/ets/components/PhotoBackupSettingsSheet.ets`:

```ts
import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupSettings } from '../model/PhotoBackupModel';
import { PhotoBackupSettingsStore } from '../model/PhotoBackupSettingsStore';
import Constant from '../model/Constant';

@Component
export struct PhotoBackupSettingsSheet {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State settings: PhotoBackupSettings = new PhotoBackupSettings();
  onClose: () => void = () => {};
  onPickPath: () => void = () => {};

  aboutToAppear(): void {
    this.settings = PhotoBackupSettingsStore.load();
  }

  private persist(): void {
    PhotoBackupSettingsStore.save(this.settings);
  }

  @Builder switchRow(title: string, desc: string, value: boolean, onToggle: (v: boolean) => void) {
    Row({ space: CloudThemeToken.spacingSection }) {
      Column({ space: CloudThemeToken.spacingXs }) {
        Text(title).fontSize(CloudThemeToken.textSizeLarge).fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
        if (desc.length > 0) {
          Text(desc).fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.textSecondary)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(CloudThemeToken.primary)
        .onChange((isOn: boolean) => { onToggle(isOn); })
    }
    .width('100%').height(CloudThemeToken.rowHeight4xl)
    .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: CloudThemeToken.spacingPage }) {
      // header
      Row() {
        Text('相册备份').fontSize(CloudThemeToken.textSizeTitle).fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_xmark_bold')).width(CloudThemeToken.sheetActionIconSize)
            .height(CloudThemeToken.sheetActionIconSize).fillColor(CloudThemeToken.textSecondary).draggable(false)
        }
        .width(CloudThemeToken.iconBoxSm).height(CloudThemeToken.iconBoxSm)
        .borderRadius(CloudThemeToken.controlRadius).backgroundColor(CloudThemeToken.surfaceSubtle)
        .onClick(() => { this.onClose(); })
      }.width('100%').alignItems(VerticalAlign.Center)

      this.switchRow('开启自动备份', '扫描本地图片并上传到云端', this.settings.enabled, (v: boolean) => {
        this.settings.enabled = v;
        this.persist();
      })

      // 备份路径（点开宿主路径选择）
      Row({ space: CloudThemeToken.spacingSection }) {
        Column({ space: CloudThemeToken.spacingXs }) {
          Text('备份路径').fontSize(CloudThemeToken.textSizeLarge).fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
          Text(this.settings.remotePath).fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Image($r('app.media.ic_chevron_right')).width(CloudThemeToken.iconXs).height(CloudThemeToken.iconXs)
          .fillColor(CloudThemeToken.textSecondary).draggable(false)
      }
      .width('100%').height(CloudThemeToken.rowHeight4xl)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .borderRadius(CloudThemeToken.controlRadiusLg).backgroundColor(CloudThemeToken.surface)
      .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.onPickPath(); })

      this.switchRow('仅 Wi-Fi 下备份', '', this.settings.wifiOnly, (v: boolean) => {
        this.settings.wifiOnly = v;
        this.persist();
      })

      // 同时上传数量步进器
      Row({ space: CloudThemeToken.spacingSection }) {
        Column({ space: CloudThemeToken.spacingXs }) {
          Text('同时上传数量').fontSize(CloudThemeToken.textSizeLarge).fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
          Text(`当前 ${this.settings.uploadConcurrent} 个任务同时上传`)
            .fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.textSecondary)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Row({ space: CloudThemeToken.spacingMd }) {
          Text('−').width(CloudThemeToken.rowHeightSm).height(CloudThemeToken.rowHeightSm)
            .fontSize(CloudThemeToken.textSizeLarge).textAlign(TextAlign.Center)
            .fontColor(CloudThemeToken.textPrimary)
            .onClick(() => {
              this.settings.uploadConcurrent =
                PhotoBackupSettingsStore.normalizeConcurrent(this.settings.uploadConcurrent - 1);
              this.persist();
            })
          Text(this.settings.uploadConcurrent.toString())
            .width(CloudThemeToken.rowHeightMd).textAlign(TextAlign.Center)
            .fontColor(CloudThemeToken.textPrimary).fontSize(CloudThemeToken.textSizeLarge)
          Text('+').width(CloudThemeToken.rowHeightSm).height(CloudThemeToken.rowHeightSm)
            .fontSize(CloudThemeToken.textSizeLarge).textAlign(TextAlign.Center)
            .fontColor(CloudThemeToken.primary)
            .onClick(() => {
              this.settings.uploadConcurrent =
                PhotoBackupSettingsStore.normalizeConcurrent(this.settings.uploadConcurrent + 1);
              this.persist();
            })
        }
        .padding({ left: CloudThemeToken.spacingSm, right: CloudThemeToken.spacingSm })
        .borderRadius(CloudThemeToken.controlRadiusRoundMd).backgroundColor(CloudThemeToken.surfaceSubtle)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%').height(CloudThemeToken.rowHeight4xl)
      .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
      .borderRadius(CloudThemeToken.controlRadiusLg).backgroundColor(CloudThemeToken.surface)
      .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal, right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop, bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
    .constraintSize({ minHeight: CloudThemeToken.detailSheetMinHeight })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }
}
```

> 注：实现时如 `CloudThemeToken` 缺少引用到的 token，沿用 `TabMine` 既有同名 token；`PhotoBackupSettings` 需为可 `new` 的默认实例（现有类已支持，确认其字段默认值）。

- [ ] **Step 2: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL（组件未被引用，仅验证可编译）

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/components/PhotoBackupSettingsSheet.ets
git commit -m "feat(mine): photo backup settings sheet component"
```

### Task 6：在「我的」页接入备份设置入口

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabMine.ets`

**背景：** 在 `settingButton()` 的设置列表中新增一行「相册备份」（用既有 `rowWithNext`），副标题显示开启状态；点击打开 `PhotoBackupSettingsSheet`。沿用现有 `bindSheet`/`MineSheetType` 机制：新增枚举值 `PHOTO_BACKUP`，在 `settingsSheet()` 分支渲染新组件，路径选择复用现有 `PathSelectSheet`（已在 TabPictures 用过）经宿主弹出。

- [ ] **Step 1: 扩展 MineSheetType 与 import**

在 `TabMine.ets` 顶部 import 新组件与 `PathSelectSheet`、`PhotoBackupSettingsStore`：

```ts
import { PhotoBackupSettingsSheet } from '../../components/PhotoBackupSettingsSheet';
import { PathSelectSheet } from '../../components/PathSelectSheet';
import { PhotoBackupSettingsStore } from '../../model/PhotoBackupSettingsStore';
import { PhotoBackupSettings } from '../../model/PhotoBackupModel';
```

`MineSheetType` 枚举增加：

```ts
PHOTO_BACKUP = 'photo_backup'
```

新增状态：

```ts
@State photoBackupEnabledText: string = '未开启'
@State showPhotoBackupPathSheet: boolean = false
```

- [ ] **Step 2: 在 settingButton() 增加入口行**

在 `settingButton()` 的 `Column` 内（建议放主题之后、更多设置之前）加：

```ts
this.rowWithNext($r('app.media.ic_photo'),
  CloudThemeToken.settingIconThemeBackground,
  '相册备份',
  this.photoBackupEnabledText,
  () => {
    this.openSettingsSheet(MineSheetType.PHOTO_BACKUP)
  })
```

> 图标资源：若无 `ic_photo`，沿用一个已存在的合适图标（如 `ic_externaldrive_fill`）。在 `loadLocalPreferences()` 末尾刷新 `photoBackupEnabledText`：
> ```ts
> this.photoBackupEnabledText = PhotoBackupSettingsStore.load().enabled ? '已开启' : '未开启'
> ```

- [ ] **Step 3: 在 settingsSheet() 渲染分支**

`openSettingsSheet(type)` 中，在重置各 `show*Sheet` 后增加对 `PHOTO_BACKUP` 的处理（与 THEME/MORE 同构：直接 `this.showSettingsSheet = true` 并 `return`）。在 `settingsSheet()` 的 `@Builder` 分支增加：

```ts
} else if (this.activeSheetType === MineSheetType.PHOTO_BACKUP) {
  this.photoBackupSheet()
}
```

新增 `@Builder`：

```ts
@Builder photoBackupSheet() {
  PhotoBackupSettingsSheet({
    onClose: () => { this.closeSettingsSheet() },
    onPickPath: () => { this.showPhotoBackupPathSheet = true }
  })
}
```

并在 `build()` 的 Stack 内增加一个 `bindSheet` 承载路径选择（复用 `PathSelectSheet`，参数参照其在 `TabPictures` 的用法），选中后写回设置：

```ts
Column().width(0).height(0)
  .bindSheet($$this.showPhotoBackupPathSheet, this.photoBackupPathSheet(), {
    showClose: false, backgroundColor: CloudThemeToken.background,
    onDisappear: () => { this.showPhotoBackupPathSheet = false }
  })
```

```ts
@Builder photoBackupPathSheet() {
  PathSelectSheet({
    onConfirm: (path: string) => {
      const s: PhotoBackupSettings = PhotoBackupSettingsStore.load()
      s.remotePath = path
      PhotoBackupSettingsStore.save(s)
      this.showPhotoBackupPathSheet = false
    },
    onClose: () => { this.showPhotoBackupPathSheet = false }
  })
}
```

> 实现时以 `PathSelectSheet` 在 `TabPictures.pathSelectSheet()` 中的真实 props 为准（打开 `TabPictures.ets` 第 2584 行 `pathSelectSheet()` 抄它的参数形态），本步只表达接线意图。

- [ ] **Step 4: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: 真机验证**

安装运行，进入「我的」→「相册备份」，确认能打开 sheet、切换开关、改并发、选路径并持久化（杀进程重进仍在）。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/pages/tabs/TabMine.ets
git commit -m "feat(mine): add photo backup settings entry and sheet wiring"
```

---

## Phase 3：相册页 UI 组件

### Task 7：时间/相册分段控件

**Files:**
- Create: `entry/src/main/ets/components/PhotoGallerySegment.ets`

- [ ] **Step 1: 实现组件**

`entry/src/main/ets/components/PhotoGallerySegment.ets`:

```ts
import { CloudThemeToken } from '../model/CloudTheme';
import { GallerySegment } from '../model/PhotoGalleryModel';

@Component
export struct PhotoGallerySegment {
  @Prop current: GallerySegment = GallerySegment.TIME;
  onSelect: (seg: GallerySegment) => void = () => {};

  @Builder seg(title: string, value: GallerySegment) {
    Text(title)
      .layoutWeight(1).textAlign(TextAlign.Center)
      .height(CloudThemeToken.rowHeight2xl)
      .fontSize(CloudThemeToken.textSizeBody)
      .fontWeight(this.current === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.current === value ? CloudThemeToken.textPrimary : CloudThemeToken.textSecondary)
      .backgroundColor(this.current === value ? CloudThemeToken.surface : Color.Transparent)
      .borderRadius(CloudThemeToken.controlRadius)
      .onClick(() => { this.onSelect(value); })
  }

  build() {
    Row() {
      this.seg('时间', GallerySegment.TIME)
      this.seg('相册', GallerySegment.ALBUM)
    }
    .width('100%').padding(CloudThemeToken.spacingXs)
    .borderRadius(CloudThemeToken.controlRadiusLg)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
  }
}
```

- [ ] **Step 2: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/components/PhotoGallerySegment.ets
git commit -m "feat(album): time/album segment control"
```

### Task 8：顶部进度抽屉组件

**Files:**
- Create: `entry/src/main/ets/components/PhotoBackupDrawer.ets`

**背景：** 抽屉内容（设计稿 §3.2）：总进度文案 + 进度条 + 暂停/继续 + 立即备份 + 上传中/待备份/失败计数（失败可点重试）；备份关闭时显示「备份已关闭，去开启」。抽屉是受控展开/收起，运行态数据由相册页通过 `@Prop` 注入，操作通过回调上抛。

- [ ] **Step 1: 实现组件**

`entry/src/main/ets/components/PhotoBackupDrawer.ets`:

```ts
import { CloudThemeToken } from '../model/CloudTheme';

@Component
export struct PhotoBackupDrawer {
  @Prop enabled: boolean = false;
  @Prop running: boolean = false;
  @Prop paused: boolean = false;
  @Prop completedCount: number = 0;
  @Prop localCount: number = 0;
  @Prop uploadingCount: number = 0;
  @Prop waitingCount: number = 0;
  @Prop failedCount: number = 0;
  @Prop statusText: string = '';

  onPrimary: () => void = () => {};        // 立即备份
  onPauseResume: () => void = () => {};     // 暂停/继续
  onRetryFailed: () => void = () => {};     // 重试失败
  onGoEnable: () => void = () => {};        // 去开启（跳我的）

  @Builder metric(value: number, label: string, color: ResourceColor, onTap?: () => void) {
    Column({ space: CloudThemeToken.spacingXs }) {
      Text(value.toString()).fontSize(CloudThemeToken.textSizeTitle).fontWeight(FontWeight.Bold).fontColor(color)
      Text(label).fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.textSecondary)
    }
    .onClick(() => { if (onTap) { onTap(); } })
  }

  build() {
    Column({ space: CloudThemeToken.spacingSection }) {
      if (!this.enabled) {
        Row() {
          Text('备份已关闭').fontSize(CloudThemeToken.textSizeBody).fontColor(CloudThemeToken.textSecondary).layoutWeight(1)
          Button('去开启').fontSize(CloudThemeToken.textSizeSmallPlus).height(CloudThemeToken.rowHeightSm)
            .onClick(() => { this.onGoEnable(); })
        }.width('100%').alignItems(VerticalAlign.Center)
      } else {
        Row() {
          Column({ space: CloudThemeToken.spacingXs }) {
            Text(this.statusText).fontSize(CloudThemeToken.textSizeBody).fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary)
            Text(`已备份 ${this.completedCount} / ${this.localCount}`)
              .fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.textSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.running || this.paused) {
            Button(this.paused ? '继续' : '暂停').fontSize(CloudThemeToken.textSizeSmallPlus)
              .height(CloudThemeToken.rowHeightSm).backgroundColor(CloudThemeToken.surface)
              .fontColor(CloudThemeToken.primary).onClick(() => { this.onPauseResume(); })
          } else {
            Button('立即备份').fontSize(CloudThemeToken.textSizeSmallPlus)
              .height(CloudThemeToken.rowHeightSm).onClick(() => { this.onPrimary(); })
          }
        }.width('100%').alignItems(VerticalAlign.Center)

        Progress({ value: this.completedCount, total: Math.max(this.localCount, 1), type: ProgressType.Capsule })
          .width('100%').height(CloudThemeToken.storageProgressHeight)
          .color(CloudThemeToken.primary).backgroundColor(CloudThemeToken.surfaceSubtle)

        Row({ space: CloudThemeToken.spacingPage }) {
          this.metric(this.uploadingCount, '上传中', CloudThemeToken.primary)
          this.metric(this.waitingCount, '待备份', CloudThemeToken.textPrimary)
          this.metric(this.failedCount, '失败 · 重试', CloudThemeToken.danger, () => {
            if (this.failedCount > 0) { this.onRetryFailed(); }
          })
        }.width('100%').justifyContent(FlexAlign.Start)
      }
    }
    .width('100%').padding(CloudThemeToken.spacingPage)
    .borderRadius(CloudThemeToken.cardRadius).backgroundColor(CloudThemeToken.surface)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
  }
}
```

- [ ] **Step 2: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/components/PhotoBackupDrawer.ets
git commit -m "feat(album): top progress drawer component"
```

### Task 9：瀑布流网格组件

**Files:**
- Create: `entry/src/main/ets/components/PhotoGalleryGrid.ets`

**背景：** 用 `Task 3` 的分组 + `Task 4` 的行布局算出每张图尺寸，渲染分组标题 + 等高行；每张图右下角按 `Task 2` 映射叠加角标。缩略图复用相册页注入的 `@Provide photoBackupThumbs: Map<string, PixelMap>`（现有机制），缺图时显示占位并回调请求加载。点击回调上抛 `(item, flatIndex)` 供预览。

容器宽度通过 `onAreaChange` 获取；目标行高用一个 token（如 `CloudThemeToken.photoGalleryRowHeight`，若无则用常量 110vp）。

- [ ] **Step 1: 实现组件**

`entry/src/main/ets/components/PhotoGalleryGrid.ets`:

```ts
import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupItem, PhotoBackupStatus } from '../model/PhotoBackupModel';
import { PhotoGroup, JustifiedRow, justifyRows, badgeForStatus, PhotoBadge } from '../model/PhotoGalleryModel';

const ROW_TARGET_HEIGHT: number = 112;
const GAP: number = 3;

@Component
export struct PhotoGalleryGrid {
  @Prop groups: PhotoGroup[] = [];
  @Prop backupEnabled: boolean = false;
  @Consume photoBackupThumbs: Map<string, PixelMap>;
  onRequestThumb: (item: PhotoBackupItem) => void = () => {};
  onTapPhoto: (item: PhotoBackupItem) => void = () => {};
  @State containerWidth: number = 0;

  private ratioOf(item: PhotoBackupItem): number {
    // 缩略图为方图时 ratio≈1；如 PhotoBackupItem 未携带宽高，统一按 1:1
    return 1;
  }

  @Builder badge(item: PhotoBackupItem) {
    if (badgeForStatus(item.status, this.backupEnabled) === PhotoBadge.CLOUD) {
      this.badgeDot($r('app.media.ic_cloud'), 0x99000000)
    } else if (badgeForStatus(item.status, this.backupEnabled) === PhotoBadge.UPLOADING) {
      this.badgeDot($r('app.media.ic_arrow_up'), CloudThemeToken.primary)
    } else if (badgeForStatus(item.status, this.backupEnabled) === PhotoBadge.FAILED) {
      this.badgeDot($r('app.media.ic_exclamationmark'), CloudThemeToken.danger)
    }
  }

  @Builder badgeDot(icon: ResourceStr, bg: ResourceColor) {
    Image(icon).width(10).height(10).fillColor(Color.White).draggable(false)
      .padding(3).backgroundColor(bg).borderRadius(9)
      .position({ right: 4, bottom: 4 })
  }

  @Builder photoCell(item: PhotoBackupItem, w: number, h: number) {
    Stack() {
      if (this.photoBackupThumbs.has(item.id)) {
        Image(this.photoBackupThumbs.get(item.id)).width(w).height(h).objectFit(ImageFit.Cover)
          .borderRadius(CloudThemeToken.cardRadius).draggable(false)
      } else {
        Column().width(w).height(h).borderRadius(CloudThemeToken.cardRadius)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .onAppear(() => { this.onRequestThumb(item); })
      }
      this.badge(item)
    }
    .width(w).height(h)
    .onClick(() => { this.onTapPhoto(item); })
  }

  build() {
    List({ space: CloudThemeToken.spacingSection }) {
      ForEach(this.groups, (group: PhotoGroup) => {
        ListItem() {
          Column({ space: GAP }) {
            Text(group.title).fontSize(CloudThemeToken.textSizeBody).fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary).width('100%').textAlign(TextAlign.Start)
            ForEach(justifyRows(group.items.map((it: PhotoBackupItem) => this.ratioOf(it)),
              this.containerWidth > 0 ? this.containerWidth : 360, ROW_TARGET_HEIGHT, GAP),
              (row: JustifiedRow) => {
                Row({ space: GAP }) {
                  ForEach(row.widths, (w: number, i: number) => {
                    this.photoCell(group.items[row.startIndex + i], w, row.height)
                  })
                }.width('100%')
              })
          }.width('100%')
        }
      })
    }
    .width('100%').height('100%').scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onAreaChange((_o: Area, n: Area) => { this.containerWidth = n.width as number; })
  }
}
```

> 实现注意：图标资源 `ic_cloud/ic_arrow_up/ic_exclamationmark` 若不存在，用 `Text('☁'/'↑'/'!')` 替代或新增图标资源；`PhotoBackupStatus` 从 `PhotoBackupModel` 导入。`onAppear` 触发缩略图懒加载，沿用相册页现有 `loadPhotoThumbnail`。

- [ ] **Step 2: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/components/PhotoGalleryGrid.ets
git commit -m "feat(album): justified waterfall grid with status badges"
```

---

## Phase 4：本地大图预览

### Task 10：本地图预览页 + 路由常量

**Files:**
- Create: `entry/src/main/ets/pages/PhotoLocalPreview.ets`
- Modify: `entry/src/main/ets/model/Constant.ets`

**背景：** 现有 `ImagePreviewPage` 走云端下载，不适合本地图。新建本地预览页：用 `@HMRouter` 注册，接收一组本地照片（URI + 元数据）与起始下标，左右滑动，底部信息条显示 文件名/时间/大小/尺寸/备份状态路径（设计稿 §3.5），失败态可重试、未备份态可"立即备份这张"。本地图直接用 `Image(uri)` 渲染。

- [ ] **Step 1: 新增路由常量**

在 `Constant.ets` 增加（参照现有页面常量写法，如 `ABOUT_PAGE`）：

```ts
PHOTO_LOCAL_PREVIEW_PAGE: string = 'PhotoLocalPreviewPage'
```

- [ ] **Step 2: 实现预览页**

`entry/src/main/ets/pages/PhotoLocalPreview.ets`（结构示意，含完整骨架）：

```ts
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupItem, PhotoBackupStatus } from '../model/PhotoBackupModel';
import { CommonUtil } from '../utils/CommonUtil';
import { DateFormatUtil } from '../utils/DateFormatUtil';

@HMRouter({ pageUrl: Constant.PHOTO_LOCAL_PREVIEW_PAGE })
@Component
export struct PhotoLocalPreviewPage {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State items: PhotoBackupItem[] = [];
  @State index: number = 0;
  @State backupEnabled: boolean = false;

  aboutToAppear(): void {
    const param = HMRouterMgr.getCurrentParam() as Record<string, Object> | undefined;
    if (param) {
      this.items = (param.items as PhotoBackupItem[]) ?? [];
      this.index = (param.index as number) ?? 0;
      this.backupEnabled = (param.backupEnabled as boolean) ?? false;
    }
  }

  private statusLine(item: PhotoBackupItem): string {
    if (item.status === PhotoBackupStatus.COMPLETED) {
      return `已备份`;
    }
    if (!this.backupEnabled) {
      return '未备份';
    }
    if (item.status === PhotoBackupStatus.UPLOADING) { return '上传中'; }
    if (item.status === PhotoBackupStatus.FAILED) { return '备份失败 · 点击重试'; }
    return '待备份';
  }

  @Builder infoBar(item: PhotoBackupItem) {
    Column({ space: CloudThemeToken.spacingXs }) {
      Text(item.name).fontSize(CloudThemeToken.textSizeBody).fontColor(Color.White).fontWeight(FontWeight.Medium)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${DateFormatUtil.format(new Date(item.modifiedAt), 'yyyy/MM/dd HH:mm')} · ${CommonUtil.formatBytes(item.size)}`)
        .fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.textSecondary)
      Text(this.statusLine(item)).fontSize(CloudThemeToken.textSizeSmall).fontColor(CloudThemeToken.primary)
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(CloudThemeToken.spacingPage)
    .backgroundColor(0xCC000000)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper() {
        ForEach(this.items, (item: PhotoBackupItem) => {
          Image(item.uri).width('100%').height('100%').objectFit(ImageFit.Contain).draggable(false)
        }, (item: PhotoBackupItem) => item.id)
      }
      .index(this.index).loop(false).indicator(false)
      .onChange((i: number) => { this.index = i; })
      .width('100%').height('100%')

      if (this.items.length > 0 && this.index < this.items.length) {
        Column() { this.infoBar(this.items[this.index]) }
          .width('100%').padding({ bottom: this.bottomRectHeight })
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
  }
}
```

> 注：`HMRouterMgr.getCurrentParam` 的真实取参方式以项目内其他 `@HMRouter` 页面（如 `ImagePreview.ets`/`VideoPreview.ets`）为准，照其形态接 `routeParam`；本步表达数据契约（items/index/backupEnabled）。失败重试/单张备份的回调接线放 Task 12 与相册页打通。

- [ ] **Step 3: 确认路由已被 hmrouter 插件收集**

新页带 `@HMRouter` 装饰，构建时由 `@hadss/hmrouter-plugin` 自动收进路由表。

- [ ] **Step 4: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/pages/PhotoLocalPreview.ets entry/src/main/ets/model/Constant.ets
git commit -m "feat(album): local photo preview page with info bar"
```

---

## Phase 5：相册页整合与旧 UI 移除

### Task 11：用新组件重写 TabPictures 的 build 层

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabPictures.ets`

**背景：** 这是核心整合。保留文件内所有备份引擎方法（扫描/合并/done-ids/上传队列/缩略图/权限），**仅替换 `build()` 与展示用 `@Builder`**：新 build = 顶栏(标题+抽屉开关) + 可展开 `PhotoBackupDrawer` + `PhotoGallerySegment` + `PhotoGalleryGrid`。设置改为从 `PhotoBackupSettingsStore` 读取（不再有页面内设置面板）。新增 `@State drawerOpen`、`@State segment: GallerySegment`、`@State groups: PhotoGroup[]`，按分段调用 `groupByDate/groupByAlbum`。监听 `AppStorage` 的 `PHOTO_BACKUP_REVISION_KEY` 以在「我的」改设置后刷新。

- [ ] **Step 1: 顶部新增 import 与状态**

```ts
import { PhotoBackupDrawer } from '../../components/PhotoBackupDrawer';
import { PhotoGalleryGrid } from '../../components/PhotoGalleryGrid';
import { PhotoGallerySegment } from '../../components/PhotoGallerySegment';
import { GallerySegment, PhotoGroup, groupByDate, groupByAlbum } from '../../model/PhotoGalleryModel';
import { PhotoBackupSettingsStore, PHOTO_BACKUP_REVISION_KEY } from '../../model/PhotoBackupSettingsStore';
import { CloudRouter } from '../../utils/CloudRouter';
```

新增字段：

```ts
@State drawerOpen: boolean = false;
@State segment: GallerySegment = GallerySegment.TIME;
@State galleryGroups: PhotoGroup[] = [];
@StorageProp(PHOTO_BACKUP_REVISION_KEY) @Watch('onSettingsRevisionChanged') settingsMirrorRevision: number = 0;
```

- [ ] **Step 2: 替换 build()**

把现有 `build()`（第 1548 行起）整体替换为：

```ts
build() {
  Stack({ alignContent: Alignment.Bottom }) {
    Column({ space: CloudThemeToken.sectionGap }) {
      // 顶栏
      Row() {
        Text('相册').fontSize(CloudThemeToken.textSizeHero).fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_chevron_down')).width(CloudThemeToken.iconMd).height(CloudThemeToken.iconMd)
            .fillColor(CloudThemeToken.onPrimary)
            .rotate({ angle: this.drawerOpen ? 180 : 0 }).draggable(false)
        }
        .width(CloudThemeToken.iconBoxSm).height(CloudThemeToken.iconBoxSm)
        .backgroundColor(CloudThemeToken.primary)
        .onClick(() => {
          this.getUIContext().animateTo({ duration: CloudThemeToken.defaultAnimationDuration, curve: Curve.EaseOut },
            () => { this.drawerOpen = !this.drawerOpen; })
        })
      }.width('100%').alignItems(VerticalAlign.Center)

      // 抽屉（展开时显示）
      if (this.drawerOpen) {
        PhotoBackupDrawer({
          enabled: this.getSettingsEnabled(), running: this.isBackupRunning(),
          paused: this.backupState === PhotoBackupState.PAUSED,
          completedCount: this.completedPhotoCount, localCount: this.localPhotoCount,
          uploadingCount: this.uploadingPhotoCount, waitingCount: this.waitingPhotoCount,
          failedCount: this.failedPhotoCount, statusText: this.getStatusText(),
          onPrimary: () => { this.startBackup(); },
          onPauseResume: () => { this.isBackupRunning() ? this.pauseBackup() : this.startBackup(); },
          onRetryFailed: () => { this.retryFailedPhotos(); },
          onGoEnable: () => { CloudRouter.push(Constant.HOME_PAGE_MINE /* 或跳我的 tab 的既有方式 */); }
        })
      }

      PhotoGallerySegment({
        current: this.segment,
        onSelect: (seg: GallerySegment) => { this.segment = seg; this.rebuildGroups(); }
      })

      PhotoGalleryGrid({
        groups: this.galleryGroups, backupEnabled: this.getSettingsEnabled(),
        onRequestThumb: (item: PhotoBackupItem) => { this.loadPhotoThumbnail(item); },
        onTapPhoto: (item: PhotoBackupItem) => { this.openLocalPreview(item); }
      }).layoutWeight(1)
    }
    .width('100%').height('100%')
    .padding({
      left: CloudThemeToken.pagePadding, right: CloudThemeToken.pagePadding,
      top: this.getTopInset() + CloudThemeToken.scaffoldTopPadding,
      bottom: this.tabBarHeight + CloudThemeToken.scaffoldBottomPadding
    })
    .backgroundColor(CloudThemeToken.background)
  }.width('100%').height('100%')
}
```

> `CloudRouter.push(...)` 跳「我的」的具体方式以项目既有跳转/切 tab 实现为准；若无直接跳 tab 的 API，可 `showToast('请在「我的-相册备份」中开启')`。

- [ ] **Step 3: 新增 rebuildGroups / openLocalPreview / retryFailedPhotos / onSettingsRevisionChanged**

```ts
rebuildGroups(): void {
  const list = this.getPhotos();
  this.galleryGroups = this.segment === GallerySegment.TIME
    ? groupByDate(list, new Date()) : groupByAlbum(list);
}

onSettingsRevisionChanged(): void {
  this.loadSettings();           // 已有方法，改为内部走 PhotoBackupSettingsStore.load()
  this.rebuildGroups();
}

openLocalPreview(item: PhotoBackupItem): void {
  const flat = this.getPhotos();
  const idx = flat.findIndex((it: PhotoBackupItem) => it.id === item.id);
  CloudRouter.push(Constant.PHOTO_LOCAL_PREVIEW_PAGE, {
    items: flat, index: Math.max(idx, 0), backupEnabled: this.getSettingsEnabled()
  });
}

retryFailedPhotos(): void {
  // 把 FAILED 项重置为 WAITING 后触发 startBackup（沿用现有 setPhotoStatus / startBackup）
  this.getFailedItems().forEach((it: PhotoBackupItem) =>
    this.setPhotoStatus(it, PhotoBackupStatus.WAITING, 0, ''));
  this.startBackup();
}
```

> `CloudRouter.push` 带参形态以项目既有用法为准（参照 `ImagePreview` 打开方式）。`loadSettings()` 改为 `this.applySettings(PhotoBackupSettingsStore.load())`。

- [ ] **Step 4: 在扫描/统计更新后调用 rebuildGroups**

在 `refreshPhotoStats()` 的 `runInUiScope` 回调末尾、以及 `scanLocalPhotos` 合并完成后，追加 `this.rebuildGroups();`，保证网格随数据刷新。

- [ ] **Step 5: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL（此时旧 `@Builder`（summaryCard 等）可能仍存在但未被引用——下个任务删除）

- [ ] **Step 6: 真机验证**

运行进入相册 tab：确认显示照片网格、分段切换、点抽屉开关展开/收起进度、点图进预览。

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/pages/tabs/TabPictures.ets
git commit -m "feat(album): rebuild picture tab with gallery grid, drawer and segment"
```

### Task 12：填本地相册名、接预览操作、删除旧 UI

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabPictures.ets`

- [ ] **Step 1: 扫描时填充 albumName（支持相册分组）**

在 `readPhotoFetchResult` / `createBackupItem` 链路中，给 item 写入相册名：用 `photoAccessHelper` 的 album 查询为 asset 归属相册赋值。最简实现——在 `scanLocalPhotos` 中改为遍历 `getAlbums()` 拿到每个相册（`albumName`）再取其资产，给每个 item `item.albumName = album.albumName`。若实现成本高，先用资产 URI 推断目录名作为 albumName 的兜底。

```ts
// createBackupItem 增加可选参数或在调用处赋值：
item.albumName = albumName ?? '';
```

- [ ] **Step 2: 预览页失败重试/单张备份接线**

`PhotoLocalPreview` 的信息条状态行点击时，通过路由返回参数或共享回调通知相册页对该 item 重试/备份。最简方案：预览页只展示状态；重试/单张备份入口留在相册页抽屉（失败计数点重试）。**本步确认：预览页信息条仅展示，不内置操作按钮**（与设计"信息条"一致），避免跨页回调复杂度。

- [ ] **Step 3: 删除旧展示 Builder**

删除 `TabPictures.ets` 中不再引用的旧 `@Builder`：`summaryCard`、`permissionHintCard`(若保留空状态另写)、`emptyPathCard`、`sectionUploading/uploadingItem/...`、`compactPhotoSection`、`sectionWaiting/Failed/Completed/BackupHistory`、`settingsPanel`、`pathRow`、旧 `header`、以及随之无用的 preview dataSource 字段。**保留**：缩略图加载、扫描、备份引擎、done-ids、统计计算（`refreshPhotoStats` 等仍驱动抽屉计数）。

> 删除前用编译器/搜索确认每个 Builder 无引用再删，逐个删除并编译，避免一次删多。

- [ ] **Step 4: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: 真机验证**

相册 tab 全流程：时间/相册分组正确、角标语义正确（已备份☁、上传中蓝↑、失败红!、未备份无；关闭备份时已备份仍☁）、抽屉进度与操作可用、预览信息条正确。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/pages/tabs/TabPictures.ets
git commit -m "refactor(album): fill album names, finalize preview, remove legacy backup UI"
```

### Task 13：空状态与权限态

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabPictures.ets`

**背景：** 设计稿 §3.6：未授权→空状态 + 「授权读取相册」按钮；本地无照片→空状态文案。复用现有 `EmptyState` 组件。

- [ ] **Step 1: 在网格区按条件渲染空状态**

在 build 的网格位置改为：

```ts
if (this.permissionHint.length > 0 && this.getPhotos().length === 0) {
  // 权限/空：复用 EmptyState，提供授权按钮
  Column() {
    EmptyState({ /* 文案/图标按 EmptyState 既有 props */ })
    Button('授权读取相册').onClick(() => { this.scanLocalPhotos(true, false); })
  }.layoutWeight(1).justifyContent(FlexAlign.Center)
} else if (this.getPhotos().length === 0) {
  EmptyState({ /* 本地无照片文案 */ })
} else {
  PhotoGalleryGrid({ /* 同 Task 11 */ })
}
```

> `EmptyState` 真实 props 以 `components/EmptyState.ets` 为准。

- [ ] **Step 2: 编译验证**

Run: `./hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: 真机验证**

撤销相册权限后进入相册 tab → 显示空状态与授权按钮；授权后自动扫描出图。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/pages/tabs/TabPictures.ets
git commit -m "feat(album): empty and permission states for gallery"
```

---

## 收尾验证

- [ ] 全量编译：`./hvigorw assembleHap` BUILD SUCCESSFUL
- [ ] 单测：`./hvigorw test -p module=entry@ohosTest` 全绿（store + gallery model）
- [ ] 真机回归：相册浏览/分组/角标/抽屉/预览；「我的」备份设置改动能同步到相册页；备份开/关行为符合设计
- [ ] Code Linter：DevEco「Code Linter」或 `./hvigorw codeLinter` 无新增告警

## 实现期可能需查证的点（非阻塞）

- `PathSelectSheet` 的真实 props（`TabPictures.ets:2584 pathSelectSheet()`）。
- `CloudRouter.push` 带参与跳转/切 tab 的真实 API（参照 `ImagePreview` 打开方式与 `HomePage` tab 切换）。
- `photoAccessHelper` 取相册（album/bucket）名的查询写法。
- 角标/图标资源是否存在（`ic_cloud` 等），不存在则补资源或用文字。
- `EmptyState` 组件 props。
