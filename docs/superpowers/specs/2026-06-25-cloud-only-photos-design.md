# 本地 + 云端统一相册（仅云端图显示与预览）设计文档

- 日期：2026-06-25
- 状态：待实现（设计待用户审阅）
- 关联代码：`model/PhotoBackupModel.ets`、`pages/tabs/TabPictures.ets`、`components/PhotoGalleryGrid.ets`、`pages/ImagePreview.ets`、`pages/PhotoLocalPreview.ets`、`model/net/CloudApi.ets`

## 1. 背景与目标

相册页现在只反映本地相册。本地删除一张**已备份到云**的图后，下拉刷新会把它移除，之后就看不到了。

目标：**已备份到云端的图，本地删了也保留在相册页（标"云端"记号），点开用网盘那份预览**；本地未备份的图删了仍然移除。

## 2. 现状要点（已查证）

- 备份上传到 `设置.remotePath` 下、用原文件名（`backupItem` → `getRemoteFilePath`）。
- 云端列目录：`CloudApi.getFilesInfo(remotePath)` → `DirectoryInfo.objects: ObjectInfo[]`，每项含 **`id`（云端文件 ID）+ `name`**。`loadRemotePhotoNameCache` 已用它（只取了 name）。
- 云端缩略图：`CloudApi.getThumb(fileId)`。
- 云端图预览：`ImagePreview` 页用 `CloudApi.getDownloadUri(fileId)` 加载网络图。
- 本地图预览：`PhotoLocalPreview` 页用本地 `uri`。
- `PhotoBackupItem`：`id/uri/name/size/modifiedAt/status/...`，**无本地存在标记、无云端 ID**。

## 3. 数据模型

`PhotoBackupItem` 新增两个字段（含 `toData`/`fromData` 持久化、向后兼容默认值）：

- `localExists: boolean = true` —— 本地媒体库是否还有这张图。
- `remoteFileId: string = ''` —— 云端文件 ID（仅云端图预览/缩略图用）。

## 4. 云端文件 ID 的获取方式

**方案 A（采用）**：全量扫描 / 下拉刷新时，调一次 `getFilesInfo(remotePath)` 拿云端目录（`Map<name, ObjectInfo>`），给仅云端图按 `name` 匹配填 `remoteFileId`。复用 / 扩展 `loadRemotePhotoNameCache` 为 `loadRemotePhotoMap`（返回 name→ObjectInfo）。**不改备份流程**。

方案 B（不采用）：备份时记录 `remoteFileId` —— 要改 `backupItem` + 迁移旧记录，且旧已备份记录没有 ID。

## 5. 扫描 / 合并逻辑（全量扫描 / 下拉刷新）

`scanLocalPhotos(forceFull=true)` 内（`mergePhotoList` 调整）：

1. `nextPhotos` = 本地实际扫到的图 → `localExists = true`。
2. 加载云端目录 map：`loadRemotePhotoMap(remotePath)`（`name → ObjectInfo`）。
3. 对持久化记录里**本地扫不到**的图：
   - 若 `status === COMPLETED`（已备份）**且** 云端 map 含其 `name` → 标 `localExists = false`、`remoteFileId = 云端 id`，**保留**（仅云端）。
   - 否则（本地无 + 未备份，或云端也没有）→ **移除**。
4. 增量扫描（registerChange 触发）只处理新增，不动 `localExists`（删除/仅云端的判定只在全量扫描/下拉刷新做，避免每次查云端目录）。

## 6. 预览分流（`openLocalPreview`）

- `localExists === true` → `PhotoLocalPreview`（本地，现状不变）。
- `localExists === false` → `ImagePreview`（`{ fileName: item.name, fileId: item.remoteFileId, fileExtension }`，走网盘下载预览）。

## 7. 缩略图分流（`loadPhotoThumbnail` / `PhotoGalleryGrid`）

