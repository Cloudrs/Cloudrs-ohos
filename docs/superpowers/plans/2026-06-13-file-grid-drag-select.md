# 文件多选拖动框选 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在文件页多选模式下,新增触屏「长按某项后拖动连续选择」和鼠标「拖框框选」,两者都 additive 保留已有选择、可在手势内反向撤销。

**Architecture:** 把选择范围的纯逻辑(锚点模式、范围加减、快照可逆)抽成一个无 ArkUI 依赖的 `DragSelectController`(可在本地单测覆盖);`TabFiles` 的 `Grid` 用 HarmonyOS 原生 `multiSelectable` 接鼠标框选,用 `LongPressGesture+PanGesture` + `componentUtils` 命中测试接触屏拖选,两条路都驱动同一个 controller。

**Tech Stack:** ArkTS / ArkUI(`Grid`/`GridItem`、`multiSelectable`、`GestureGroup`、`componentUtils.getRectangleById`)、`@ohos/hypium`(本地单测)。

参考设计文档:`docs/superpowers/specs/2026-06-13-file-grid-drag-select-design.md`

---

## File Structure

- **Create** `entry/src/main/ets/model/DragSelectModel.ets` — 纯逻辑:`DragMode` 枚举 + `DragSelectController` 类(锚点/模式/快照/范围加减)。无 ArkUI 依赖。
- **Create** `entry/src/test/DragSelectModel.test.ets` — `DragSelectController` 的本地单元测试(hypium)。
- **Modify** `entry/src/test/List.test.ets` — 注册新测试套件。
- **Create** `entry/src/main/ets/utils/GridHitTest.ets` — `hitTestItemId(point, ids, uiContext)`:用 `componentUtils.getRectangleById` 在可见项里找包含触点的 id。隔离 ArkUI 几何细节。
- **Modify** `entry/src/main/ets/pages/tabs/TabFiles.ets` — 接线:统一线性 id 序、`selectedIds: Set` 与 `selectedObjects` 同步、鼠标 `multiSelectable`、触屏长按+Pan 手势、命中测试、边缘自动滚动。

约束:`TabFiles.ets` 已经很大,新增**纯逻辑放 `DragSelectModel`、几何放 `GridHitTest`**,`TabFiles` 只持有状态 + 调接口。

---

## Task 1: DragSelectController 纯逻辑 + 本地单测(TDD)

**Files:**
- Create: `entry/src/main/ets/model/DragSelectModel.ets`
- Test: `entry/src/test/DragSelectModel.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 先写空实现骨架(让测试能 import)**

Create `entry/src/main/ets/model/DragSelectModel.ets`:

```ts
export enum DragMode {
  SELECT = 0,
  DESELECT = 1
}

export class DragSelectController {
  private base: Set<string> = new Set<string>()
  private mode: DragMode = DragMode.SELECT
  private anchorIndex: number = -1
  private active: boolean = false

  isActive(): boolean {
    return this.active
  }

  getMode(): DragMode {
    return this.mode
  }

  // 开始一次拖选:锚点下标、统一线性 id 序、当前已选集合
  begin(anchorIndex: number, orderedIds: string[], current: Set<string>): void {
    this.active = true
    this.anchorIndex = anchorIndex
    this.base = new Set<string>(current)
    const anchorId = orderedIds[anchorIndex]
    this.mode = (anchorId !== undefined && current.has(anchorId)) ? DragMode.DESELECT : DragMode.SELECT
  }

  // 拖到 currentIndex,返回新的已选集合(base 上按 mode 对 [anchor,current] 范围加减)
  dragTo(currentIndex: number, orderedIds: string[]): Set<string> {
    const result = new Set<string>(this.base)
    if (this.anchorIndex < 0 || currentIndex < 0) {
      return result
    }
    const lo = Math.min(this.anchorIndex, currentIndex)
    const hi = Math.max(this.anchorIndex, currentIndex)
    for (let i = lo; i <= hi; i++) {
      const id = orderedIds[i]
      if (id === undefined) {
        continue
      }
      if (this.mode === DragMode.SELECT) {
        result.add(id)
      } else {
        result.delete(id)
      }
    }
    return result
  }

