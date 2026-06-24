
import { CloudThemeToken } from "../model/CloudTheme";
import Constant from "../model/Constant";

export enum FileType {
  IMAGE = 'image',
  VIDEO = 'video',
  MUSIC = 'music',
  WORD = 'word',
  EXCEL = 'excel',
  PPT = 'ppt',
  JSON = 'json',
  XML = 'xml',
  YAML = 'yaml',
  TOML = 'toml',
  TXT = 'txt',
  CONF = 'conf',
  PDF = 'pdf',
  COMPRESSED = 'compressed',
  DB = 'database',
  CODE = 'code',
  MARKDOWN = 'markdown',
  DOCUMENT = 'document',
  UNKNOWN = 'unknown'
}

export interface FileIconInfo {
  icon: Resource,
  color?: Resource,
  backgroundColor?: ResourceColor,
}

export class CommonUtil {

  static formatBytes(bytes: number, decimals = 2): string {
    if (bytes === 0) return '0 B';

    const k = Constant.BYTE_UNIT_SIZE;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];

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

  static getFileName(filePath: string): string {
    if (filePath.length === 0) {
      return ''
    }
    const normalizedPath = filePath.endsWith('/') ? filePath.substring(0, filePath.length - 1) : filePath
    const lastSlashIndex = normalizedPath.lastIndexOf('/')
    return lastSlashIndex === -1 ? normalizedPath : normalizedPath.substring(lastSlashIndex + 1)
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
      case 'heic':
      case 'heif':
      case 'svg':
        return FileType.IMAGE

      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'avi':
      case 'rmvb':
      case 'mpg':
      case 'mpeg':
      case 'm4v':
      case 'webm':
      case '3gp':
        return FileType.VIDEO

      case 'mp3':
      case 'm4a':
      case 'aac':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'opus':
        return FileType.MUSIC

      case 'doc':
      case 'docx':
        return FileType.WORD

      case 'xls':
      case 'xlsx':
      case 'csv':
        return FileType.EXCEL

      case 'ppt':
      case 'pptx':
        return FileType.PPT

      case 'txt':
      case 'log':
        return FileType.TXT

      case 'conf':
      case 'config':
      case 'ini':
      case 'env':
      case 'properties':
        return FileType.CONF

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
      case 'bz2':
      case 'xz':
        return FileType.COMPRESSED

      case 'pdf':
        return FileType.PDF

      case 'db':
      case 'sqlite':
      case 'sqlite3':
      case 'sql':
        return FileType.DB

      case 'md':
      case 'markdown':
        return FileType.MARKDOWN

      case 'js':
      case 'ts':
      case 'ets':
      case 'css':
      case 'scss':
      case 'sass':
      case 'html':
      case 'htm':
      case 'java':
      case 'kt':
      case 'kts':
      case 'go':
      case 'rs':
      case 'py':
      case 'c':
      case 'h':
      case 'cpp':
      case 'hpp':
      case 'cc':
      case 'cxx':
      case 'cs':
      case 'sh':
      case 'ps1':
      case 'bat':
        return FileType.CODE

      default:
        return FileType.UNKNOWN
    }
  }

  /**
   * 生成保存到相册时的标题（不含扩展名）。
   * 规则：去扩展名 → 过滤非法字符( . \ / : * ? " ' ` < > | { } [ ] ) → 截断 255 → 为空回退 'image'。
   */
  static sanitizeAlbumTitle(name: string): string {
    const dot = name.lastIndexOf('.')
    const raw = dot >= 0 ? name.substring(0, dot) : name
    const illegal = '.\\/:*?"\'`<>|{}[]'
    let base = ''
    for (let i = 0; i < raw.length; i++) {
      const ch = raw.charAt(i)
      if (illegal.indexOf(ch) === -1) {
        base += ch
      }
    }
    if (base.length > 255) {
      base = base.substring(0, 255)
    }
    return base.length === 0 ? 'image' : base
  }

  /** 判断一组文件名是否全部为图片类型（空数组返回 false）。 */
  static isAllImages(names: string[]): boolean {
    return names.length > 0 && names.every((n: string) => CommonUtil.getFileType(n) === FileType.IMAGE)
  }

  static getFileIconInfo(fileName: string): FileIconInfo {
    let fileExtention = CommonUtil.getFileExtention(fileName).toLowerCase()
    let lowerFileName = fileName.toLowerCase()
    let fileType = CommonUtil.getFileType(fileName)
    let fileIconInfo: FileIconInfo = {
      icon: $r('app.media.mit_file_document'),
      backgroundColor: CloudThemeToken.fileIconBackground
    }

    if (lowerFileName === 'dockerfile') {
      fileIconInfo.icon = $r('app.media.mit_file_docker')
      return fileIconInfo
    }

    switch (fileExtention) {
      case 'js':
        fileIconInfo.icon = $r('app.media.mit_file_javascript')
        return fileIconInfo
      case 'ts':
      case 'ets':
        fileIconInfo.icon = $r('app.media.mit_file_typescript')
        return fileIconInfo
      case 'html':
      case 'htm':
        fileIconInfo.icon = $r('app.media.mit_file_html')
        return fileIconInfo
      case 'css':
      case 'scss':
      case 'sass':
        fileIconInfo.icon = $r('app.media.mit_file_css')
        return fileIconInfo
      case 'py':
        fileIconInfo.icon = $r('app.media.mit_file_python')
        return fileIconInfo
      case 'java':
        fileIconInfo.icon = $r('app.media.mit_file_java')
        return fileIconInfo
      case 'kt':
      case 'kts':
        fileIconInfo.icon = $r('app.media.mit_file_kotlin')
        return fileIconInfo
      case 'go':
        fileIconInfo.icon = $r('app.media.mit_file_go')
        return fileIconInfo
      case 'rs':
        fileIconInfo.icon = $r('app.media.mit_file_rust')
        return fileIconInfo
      case 'ps1':
        fileIconInfo.icon = $r('app.media.mit_file_powershell')
        return fileIconInfo
      case 'c':
      case 'h':
        fileIconInfo.icon = $r('app.media.mit_file_c')
        return fileIconInfo
      case 'cpp':
      case 'hpp':
      case 'cc':
      case 'cxx':
        fileIconInfo.icon = $r('app.media.mit_file_cpp')
        return fileIconInfo
      case 'cs':
        fileIconInfo.icon = $r('app.media.mit_file_csharp')
        return fileIconInfo
    }

    switch (fileType) {
      case FileType.IMAGE:
        fileIconInfo.icon = $r('app.media.mit_file_image')
        break;
      case FileType.VIDEO:
        fileIconInfo.icon = $r('app.media.mit_file_video')
        break;
      case FileType.MUSIC:
        fileIconInfo.icon = $r('app.media.mit_file_audio')
        break;
      case FileType.WORD:
        fileIconInfo.icon = $r('app.media.mit_file_word')
        break;
      case FileType.EXCEL:
        fileIconInfo.icon = $r('app.media.mit_file_table')
        break;
      case FileType.PPT:
        fileIconInfo.icon = $r('app.media.mit_file_powerpoint')
        break;
      case FileType.TXT:
      case FileType.DOCUMENT:
        fileIconInfo.icon = $r('app.media.mit_file_document')
        break;
      case FileType.COMPRESSED:
        fileIconInfo.icon = $r('app.media.mit_file_zip')
        break;
      case FileType.XML:
        fileIconInfo.icon = $r('app.media.mit_file_xml')
        break;
      case FileType.JSON:
        fileIconInfo.icon = $r('app.media.mit_file_json')
        break;
      case FileType.YAML:
        fileIconInfo.icon = $r('app.media.mit_file_yaml')
        break;
      case FileType.TOML:
      case FileType.CONF:
        fileIconInfo.icon = $r('app.media.mit_file_settings')
        break;
      case FileType.PDF:
        fileIconInfo.icon = $r('app.media.mit_file_pdf')
        break;
      case FileType.DB:
        fileIconInfo.icon = $r('app.media.mit_file_database')
        break;
      case FileType.CODE:
        fileIconInfo.icon = $r('app.media.mit_file_settings')
        break;
      case FileType.MARKDOWN:
        fileIconInfo.icon = $r('app.media.mit_file_markdown')
        break;
    }

    return fileIconInfo
  }

  static getDaysDifference(date1: Date, date2: Date): number {
    const diffInMilliseconds = Math.abs(date2.getTime() - date1.getTime());
    const diffInDays = diffInMilliseconds / (Constant.MILLISECONDS_PER_SECOND * Constant.SECONDS_PER_MINUTE *
      Constant.MINUTES_PER_HOUR * Constant.HOURS_PER_DAY);
    return Math.floor(diffInDays); // 或者使用 Math.round 根据需要
  }
}