- `localExists === true` → 本地 `asset.getThumbnail`（现状）。
- `localExists === false` → `CloudApi.getThumb(item.remoteFileId)` 取云端缩略图，存入 `photoBackupThumbs`（与本地缩略图同一展示通道）。
  - 实现时确认 `getThumb` 回调返回的是 url 还是数据；`PhotoGalleryGrid.photoCell` 已按 `photoBackupThumbs.has(item.id)` 显示，统一成 PixelMap 即可复用。

## 8. 角标

仅云端图（`localExists === false`）在网格上显示一个**"仅云端"角标**以区分。`PhotoGalleryGrid` 的 badge 体系已有 `CLOUD`（已备份云图标）；为"仅云端"用一个可区分的记号（如带斜杠的云 / 不同色），具体图标实现时定。

## 9. 边界与约束

- **删仅云端图**：本次不支持在相册页删除仅云端图（那等于删云端备份）。YAGNI，先只做显示 + 预览。
- **备份开关关闭**：相册页本就 `enabled` 时才扫描/显示；仅云端图同理。
- **remotePath 变更**：仅云端图依赖当前 `remotePath` 在云端定位；若用户改了备份路径，旧仅云端图在新路径查不到 → 该图缩略图/预览失败，下拉刷新时按"云端也没有"移除。
- **云端目录大**：`getFilesInfo` 列整个备份目录；目录文件多时一次列举有开销，但仅在全量扫描/下拉刷新触发，可接受。

## 10. 测试

- 单元（ohosTest）：`mergePhotoList` 的本地存在 / 仅云端 / 移除三分支判定（构造本地集合 + 云端 name 集合 + 持久化记录）。
- 手动：备份一张图 → 本地删除 → 下拉刷新 → 该图保留、带"仅云端"角标、显示云端缩略图、点开走网盘预览；未备份图本地删除 → 下拉刷新移除。

## 11. 切换备份路径后的刷新

`getDoneKey` 含路径（`${remotePath}|${id}`），所以换路径后旧"已备份"标记逻辑上自动失效。但当前 `onSettingsRevisionChanged → loadSettings` **只更新路径、没重判标记**，导致小云朵残留旧状态。

修复：**检测到 `remotePath` 变化时**，调 `refreshDoneStatus()`（按新路径重判已备份标记）+ 触发一次全量刷新（重新按新路径关联云端：仅云端图按新路径在云端查；新路径查不到的仅云端图移除）。本地图本身不需重扫（与路径无关）。

## 12. 实时删除处理（registerChange `NOTIFY_REMOVE`）

**已真机确诊**：删除事件 `type === NotifyType.NOTIFY_REMOVE`（值 2），`changeData.uris` 为被删图的 uri，格式 `file://media/Photo/.../<name>`，**与本地图 `item.uri` 同格式可直接匹配**。

`onMediaLibraryChange` 收到 `NOTIFY_REMOVE` 时，对每个被删 uri：

1. 在 `photos` 里按 `uri` 找到对应 item。
2. **已备份**（`isPhotoDone` / `status === COMPLETED`）→ 转"仅云端"：`localExists = false`，按需查云端填 `remoteFileId`，**保留**（缩略图换云端、小云朵保留、预览走云端）。
3. **未备份** → 从 `photos` 移除（缩略图与记录都删）。
4. `refreshPhotoStats()` + `rebuildGroups()` 刷新界面。

**关键修复（之前没生效的根因）**：删除处理**不受 `isActive` 限制**——删除事件常在 App 切到系统相册（后台）时触发，不能在入口 `if (!isActive) return` 处挡掉；处理后回到前台保证界面已更新。**下拉刷新（全量）作为兜底**，万一某次实时事件丢失，下拉一次即对齐。

## 13. 不做（YAGNI）

- 在相册页删除仅云端图 / 删云端备份。
- 备份时记录 `remoteFileId`（用刷新时查云端目录代替）。
- 仅云端图的多选 / 批量操作。