  end(): void {
    this.active = false
    this.anchorIndex = -1
  }
}
```

- [ ] **Step 2: 写失败测试**

Create `entry/src/test/DragSelectModel.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import { DragSelectController, DragMode } from '../main/ets/model/DragSelectModel';

const IDS: string[] = ['a', 'b', 'c', 'd', 'e', 'f'];

export default function dragSelectModelTest() {
  describe('DragSelectController', () => {
    it('begin_on_unselected_sets_SELECT_mode', 0, () => {
      const c = new DragSelectController();
      c.begin(3, IDS, new Set<string>());
      expect(c.getMode()).assertEqual(DragMode.SELECT);
      expect(c.isActive()).assertTrue();
    });

    it('begin_on_selected_sets_DESELECT_mode', 0, () => {
      const c = new DragSelectController();
      c.begin(1, IDS, new Set<string>(['b']));
      expect(c.getMode()).assertEqual(DragMode.DESELECT);
    });

    it('drag_forward_selects_range_and_keeps_existing', 0, () => {
      const c = new DragSelectController();
      // 已选 a,b;长按 d(未选)拖到 f
      c.begin(3, IDS, new Set<string>(['a', 'b']));
      const r = c.dragTo(5, IDS); // 范围 d..f
      expect(r.has('a')).assertTrue();
      expect(r.has('b')).assertTrue();
      expect(r.has('d')).assertTrue();
      expect(r.has('e')).assertTrue();
      expect(r.has('f')).assertTrue();
      expect(r.has('c')).assertFalse();
    });

    it('drag_backward_reverts_items_leaving_range', 0, () => {
      const c = new DragSelectController();
      c.begin(3, IDS, new Set<string>()); // 锚点 d
      c.dragTo(5, IDS);                    // 先拖到 f -> d,e,f
      const r = c.dragTo(4, IDS);          // 再往回拖到 e -> 只剩 d,e;f 回退
      expect(r.has('d')).assertTrue();
      expect(r.has('e')).assertTrue();
      expect(r.has('f')).assertFalse();
    });

    it('deselect_drag_removes_range_keeps_others', 0, () => {
      const c = new DragSelectController();
      // 已选 a,b,c;长按 b(已选)拖到 a -> 取消 a,b,保留 c
      c.begin(1, IDS, new Set<string>(['a', 'b', 'c']));
      const r = c.dragTo(0, IDS);
      expect(r.has('a')).assertFalse();
      expect(r.has('b')).assertFalse();
      expect(r.has('c')).assertTrue();
    });
  });
}
```

- [ ] **Step 3: 注册测试套件**

Modify `entry/src/test/List.test.ets` — 在现有 `localUnitTest()` 旁加一行:

```ts
import localUnitTest from './LocalUnit.test';
import dragSelectModelTest from './DragSelectModel.test';

export default function testsuite() {
  localUnitTest();
  dragSelectModelTest();
}
```

- [ ] **Step 4: 跑测试,确认通过**

让用户在 DevEco 里对 `entry/src/test`(Local Unit Test)运行测试,或 CLI:
Run: `./hvigorw test -p module=entry@ohosTest`(本项目测试入口;本地单测在 DevEco 的 "Run Local Test" 里更直接)
Expected: `DragSelectController` 5 个用例全部 PASS。
> 备注:Step 1 已给出正确实现,这些用例应直接通过(逻辑简单、先写实现再补测试以保证可编译;若某条失败,按断言修 `DragSelectModel.ets`)。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/model/DragSelectModel.ets entry/src/test/DragSelectModel.test.ets entry/src/test/List.test.ets
git commit -m "feat(files): add DragSelectController selection-range logic with tests"
```

---

## Task 2: TabFiles 选择集合改造(selectedIds + 线性序)

把现有 `selectedObjects: ObjectInfo[]` 配一个 `selectedIds: Set<string>` 做 O(1) 命中,并提供统一线性 id 序。**纯接线,不改交互**,先保证回归不破。

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabFiles.ets`

- [ ] **Step 1: 加状态与同步辅助**

在 `TabFiles` 类里(`selectedObjects` 声明附近)新增:

```ts
@State selectedIds: Set<string> = new Set<string>()
```

新增辅助方法(放在 `enterMultiSelectMode` 附近):

```ts
private isSelected(item: ObjectInfo): boolean {
  return this.selectedIds.has(item.id)
}

