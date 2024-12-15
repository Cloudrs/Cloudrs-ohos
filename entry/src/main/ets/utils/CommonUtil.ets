import { defaultAppManager } from "@kit.AbilityKit";
import File from "@system.file";

export enum FileType {
  IMAGE,
  VIDEO,
  WORD,
  JSON,
  XML,
  YAML,
  TOML,
  TXT,
  CONF,
  PDF,
  COMPRESSED,
  DB,
  CODE,
  MARKDOWN,
  UNKNOWN
}

export interface FileIconInfo {
  icon: Resource,
  color?: Resource,
  backgroundColor?: Resource,
}

export class CommonUtil {

  static formatBytes(bytes: number, decimals = 2): string {
    if (bytes === 0) return '0 Bytes';

    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];

    const i = Math.floor(Math.log(bytes) / Math.log(k));

    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
  }

  static getDirectoryPath(filePath: string): string {
    const lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex === -1) {
      return '/';
    }
    const directoryPath = filePath.substring(0, lastSlashIndex);
    return directoryPath === '' ? '/' : directoryPath;
  }

  static getLastDirectoryName(filePath: string): string {
    // 分割路径并去除空字符串
    const parts = filePath.split('/').filter(part => part !== '');
    const lastDirectoryName = parts.length >= 1 ? parts[parts.length - 1] : '/';
    return lastDirectoryName;
  }

  /**
   * 根据文件名获取文件后缀
   * @param fileName 例如: test.txt  test.doc
   * @returns
   */
  static getFileExtention(fileName: string) {
    if (fileName.length != 0 && fileName.includes(".")) {
      return fileName.substring(fileName.lastIndexOf(".") + 1);
    }
    return '';
  }

  static getFileType(fileName: string): FileType {
    let fileExtention = CommonUtil.getFileExtention(fileName).toLowerCase()
    switch (fileExtention) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return FileType.IMAGE

      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'avi':
      case 'rmvb':
      case 'mpg':
        return FileType.VIDEO

      case 'doc':
      case 'docx':
      case 'xls':
      case 'xlsx':
      case 'ppt':
      case 'pptx':
        return FileType.WORD

      case 'xml':
        return FileType.XML

      case 'json':
      case 'json5':
        return FileType.JSON

      case 'yaml':
      case 'yml':
        return FileType.YAML

      case 'toml':
        return FileType.TOML

      case 'zip':
      case 'rar':
      case 'gz':
      case 'tar':
      case '7z':
        return FileType.COMPRESSED

      case 'pdf':
        return FileType.PDF

      case 'db':
        return FileType.DB

      case 'md':
        return FileType.MARKDOWN

      default:
        return FileType.UNKNOWN
    }
  }

  static getFileIconInfo(fileName: string) {
    let fileType = CommonUtil.getFileType(fileName)
    let fileIconInfo: FileIconInfo = {
      icon: $r('app.media.ic_doc_plaintext_fill'),
      backgroundColor: $r('app.color.file_icon_background')
    }

    switch (fileType){
      case FileType.IMAGE:
        fileIconInfo.icon = $r("app.media.ic_file_image")
        break;
      case FileType.VIDEO:
        fileIconInfo.icon = $r("app.media.ic_file_video")
        break;
      case FileType.WORD:
        fileIconInfo.icon = $r('app.media.ic_doc_text_fill')
        break;
      case FileType.COMPRESSED:
        fileIconInfo.icon = $r("app.media.ic_file_compressed")
        break;
      case FileType.XML:
        fileIconInfo.icon = $r("app.media.ic_file_xml")
        break;
      case FileType.JSON:
        fileIconInfo.icon = $r("app.media.ic_file_json")
        break;
      case FileType.YAML:
        fileIconInfo.icon = $r('app.media.ic_file_yaml')
        break;
      case FileType.TOML:
        fileIconInfo.icon = $r('app.media.ic_file_toml')
        break;
      case FileType.PDF:
        fileIconInfo.icon = $r("app.media.ic_file_pdf")
        break;
      case FileType.MARKDOWN:
        fileIconInfo.icon = $r("app.media.ic_file_markdown")
        break;
    }

    return fileIconInfo
  }

  static getDaysDifference(date1: Date, date2: Date): number {
    const diffInMilliseconds = Math.abs(date2.getTime() - date1.getTime());
    const diffInDays = diffInMilliseconds / (1000 * 60 * 60 * 24);
    return Math.floor(diffInDays); // 或者使用 Math.round 根据需要
  }
}