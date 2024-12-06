
export class ImagePreview {
  fileName: string = ''
  fileId: string = ''
  fileExtension: string = ''

  constructor(fileName: string, fileId: string, fileExtension: string) {
    this.fileName = fileName
    this.fileId = fileId
    this.fileExtension = fileExtension
  }
}