// 统一线性 id 序:目录在前、文件在后(与 Grid 渲染顺序一致)
private buildOrderedIds(): string[] {
  const ids: string[] = []
  this.dirFileInfo.dirObjects.forEach((o: ObjectInfo) => ids.push(o.id))
  this.dirFileInfo.fileObjects.forEach((o: ObjectInfo) => ids.push(o.id))
  return ids
}

// 用一个新的已选集合刷新 selectedObjects + selectedIds(保持二者同步)
private applySelection(ids: Set<string>): void {
  const all: ObjectInfo[] = this.dirFileInfo.dirObjects.concat(this.dirFileInfo.fileObjects)
  this.selectedObjects = all.filter((o: ObjectInfo) => ids.has(o.id))
  this.selectedIds = new Set<string>(ids)
}
```

> 确认点:`this.dirFileInfo` 是当前持有 `dirObjects`/`fileObjects` 的对象(`DirFileInfo`,见 `model/net/ApiTypes.ets`)。若 `TabFiles` 里字段名不同(如 `this.dirInfo`),按实际改;`ObjectInfo.id: string` 已存在(LazyForEach key 用的就是 `item.id`)。

- [ ] **Step 2: 让现有点选走 applySelection**

找到 `onItemClick(item)` 里切换选中的逻辑,把对 `selectedObjects` 的增删改成:命中则移除、未命中则加入,然后调用 `this.applySelection(newSet)`。示例(按现有代码语义替换):

```ts
private toggleSelect(item: ObjectInfo): void {
  const ids = new Set<string>(this.selectedIds)
  if (ids.has(item.id)) {
    ids.delete(item.id)
  } else {
    ids.add(item.id)
  }
  this.applySelection(ids)
}
```

并在 `onItemClick` 多选分支里调用 `this.toggleSelect(item)`。`exitMultiSelectMode()` 里追加 `this.selectedIds = new Set<string>()`。

- [ ] **Step 3: 编译**

Run: 让用户编译(`hvigorw assembleHap`)。
Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: 模拟器回归**

让用户在 5555 上进多选、点选若干、退出 —— 选中高亮、计数、批量操作与改造前一致。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/pages/tabs/TabFiles.ets
git commit -m "refactor(files): track multi-select with selectedIds set + linear order"
```

---

## Task 3: 鼠标框选(原生 multiSelectable)

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabFiles.ets`

- [ ] **Step 1: 开启 Grid 框选并接 GridItem**

在 `objectGrid()` 的 `Grid(this.scrollerForList) { ... }` 上加:

```ts
.multiSelectable(true)
```

给两段 `LazyForEach` 里的 `GridItem()` 都加(目录段、文件段同样处理):

```ts
GridItem() {
  ObjectItem({ index, item, showType: this.showType, /* ...原有参数... */
    selected: this.isSelected(item) })
}
.id(item.id)
.selectable(true)
.selected(this.isSelected(item))
.onSelect((isSelected: boolean) => {
  this.onBoxSelect(item, isSelected)
})
.onClick(async () => { this.onItemClick(item) })
```

- [ ] **Step 2: 实现 onBoxSelect(additive)**

```ts
private onBoxSelect(item: ObjectInfo, isSelected: boolean): void {
  if (!this.isMultiSelectMode) {
    this.enterMultiSelectMode()   // 未进多选时,拉框自动进入
  }
  const ids = new Set<string>(this.selectedIds)
  if (isSelected) {
    ids.add(item.id)
  } else {
    ids.delete(item.id)
  }
  this.applySelection(ids)
}
```

- [ ] **Step 3: 编译**

Run: 用户编译。Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: 模拟器验证 + 关键 spike(2in1 / 5557)**

让用户在 5557 上:① 多选模式下鼠标拉框 → 框内项选中;② 未进多选时拉框 → 自动进入多选并选中;③ **关键验证(spike):先点选 A、B,再到别处拉一个不含 A、B 的框 → 确认 A、B 是否还在。**
- 若 A、B 保留 → 原生即 additive,完成。
- 若 A、B 被清掉(原生「替换式」)→ 执行 Step 5 的回退处理。

- [ ] **Step 5:(条件)additive 回退处理**

仅当 Step 4 发现原生会清空框外旧选择时:在框选手势开始时快照、只对 `onSelect` 真正回调到的项做增删、忽略原生的整批 `onSelect(false)`。具体:用一个 `@State boxSnapshot: Set<string> | null` 在 `onSelect` 首次回调时初始化为当前 `selectedIds` 快照,后续只把回调项叠加到快照;`PointerEvent`/框结束清空快照。(若 Step 4 表明不需要,跳过本步并在提交信息注明 native additive。)

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/pages/tabs/TabFiles.ets
git commit -m "feat(files): mouse box-selection via Grid multiSelectable"
```

