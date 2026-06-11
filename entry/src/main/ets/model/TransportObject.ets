import { FileModelState } from "./FileModel";
import { ObjectInfo } from "./net/ApiTypes";
import Constant from "./Constant";

export enum TransportType {
  DOWNLOAD,
  UPLOAD,
  BACKUP,
  SYNC
}

@ObservedV2
export class TransportObject {
  type: TransportType = TransportType.DOWNLOAD;
  id: string = '';
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

  constructor(item: ObjectInfo, path: string, url: string, id?: string) {
    this.item = item;
    this.path = path;
    this.url = url;
    this.total = item.size
    this.id = id ?? item.id
  }

  update(trans: number, state: FileModelState)
  {
    let biosTime = new Date().getTime() - this.lastTime;
    let biosBytes = trans - this.trans;
    if (biosTime > 0 && biosBytes >= 0) {
      this.speed = biosBytes / biosTime * Constant.MILLISECONDS_PER_SECOND;
    } else {
      this.speed = 0;
    }
    let newTrans = trans
    this.trans = newTrans;
    this.progress = this.total > 0 ?
      Math.min(Constant.BACKGROUND_TASK_COMPLETE_PERCENT,
        Math.floor(trans / this.total * Constant.BACKGROUND_TASK_COMPLETE_PERCENT)) : 0;
    let newState = state;
    this.state = newState;
    this.lastTime = this.lastTime+biosTime;
  }
}
