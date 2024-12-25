
export enum DownloadState {
  INITIALIZED,
  WAITING,
  RUNNING,
  RETRYING,
  PAUSED,
  STOPPED,
  COMPLETED,
  FAILED,
  REMOVED
}

type progressCallback = (trans: number, state: DownloadState) => void

export class DownloadFileModel {
  id: string;
  path: string;
  url: string;
  fileType?: string;
  callback?: progressCallback

  constructor(id: string, path: string, url: string, fileType?: string, callback?: progressCallback) {
    this.id = id;
    this.path = path;
    this.url = url;
    if (fileType) {
      this.fileType = fileType;
    }
    if (callback) {
      this.callback = callback
    }
  }
}