---

## Task 4: 触屏命中测试工具(point → item id)

**Files:**
- Create: `entry/src/main/ets/utils/GridHitTest.ets`

- [ ] **Step 1: 实现命中测试**

```ts
import componentUtils from '@ohos.arkui.componentUtils';
import { UIContext } from '@ohos.arkui.UIContext';

export interface HitPoint {
  x: number
  y: number
}

// 在给定的一组(可见)item id 里,找窗口坐标 (x,y) 命中的那个 id;找不到返回 ''
export function hitTestItemId(point: HitPoint, ids: string[], ctx: UIContext): string {
  const utils = ctx.getComponentUtils()
  for (let i = 0; i < ids.length; i++) {
    const id = ids[i]
    if (id.length === 0) {
      continue
    }
    try {
      const info = utils.getRectangleById(id)
      // componentUtils 返回 px;GestureEvent.fingerList 的 globalX/Y 是 vp。统一转成 vp 比较。
      const ox = ctx.px2vp(info.windowOffset.x)
      const oy = ctx.px2vp(info.windowOffset.y)
      const w = ctx.px2vp(info.size.width)
      const h = ctx.px2vp(info.size.height)
      if (point.x >= ox && point.x <= ox + w && point.y >= oy && point.y <= oy + h) {
        return id
      }
    } catch (e) {
      // 该 id 当前不在树上(被滚出),跳过
    }
  }
  return ''
}
```

> 确认点:`getRectangleById` 返回的 `windowOffset`/`size` 字段名以 SDK 实际为准(本项目 SDK 6.1.0);若字段名不同(如 `screenOffset`),按真机/模拟器实测取能和 `PanGesture` 事件坐标对齐的那一组。**PanGesture 的 fingerList 坐标系要和这里取的 offset 坐标系一致**(都用 window 坐标)。

- [ ] **Step 2: 编译**

Run: 用户编译。Expected: BUILD SUCCESSFUL(此步无 UI 变化,仅确保新文件可编译)。

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/utils/GridHitTest.ets
git commit -m "feat(files): add grid point hit-test helper"
```

---

## Task 5: 触屏长按 + 拖动范围选择

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabFiles.ets`

- [ ] **Step 1: 加 controller、可见范围、import**

`TabFiles` 顶部 import:

```ts
import { DragSelectController } from '../../model/DragSelectModel';
import { hitTestItemId, HitPoint } from '../../utils/GridHitTest';
```

类内新增:

```ts
private dragSelect: DragSelectController = new DragSelectController()
private visibleFirst: number = 0
private visibleLast: number = 0
```

`Grid(...)` 上加可见范围跟踪:

```ts
.onScrollIndex((first: number, last: number) => {
  this.visibleFirst = first
  this.visibleLast = last
})
```

- [ ] **Step 2: 给 Grid 挂长按+拖动手势**

在 `Grid(...) { ... }` 链上加(仅多选模式有效,普通滑动仍滚动):

