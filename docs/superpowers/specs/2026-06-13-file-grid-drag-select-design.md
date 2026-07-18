# 文件多选 — 触屏长按拖动选择 + 鼠标框选

> 日期: 2026-06-13
> 状态: 已实现 —— 触屏拖选部分取消(见下「实现结果」),鼠标框选按设计落地

## 实现结果(2026-06-13 更新)

实现期间,**触屏长按拖动选择被取消**:文件列表在 `HdsTabs` 容器内,向左右拖会切 tab、向下拖会触发下拉刷新,容器的滑动手势优先级高于自定义 `PanGesture`,无法稳定让拖选手势胜出(SDK 也未提供禁用 HdsTabs 滑动的开关)。多次尝试(`priorityGesture`、长按串 Pan、条件 `responseType`)均无法兼顾。

最终落地方案:

- **鼠标 / 2in1:** 保留 `Grid.multiSelectable(true)` 原生框选(走系统命中,不参与手势仲裁,工作正常)。
- **触屏:** 改为「点选切换」+ 多选标题栏右上角两个按钮 —— 「全选 / 取消全选」(图标随状态切换 `sys.symbol.checkmark_square_on_square` / `_fill`)与「取消」(`sys.symbol.xmark`)。不再做长按拖选。
- **底部操作栏:** 多选底部操作栏(复制/移动/下载/删除)测量真实高度(`onAreaChange → multiSelectBarHeight`)抬高列表底部占位,避免遮住末尾项;手机端多选时 FAB 下移到安全区、藏到操作栏之后;操作按钮去掉默认灰底(`stateEffect:false` + `hoverEffect:None`),改用轻量按压反馈(`stateStyles` 缩放+变淡)。
- **删除确认:** 多个项目时只显示「将删除 N 个项目」,不逐行列文件名。

下方为原始设计存档(触屏拖选部分未采用)。

## 目标

在文件页(`TabFiles`)的多选模式下,新增两种连续多选方式,减少逐个点选的操作量:

- **触屏:** 长按某个文件项后拖动,连续选中(或取消)手指经过的范围。
- **鼠标(PC / 2in1 模式):** 拖出一个选择框,框住的文件项自动选中。

两种方式都是 **additive(累加)**:不会清空已有选择,只在划过/框住的范围上做加减;并且在单次手势内可反向撤销。

## 当前实现(背景)

- 文件列表是一个 `Grid(this.scrollerForList)`,内部两段 `LazyForEach`:先目录 `dirDataSource`,再文件 `fileDataSource`,每项用 `GridItem() { ObjectItem({...}) }` 包裹。
- 多选状态:`@State isMultiSelectMode: boolean`、`@State selectedObjects: ObjectInfo[]`。
- 进入多选:`enterMultiSelectMode()`(目前由菜单按钮触发,`TabFiles.ets:2737`);`exitMultiSelectMode()` 退出。
- 点击:`GridItem().onClick(() => this.onItemClick(item))` —— 多选模式下切换选中,否则打开。
- `ObjectItem` 有 `@Prop selected: boolean` / `@Prop multiSelectMode: boolean`,用 `itemStyle(selected)` 渲染选中高亮。
- 目前**没有任何长按手势 / `multiSelectable` / 拖动选择**,这是全新增量。

## 设计

### 1. 统一的线性顺序与选择模型

为支持「锚点 → 当前项」的范围选择,需要一个跨 目录+文件 的**统一线性序**:

- 线性序 = `dirDataSource` 全部(按显示顺序)在前,接 `fileDataSource` 全部(按显示顺序)。
- 提供工具:
  - `linearIndexOf(item): number` —— 返回某项在统一序中的下标(目录段 `[0, dirCount)`,文件段 `[dirCount, dirCount+fileCount)`)。
  - `itemAtLinearIndex(idx): ObjectInfo` —— 反查。
  - `isSelected(item): boolean` —— 用 id 判断是否已选(`selectedObjects` 建议配一个 `Set<string>` 的 id 索引,避免数组线性查找)。

选中集合维持现有的 `selectedObjects: ObjectInfo[]`(对外不变),内部增加一个 `selectedIds: Set<string>` 做 O(1) 命中判断与增删,二者同步。

### 2. 触屏:长按 + 拖动范围选择

手势:在 Grid 容器上挂 `LongPressGesture`(触发进入拖选)串 `PanGesture`(拖动),仅在 `isMultiSelectMode` 下生效。普通滑动(未长按)仍然走 Grid 自身滚动,互不干扰。

一次拖选手势的状态:

- **手势开始(长按命中锚点项)时记录:**
  - `anchorIndex` = 锚点项的线性下标。
  - `dragMode` = 锚点项当前**未选** → `SELECT`;锚点项当前**已选** → `DESELECT`。
  - `baseSelectedIds` = 当前 `selectedIds` 的快照(手势前的选择)。
