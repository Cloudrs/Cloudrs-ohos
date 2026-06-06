
import { ObjectInfo } from "./net/ApiTypes"
import { CommonUtil } from "../utils/CommonUtil"
import { FileMenuType, ShowType } from "./MenuModel"

export class PreviewFile {
  fileName: string = ''
  fileId: string = ''
  fileExtension: string = ''

  constructor(fileName: string, fileId: string, fileExtension?: string) {
    this.fileName = fileName
    this.fileId = fileId
    this.fileExtension = fileExtension ?? CommonUtil.getFileExtention(fileName)
  }
}

export class ImagePreview {
  fileName: string = ''
  fileId: string = ''
  fileExtension: string = ''
  previewFiles: PreviewFile[] = []
  currentIndex: number = 0

  constructor(fileName: string, fileId: string, fileExtension: string, previewFiles?: PreviewFile[], currentIndex?: number) {
    this.fileName = fileName
    this.fileId = fileId
    this.fileExtension = fileExtension
    this.previewFiles = previewFiles ?? [new PreviewFile(fileName, fileId, fileExtension)]
    this.currentIndex = currentIndex ?? 0
  }
}

export class VideoPreview {
  fileName: string = ''
  fileId: string = ''
  fileExtension: string = ''

  constructor(fileName: string, fileId: string, fileExtension: string) {
    this.fileName = fileName
    this.fileId = fileId
    this.fileExtension = fileExtension
  }
}

export class FileSearchParam {
  currentPath: string = '/'
  objects: ObjectInfo[] = []
  showType: ShowType = ShowType.SHOW_LIST
  thumbImage?: Map<string, PixelMap>
  thumbSource?: Map<string, string>
  onOpen?: (item: ObjectInfo) => void
  onMenuClick?: (item: ObjectInfo, type: FileMenuType) => void

  constructor(currentPath?: string, objects?: ObjectInfo[],
    onOpen?: (item: ObjectInfo) => void,
    onMenuClick?: (item: ObjectInfo, type: FileMenuType) => void,
    showType?: ShowType,
    thumbImage?: Map<string, PixelMap>,
    thumbSource?: Map<string, string>) {
    this.currentPath = currentPath ?? '/'
    this.objects = objects ?? []
    this.showType = showType ?? ShowType.SHOW_LIST
    this.thumbImage = thumbImage
    this.thumbSource = thumbSource
    this.onOpen = onOpen
    this.onMenuClick = onMenuClick
  }
}
