import { ObjectDetail } from "./net/ApiTypes"

export class DetailData {
  name: string
  isDir: boolean
  detailInfo: ObjectDetail

  constructor(name: string, isDir: boolean, detailInfo: ObjectDetail) {
    this.name = name
    this.isDir = isDir
    this.detailInfo = detailInfo
  }
}