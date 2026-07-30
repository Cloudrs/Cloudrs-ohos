import { PhotoBackupStatus, PhotoBackupItem } from './PhotoBackupModel';

export enum GallerySegment { TIME = 0, ALBUM = 1 }

export enum PhotoBadge { NONE = 'none', CLOUD = 'cloud', UPLOADING = 'uploading', FAILED = 'failed' }

/** Badge rule: completed always shows cloud; uploading/failed only when backup enabled; waiting/others show nothing */
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
  if (d.getFullYear() !== today.getFullYear()) {
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
  }
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

/** Group by date, preserving input order (caller already sorts by modifiedAt desc) */
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

/** Group by album name, preserving first-seen order */
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
 * Slice a list of aspect ratios into equal-height justified rows.
 * @param ratios width/height per image (>0)
 * @param containerWidth available width
 * @param targetHeight target row height
 * @param gap inter-image gap
 */
export function justifyRows(ratios: number[], containerWidth: number, targetHeight: number, gap: number): JustifiedRow[] {
  const rows: JustifiedRow[] = [];
  let current: number[] = [];
  let start = 0;

  const flushRow = (currentBatch: number[], batchStart: number, isLast: boolean): number => {
    if (currentBatch.length === 0) {
      return batchStart;
    }
    const sumRatio = currentBatch.reduce((s: number, r: number) => s + r, 0);
    const totalGap = gap * (currentBatch.length - 1);
    let rowHeight = (containerWidth - totalGap) / sumRatio;
    if (isLast && rowHeight > targetHeight) {
      rowHeight = targetHeight;
    }
    const widths = currentBatch.map((r: number) => r * rowHeight);
    rows.push(new JustifiedRow(rowHeight, widths, batchStart));
    return batchStart + currentBatch.length;
  };

  ratios.forEach((ratio: number) => {
    current.push(ratio > 0 ? ratio : 1);
    const sumRatio = current.reduce((s: number, r: number) => s + r, 0);
    const totalGap = gap * (current.length - 1);
    const projectedHeight = (containerWidth - totalGap) / sumRatio;
    if (projectedHeight <= targetHeight) {
      start = flushRow(current, start, false);
      current = [];
    }
  });
  flushRow(current, start, true);
  return rows;
}

/** Clamped aspect ratio (width/height) for an item; 1 when dimensions are missing. */
export function ratioForItem(item: PhotoBackupItem): number {
  if (item.width > 0 && item.height > 0) {
    const r = item.width / item.height;
    const screenshotKey = `${item.albumName}/${item.name}`.toLowerCase();
    const isScreenshot = screenshotKey.includes('screenshot') ||
      screenshotKey.includes('截屏') || screenshotKey.includes('截图');
    if (isScreenshot) {
      // 手机截图通常接近 0.45，按真实比例展示会在宽屏相册里过窄。
      // 仅提高截图类竖图的展示宽度，ImageFit.Cover 会做少量纵向裁剪；
      // 普通照片仍保持原有 0.5 下限和布局密度。
      return Math.min(Math.max(r, 0.9), 2.0);
    }
    return Math.min(Math.max(r, 0.5), 2.0);
  }
  return 1;
}

/** A flat render row consumed by the gallery's LazyForEach: either a section header or a row of photo cells. */
export enum GalleryRowKind { HEADER = 0, PHOTOS = 1 }

export class GalleryCell {
  item: PhotoBackupItem;
  width: number;
  height: number;

  constructor(item: PhotoBackupItem, width: number, height: number) {
    this.item = item;
    this.width = width;
    this.height = height;
  }
}

export class GalleryRenderRow {
  kind: GalleryRowKind;
  key: string;
  title: string;
  count: number;
  collapsed: boolean;
  height: number;
  cells: GalleryCell[];

  constructor(kind: GalleryRowKind, key: string, title: string, count: number,
    collapsed: boolean, height: number, cells: GalleryCell[]) {
    this.kind = kind;
    this.key = key;
    this.title = title;
    this.count = count;
    this.collapsed = collapsed;
    this.height = height;
    this.cells = cells;
  }
}

/**
 * Flatten grouped photos into a single ordered list of render rows
 * (one header row per group, followed by its justified photo rows).
 * Collapsed groups (by title) emit only their header. Keys encode the group
 * title so LazyForEach diffs correctly when the grouping dimension changes.
 * Computed once per data/width/collapse change so LazyForEach can virtualize it.
 */
export function buildRenderRows(groups: PhotoGroup[], containerWidth: number,
  targetHeight: number, gap: number, collapsed: Set<string>): GalleryRenderRow[] {
  const result: GalleryRenderRow[] = [];
  groups.forEach((group: PhotoGroup) => {
    const isCollapsed = collapsed.has(group.title);
    result.push(new GalleryRenderRow(GalleryRowKind.HEADER, `h:${group.title}:${group.items.length}:${isCollapsed ? 1 : 0}`,
      group.title, group.items.length, isCollapsed, 0, []));
    if (isCollapsed) {
      return;
    }
    const ratios = group.items.map((it: PhotoBackupItem) => ratioForItem(it));
    const jrows = justifyRows(ratios, containerWidth, targetHeight, gap);
    jrows.forEach((jr: JustifiedRow, jrIndex: number) => {
      const cells: GalleryCell[] = jr.widths.map((w: number, i: number) =>
        new GalleryCell(group.items[jr.startIndex + i], w, jr.height));
      // Key 必须反映整行内容：每个格子的 id + 本地/云端状态。
      // 之前只用首图 id：删图后尾部格子前移、但首图未变的行 key 不变，LazyForEach 复用旧行
      //（旧缩略图与旧点击闭包），导致点进去是另一张，必须重启重建网格才正常。
      const rowKey = cells.length > 0
        ? cells.map((c: GalleryCell) => `${c.item.id}:${c.item.localExists ? 1 : 0}:${c.item.status}`).join(',')
        : 'empty';
      result.push(new GalleryRenderRow(GalleryRowKind.PHOTOS, `p:${group.title}:${jrIndex}:${rowKey}`,
        '', 0, false, jr.height, cells));
    });
  });
  return result;
}
