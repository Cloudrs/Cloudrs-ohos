import { CloudThemeToken } from '../model/CloudTheme';

export type PhotoThumbnailListener = (pixelMap: PixelMap) => void;

/**
 * 相册缩略图缓存。
 *
 * 缩略图加载完成后只通知正在展示同一图片的格子，避免通过 @Provide Map
 * 触发整个虚拟列表重建。Map 的迭代顺序用作 LRU 淘汰顺序。
 */
export class PhotoThumbnailStore {
  private static data: Map<string, PixelMap> = new Map<string, PixelMap>();
  private static listeners: Map<string, PhotoThumbnailListener[]> =
    new Map<string, PhotoThumbnailListener[]>();

  static has(id: string): boolean {
    return PhotoThumbnailStore.data.has(id);
  }

  static get(id: string): PixelMap | undefined {
    const pixelMap = PhotoThumbnailStore.data.get(id);
    if (!pixelMap) {
      return undefined;
    }
    PhotoThumbnailStore.data.delete(id);
    PhotoThumbnailStore.data.set(id, pixelMap);
    return pixelMap;
  }

  static set(id: string, pixelMap: PixelMap): void {
    PhotoThumbnailStore.data.delete(id);
    PhotoThumbnailStore.data.set(id, pixelMap);
    while (PhotoThumbnailStore.data.size > CloudThemeToken.photoBackupThumbnailCacheLimit) {
      const oldestKey = PhotoThumbnailStore.data.keys().next().value as string | undefined;
      if (!oldestKey) {
        break;
      }
      PhotoThumbnailStore.data.delete(oldestKey);
    }

    const currentListeners = PhotoThumbnailStore.listeners.get(id);
    if (currentListeners) {
      currentListeners.slice().forEach((listener: PhotoThumbnailListener) => {
        listener(pixelMap);
      });
    }
  }

  static subscribe(id: string, listener: PhotoThumbnailListener): void {
    const currentListeners = PhotoThumbnailStore.listeners.get(id);
    if (!currentListeners) {
      PhotoThumbnailStore.listeners.set(id, [listener]);
      return;
    }
    if (currentListeners.indexOf(listener) < 0) {
      currentListeners.push(listener);
    }
  }

  static unsubscribe(id: string, listener: PhotoThumbnailListener): void {
    const currentListeners = PhotoThumbnailStore.listeners.get(id);
    if (!currentListeners) {
      return;
    }
    const index = currentListeners.indexOf(listener);
    if (index >= 0) {
      currentListeners.splice(index, 1);
    }
    if (currentListeners.length === 0) {
      PhotoThumbnailStore.listeners.delete(id);
    }
  }
}
