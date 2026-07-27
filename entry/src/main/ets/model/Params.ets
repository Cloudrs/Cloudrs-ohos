
import { ObjectInfo } from "./net/ApiTypes"
import { CommonUtil } from "../utils/CommonUtil"
import { FileMenuType, ShowType } from "./MenuModel"
import { PhotoBackupItem } from "./PhotoBackupModel"

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
  // 碰一碰创建分享链接用的规范化路径;为空则未下载场景回退分享下载直链
  sharePath: string = ''
  // 应用接续恢复用:起播位置(秒)与是否自动播放,常规打开保持 0/true
  startTime: number = 0
  autoPlay: boolean = true

  constructor(fileName: string, fileId: string, fileExtension: string, sharePath: string = '',
    startTime: number = 0, autoPlay: boolean = true) {
    this.fileName = fileName
    this.fileId = fileId
    this.fileExtension = fileExtension
    this.sharePath = sharePath
    this.startTime = startTime
    this.autoPlay = autoPlay
  }
}

export class PhotoLocalPreviewParam {
  items: PhotoBackupItem[] = []
  index: number = 0
  backupEnabled: boolean = false

  constructor(items: PhotoBackupItem[], index: number, backupEnabled: boolean) {
    this.items = items
    this.index = index
    this.backupEnabled = backupEnabled
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
