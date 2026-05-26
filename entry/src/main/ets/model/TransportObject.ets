import { FileModelState } from "./FileModel";
import { ObjectInfo } from "./net/ApiTypes";

export enum TransportType {
  DOWNLOAD,
  UPLOAD,
  BACKUP,
  SYNC
}

@ObservedV2
export class TransportObject {
  type: TransportType = TransportType.DOWNLOAD;
  item: ObjectInfo;
  path: string = '';
  url: string = '';
  @Trace trans: number = 0;
  total: number = 0;
  @Trace progress: number = 0;
  @Trace speed: number = 0;
  @Trace state: FileModelState = FileModelState.INITIALIZED;
  @Trace statusText: string = '';
  private lastTime: number = new Date().getTime();

  constructor(item: ObjectInfo, path: string, url: string) {
    this.item = item;
    this.path = path;
    this.url = url;
    this.total = item.size
  }

  update(trans: number, state: FileModelState)
  {
    let biosTime = new Date().getTime() - this.lastTime;
    let biosBytes = trans - this.trans;
    if (biosTime > 0 && biosBytes >= 0) {
      this.speed = biosBytes / biosTime * 1000;
    } else {
      this.speed = 0;
    }
    let newTrans = trans
    this.trans = newTrans;
    this.progress = this.total > 0 ? Math.min(100, Math.floor(trans / this.total * 100)) : 0;
    let newState = state;
    this.state = newState;
    this.lastTime = this.lastTime+biosTime;
  }
}
