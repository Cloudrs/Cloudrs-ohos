
import { ObjectInfo } from "./net/ApiTypes"
import { CommonUtil } from "../utils/CommonUtil"

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

  constructor(currentPath?: string, objects?: ObjectInfo[]) {
    this.currentPath = currentPath ?? '/'
    this.objects = objects ?? []
  }
}