```ts
.gesture(
  GestureGroup(GestureMode.Sequence,
    LongPressGesture({ repeat: false })
      .onAction((event: GestureEvent) => {
        if (!this.isMultiSelectMode || event.fingerList.length === 0) {
          return
        }
        this.beginDragSelect(event.fingerList[0].globalX, event.fingerList[0].globalY)
      }),
    PanGesture()
      .onActionUpdate((event: GestureEvent) => {
        if (!this.dragSelect.isActive() || event.fingerList.length === 0) {
          return
        }
        this.updateDragSelect(event.fingerList[0].globalX, event.fingerList[0].globalY)
      })
      .onActionEnd(() => { this.dragSelect.end() })
      .onActionCancel(() => { this.dragSelect.end() })
  )
)
```

> 确认点:`fingerList[0].globalX/globalY` 是 window 坐标,与 `GridHitTest` 取的 `windowOffset` 同坐标系;若实测对不齐,换成同一坐标系的字段。`GestureGroup`/`GestureMode`/`LongPressGesture`/`PanGesture` 需确保已被 ArkUI 全局可用(无需 import)。

- [ ] **Step 3: 实现 begin / update**

```ts
private visibleIds(): string[] {
  // 只在当前可见范围内做命中(控制开销)。orderedIds 与可见下标对齐。
  const all = this.buildOrderedIds()
  const lo = Math.max(0, this.visibleFirst)
  const hi = Math.min(all.length - 1, this.visibleLast)
  const ids: string[] = []
  for (let i = lo; i <= hi; i++) {
    ids.push(all[i])
  }
  return ids
}

private beginDragSelect(x: number, y: number): void {
  const ordered = this.buildOrderedIds()
  const hitId = hitTestItemId({ x, y } as HitPoint, this.visibleIds(), this.getUIContext())
  if (hitId.length === 0) {
    return
  }
  const anchorIndex = ordered.indexOf(hitId)
  if (anchorIndex < 0) {
    return
  }
  this.dragSelect.begin(anchorIndex, ordered, this.selectedIds)
  // 锚点本身也纳入当前范围
  this.applySelection(this.dragSelect.dragTo(anchorIndex, ordered))
}

private updateDragSelect(x: number, y: number): void {
  const ordered = this.buildOrderedIds()
  const hitId = hitTestItemId({ x, y } as HitPoint, this.visibleIds(), this.getUIContext())
  if (hitId.length === 0) {
    return
  }
  const currentIndex = ordered.indexOf(hitId)
  if (currentIndex < 0) {
    return
  }
  this.applySelection(this.dragSelect.dragTo(currentIndex, ordered))
}
```

- [ ] **Step 4: 编译**

Run: 用户编译。Expected: BUILD SUCCESSFUL。

- [ ] **Step 5: 模拟器验证(phone / 5555)**

让用户在 5555 多选模式下:① 长按一个未选项往下拖 → 连续范围选中;② 往回拖 → 收缩;③ 已有选择保留;④ 长按一个已选项拖 → 取消范围;⑤ 普通滑动(不长按)仍正常滚动列表。
> 此时尚未做边缘自动滚动(Task 6),拖到屏幕外暂不滚属正常。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/pages/tabs/TabFiles.ets
git commit -m "feat(files): touch long-press drag range-selection"
```

---

## Task 6: 拖到边缘自动滚动

**Files:**
- Modify: `entry/src/main/ets/pages/tabs/TabFiles.ets`

- [ ] **Step 1: 给 Grid 设固定 id,并实现列表上下边界(vp)**

`Grid(...)` 上加 `.id('fileGrid')`。类内新增(都转成 vp,和手势 fingerList 的 vp 坐标一致):

```ts
private dragListTop(): number {
  try {
    const ctx = this.getUIContext()
    return ctx.px2vp(ctx.getComponentUtils().getRectangleById('fileGrid').windowOffset.y)
  } catch (e) {
    return 0
  }
}