- **拖动移动时:**
  - 命中当前手指所在项 → `currentIndex`。
  - 范围 `[min(anchorIndex,currentIndex), max(...)]`。
  - 重新计算选择 = `baseSelectedIds` 的副本,然后对范围内每一项按 `dragMode` 置位(SELECT→加入 / DESELECT→移除)。范围外的项保持 `baseSelectedIds` 中的状态。
  - 这样:① 已有选择被保留;② 范围内统一变为目标态;③ 往回拖、项离开范围时自动回到手势前状态(可逆)。
- **手势结束:** 提交,清空临时状态。

**命中测试(手指坐标 → 哪个项,本设计的主要难点):**

- 用 `componentUtils.getRectangleById(id)` 对当前**可见**的 GridItem 逐个取屏幕矩形,找包含手指点的那个。需要给每个 GridItem 设稳定的 `.id(item.id)`。
- 可见范围用 `Grid.onScrollIndex((first, last) => ...)` 跟踪,只对可见项做命中,控制开销。
- **边缘自动滚动:** 手指接近列表顶部/底部一定阈值时,用 `scrollerForList.scrollBy/scrollPage` 持续滚动,滚动中继续命中测试,实现「拖到边缘自动翻」。
- 兼容两种 `showType`(网格视图 / 列表视图,列数不同):命中测试基于实际矩形,天然适配;线性序与列数无关。

### 3. 鼠标:原生框选

- `Grid.multiSelectable(true)` 开启鼠标框选。
- 每个 `GridItem.selectable(true).selected(this.isSelected(item)).onSelect((isSel) => this.onBoxSelect(item, isSel))`。
- `onBoxSelect`:
  - 若当前不在多选模式,首次框选到项时自动 `enterMultiSelectMode()`(画框即明确的选择意图)。
  - `isSel === true` → 加入选择;`isSel === false` → 移出选择。
  - **保留已有选择:** 目标是 additive。需在实现时验证原生 `multiSelectable` 的 `onSelect` 行为 —— 若原生在开始新框时会对框外已选项触发 `onSelect(false)`(即「替换式」),则改为自己管理:框选开始时快照已有选择,只对框交互到的项做增删,不因新框清空框外旧选择。**此点为实现期需实测确认的风险点,附带回退方案(必要时纯靠 onSelect 增删、不依赖原生清空语义)。**

### 4. 与现有交互的关系

- 单击(`onClick → onItemClick`)切换单项:保持不变。
- 长按拖选 与 单击:长按是新增,触发阈值由 `LongPressGesture` 控制,短按仍是 click,不冲突。
- 鼠标框选 与 单击:点击 vs 拖拽由系统区分,可共存。
- 退出多选(`exitMultiSelectMode`)后,两种拖选都不生效。

## 受影响的文件/单元

- `pages/tabs/TabFiles.ets`
  - `objectGrid()`:Grid 加 `multiSelectable(true)`、`onScrollIndex`;GridItem 加 `.id()`、`.selectable().selected().onSelect()`、长按+Pan 手势(挂在 Grid 容器)。
  - 新增:`selectedIds: Set<string>` 及与 `selectedObjects` 的同步;`linearIndexOf` / `itemAtLinearIndex` / `isSelected`;拖选手势状态与处理方法;`onBoxSelect`;边缘自动滚动。
- `components/ObjectItem.ets`:基本不变(已有 `selected` 渲染);如需可加选中态过渡动画(可选,非必须)。

> 命中测试 + 边缘滚动的逻辑建议抽到一个独立的小工具/辅助方法集合(例如 `utils/GridDragSelect`),让 `TabFiles` 只持有状态、调用接口,便于单独理解与调试。`TabFiles.ets` 已经很大,新增逻辑尽量内聚成可独立测试的单元。

## 边界情况

- 空目录 / 仅目录 / 仅文件:线性序长度相应变化,范围计算照常。
- 拖动中数据刷新(LazyForEach 变更):以手势开始时的快照与当前可见项命中为准;数据大改时结束当前手势更稳妥。
- 锚点项在拖动中被滚出可见区:范围按线性下标计算,不依赖锚点仍可见;命中只用于确定 `currentIndex`。
- 网格/列表视图切换:手势进行中不切换;切换后按新布局重新命中。

## 验证方式

- 触屏(5555 phone 模拟器):多选模式下长按某项拖动,确认连续范围选中、往回拖撤销、边缘自动滚动、已有选择保留;长按已选项拖动 = 取消范围。
- 鼠标(5557 2in1 模拟器):拖框选中框内项;未进多选时拉框自动进入多选;新框不清空已有选择。
- 回归:单击切换、进入/退出多选、左滑删除、右键菜单不受影响。

## 不做(YAGNI)

- 不做「框选时按住 Ctrl 加选 / 不按为替换」等桌面修饰键语义 —— 多选模式下统一 additive。
- 不做跨目录/跨页选择持久化。
- 不改多选模式的进入方式(仍用现有菜单按钮;长按拖选只在已进入多选时生效,不额外做「长按进入多选」—— 如后续需要可再加)。
- 不引入选择框的自定义视觉(沿用系统 `multiSelectable` 框样式)。
