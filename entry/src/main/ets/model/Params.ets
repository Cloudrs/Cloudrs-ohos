
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