private dragListBottom(): number {
  try {
    const ctx = this.getUIContext()
    const r = ctx.getComponentUtils().getRectangleById('fileGrid')
    return ctx.px2vp(r.windowOffset.y + r.size.height)
  } catch (e) {
    return 0
  }
}
```

- [ ] **Step 2: 加自动滚动状态 + 逻辑**

类内新增字段:

```ts
private autoScrollTimer: number = -1
private lastDragX: number = 0
private lastDragY: number = 0
```

新增方法:

```ts
// 纯命中(不触发自动滚动,避免递归)
private updateDragSelectHit(x: number, y: number): void {
  const ordered = this.buildOrderedIds()
  const hitId = hitTestItemId({ x, y } as HitPoint, this.visibleIds(), this.getUIContext())
  if (hitId.length === 0) {
    return
  }
  const idx = ordered.indexOf(hitId)
  if (idx < 0) {
    return
  }
  this.applySelection(this.dragSelect.dragTo(idx, ordered))
}

private stopAutoScroll(): void {
  if (this.autoScrollTimer >= 0) {
    clearInterval(this.autoScrollTimer)
    this.autoScrollTimer = -1
  }
}

private startAutoScroll(stepVp: number): void {
  this.stopAutoScroll()
  this.autoScrollTimer = setInterval(() => {
    this.scrollerForList.scrollBy(0, stepVp)
    this.updateDragSelectHit(this.lastDragX, this.lastDragY)
  }, 60)
}

private maybeAutoScroll(y: number): void {
  const EDGE = CloudThemeToken.iconBoxSm     // 边缘阈值(vp,约半行高,可调)
  const STEP = CloudThemeToken.spacingPage   // 每次滚动步长(vp,可调)
  const top = this.dragListTop()
  const bottom = this.dragListBottom()
  if (bottom <= top) {
    return
  }
  if (y < top + EDGE) {
    this.startAutoScroll(-STEP)
  } else if (y > bottom - EDGE) {
    this.startAutoScroll(STEP)
  } else {
    this.stopAutoScroll()
  }
}
```

- [ ] **Step 3: 把拖动 update 接上自动滚动**

将 Task 5 的 `updateDragSelect` 改为:

```ts
private updateDragSelect(x: number, y: number): void {
  this.lastDragX = x
  this.lastDragY = y
  this.updateDragSelectHit(x, y)
  this.maybeAutoScroll(y)
}
```

手势 `onActionEnd` / `onActionCancel` 里追加 `this.stopAutoScroll()`。

- [ ] **Step 4: 编译**

Run: 用户编译。Expected: BUILD SUCCESSFUL。

- [ ] **Step 5: 模拟器验证(5555)**

多选模式下长按拖到列表上/下边缘 → 列表自动滚动,且滚动过程中范围持续扩展;松手停止滚动。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/pages/tabs/TabFiles.ets
git commit -m "feat(files): auto-scroll near edges during touch drag-select"
```

---

## Task 7: 收尾回归 + 三机验证

**Files:** 无新增改动(验证为主)

- [ ] **Step 1: 三机安装**

让用户编译后装到 5555 / 5557 / 5559。

- [ ] **Step 2: 完整回归清单(用户执行)**

- 触屏(5555):长按拖选范围 / 往回撤销 / 保留已有 / 长按已选项取消 / 普通滑动仍滚动 / 边缘自动滚动。
- 鼠标(5557):拉框 additive / 未进多选自动进入 / 新框不清空旧选(Task 3 spike 结论)。
- 通用:单击切换、进入/退出多选、左滑删除、右键菜单、批量操作不受影响。

- [ ] **Step 3: (按需)记忆与文档**

如交互最终确定,可在 `docs/superpowers/specs/2026-06-13-file-grid-drag-select-design.md` 末尾补一行「已实现」并记录 spike 结论(原生 multiSelectable 是否 additive、坐标系字段名),方便后人。

---

## 实现期需现场确认的点(汇总,均已在对应 Task 标注)

1. `TabFiles` 里持有 `dirObjects`/`fileObjects` 的字段名(Task 2)。
2. 原生 `multiSelectable` 的 `onSelect` 是否「替换式」清空框外旧选(Task 3 Step 4 spike;若是,走 Step 5 回退)。
3. `componentUtils.getRectangleById` 的偏移字段名,以及与 `GestureEvent.fingerList` 坐标系的一致性(Task 4 / Task 5)。
4. Grid 容器矩形用于边缘判断,以及 `Scroller.scrollBy` 的步长单位(vp/px)(Task 6)。
