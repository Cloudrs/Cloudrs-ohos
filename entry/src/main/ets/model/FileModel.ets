export enum FileModelState {
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

type progressCallback = (trans: number, state: FileModelState) => void

export class FileModel {
  id: string;
  path: string;
  url: string;
  fileType?: string;
  callback?: progressCallback
  // 下载直链是短时效签名链接；任务在等待队列里排队后真正启动时，
  // 通过它换取新直链，避免用入队时拿的过期链接
  refreshUrl?: () => Promise<string>

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