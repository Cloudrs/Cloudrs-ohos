import { ObjectDetail } from "./net/ApiTypes"

export class DetailData {
  name: string
  isDir: boolean
  /** 所在目录。搜索结果是跨目录的，光看文件名分不清是哪一个 */
  parentPath: string
  detailInfo: ObjectDetail

  constructor(name: string, isDir: boolean, parentPath: string, detailInfo: ObjectDetail) {
    this.name = name
    this.isDir = isDir
    this.parentPath = parentPath
    this.detailInfo = detailInfo
  }
}
