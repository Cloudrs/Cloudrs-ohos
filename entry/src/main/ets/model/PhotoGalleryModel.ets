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
