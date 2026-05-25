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
