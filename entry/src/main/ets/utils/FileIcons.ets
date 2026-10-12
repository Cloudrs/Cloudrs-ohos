import Constant from '../model/Constant'
import UserPreferences from '../model/UserPreferences'
import { CloudThemeToken } from '../model/CloudTheme'
import { CommonUtil, FileType } from './CommonUtil'

/** 文件图标按类别取，不再按扩展名一一配图；值即 FILE_ICON_SETS 的下标 */
export enum FileIconCategory {
  FOLDER = 0,
  IMAGE = 1,
  VIDEO = 2,
  AUDIO = 3,
  PDF = 4,
  WORD = 5,
  EXCEL = 6,
  PPT = 7,
  ARCHIVE = 8,
  TEXT = 9,
  CODE = 10,
  MARKDOWN = 11,
  OTHER = 12,
  APP = 13,
  DISK = 14,
  FONT = 15,
  EBOOK = 16,
  DESIGN = 17,
  DATABASE = 18,
  CONFIG = 19,
  TORRENT = 20,
  CERT = 21,
  SUBTITLE = 22,
  WEB = 23
}

export const FILE_ICON_THEME_TILE: string = 'tile'
export const FILE_ICON_THEME_PAGE: string = 'page'
export const FILE_ICON_THEME_LINE: string = 'line'

/** 设置页主题选项的顺序与名称 */
export const FILE_ICON_THEMES: string[] = [FILE_ICON_THEME_TILE, FILE_ICON_THEME_PAGE, FILE_ICON_THEME_LINE]
export const FILE_ICON_THEME_LABELS: string[] = ['色块', '文档页', '线性']
/** 设置页预览条的图标顺序：放不下时从后往前截掉 */
export const FILE_ICON_PREVIEW_ORDER: FileIconCategory[] = [
  FileIconCategory.FOLDER, FileIconCategory.IMAGE, FileIconCategory.VIDEO, FileIconCategory.AUDIO,
  FileIconCategory.PDF, FileIconCategory.WORD, FileIconCategory.EXCEL, FileIconCategory.ARCHIVE,
  FileIconCategory.PPT, FileIconCategory.TEXT, FileIconCategory.CODE, FileIconCategory.MARKDOWN,
  FileIconCategory.APP, FileIconCategory.DISK, FileIconCategory.EBOOK, FileIconCategory.DESIGN,
  FileIconCategory.DATABASE, FileIconCategory.CONFIG, FileIconCategory.FONT, FileIconCategory.WEB,
  FileIconCategory.SUBTITLE, FileIconCategory.TORRENT, FileIconCategory.CERT, FileIconCategory.OTHER
]

/** 一个类别在各主题下的图标，以及色块主题网格卡片顶部铺的极浅底色 */
interface FileIconSet {
  tile: Resource
  page: Resource
  line: Resource
  tileBackground: ResourceColor
}

// 下标与 FileIconCategory 一致；深色版在 dark/media、dark/element 同名，随深浅色自动切换。
// 文件夹卡片没有图块，底色占位用通用浅底
const FILE_ICON_SETS: FileIconSet[] = [
  { // FOLDER
    tile: $r('app.media.ic_ft_tile_folder'), page: $r('app.media.ic_ft_page_folder'),
    line: $r('app.media.ic_ft_line_folder'), tileBackground: CloudThemeToken.surfaceSubtle
  },
  { // IMAGE
    tile: $r('app.media.ic_ft_tile_image'), page: $r('app.media.ic_ft_page_image'),
    line: $r('app.media.ic_ft_line_image'), tileBackground: $r('app.color.file_tile_image')
  },
  { // VIDEO
    tile: $r('app.media.ic_ft_tile_video'), page: $r('app.media.ic_ft_page_video'),
    line: $r('app.media.ic_ft_line_video'), tileBackground: $r('app.color.file_tile_video')
  },
  { // AUDIO
    tile: $r('app.media.ic_ft_tile_audio'), page: $r('app.media.ic_ft_page_audio'),
    line: $r('app.media.ic_ft_line_audio'), tileBackground: $r('app.color.file_tile_audio')
  },
  { // PDF
    tile: $r('app.media.ic_ft_tile_pdf'), page: $r('app.media.ic_ft_page_pdf'),
    line: $r('app.media.ic_ft_line_pdf'), tileBackground: $r('app.color.file_tile_pdf')
  },
  { // WORD
    tile: $r('app.media.ic_ft_tile_word'), page: $r('app.media.ic_ft_page_word'),
    line: $r('app.media.ic_ft_line_word'), tileBackground: $r('app.color.file_tile_word')
  },
  { // EXCEL
    tile: $r('app.media.ic_ft_tile_excel'), page: $r('app.media.ic_ft_page_excel'),
    line: $r('app.media.ic_ft_line_excel'), tileBackground: $r('app.color.file_tile_excel')
  },
  { // PPT
    tile: $r('app.media.ic_ft_tile_ppt'), page: $r('app.media.ic_ft_page_ppt'),
    line: $r('app.media.ic_ft_line_ppt'), tileBackground: $r('app.color.file_tile_ppt')
  },
  { // ARCHIVE
    tile: $r('app.media.ic_ft_tile_archive'), page: $r('app.media.ic_ft_page_archive'),
    line: $r('app.media.ic_ft_line_archive'), tileBackground: $r('app.color.file_tile_archive')
  },
  { // TEXT
    tile: $r('app.media.ic_ft_tile_text'), page: $r('app.media.ic_ft_page_text'),
    line: $r('app.media.ic_ft_line_text'), tileBackground: $r('app.color.file_tile_text')
  },
  { // CODE
    tile: $r('app.media.ic_ft_tile_code'), page: $r('app.media.ic_ft_page_code'),
    line: $r('app.media.ic_ft_line_code'), tileBackground: $r('app.color.file_tile_code')
  },
  { // MARKDOWN
    tile: $r('app.media.ic_ft_tile_markdown'), page: $r('app.media.ic_ft_page_markdown'),
    line: $r('app.media.ic_ft_line_markdown'), tileBackground: $r('app.color.file_tile_markdown')
  },
  { // OTHER
    tile: $r('app.media.ic_ft_tile_other'), page: $r('app.media.ic_ft_page_other'),
    line: $r('app.media.ic_ft_line_other'), tileBackground: $r('app.color.file_tile_other')
  },
  { // APP
    tile: $r('app.media.ic_ft_tile_app'), page: $r('app.media.ic_ft_page_app'),
    line: $r('app.media.ic_ft_line_app'), tileBackground: $r('app.color.file_tile_app')
  },
  { // DISK
    tile: $r('app.media.ic_ft_tile_disk'), page: $r('app.media.ic_ft_page_disk'),
    line: $r('app.media.ic_ft_line_disk'), tileBackground: $r('app.color.file_tile_disk')
  },
  { // FONT
    tile: $r('app.media.ic_ft_tile_font'), page: $r('app.media.ic_ft_page_font'),
    line: $r('app.media.ic_ft_line_font'), tileBackground: $r('app.color.file_tile_font')
  },
  { // EBOOK
    tile: $r('app.media.ic_ft_tile_ebook'), page: $r('app.media.ic_ft_page_ebook'),
    line: $r('app.media.ic_ft_line_ebook'), tileBackground: $r('app.color.file_tile_ebook')
  },
  { // DESIGN
    tile: $r('app.media.ic_ft_tile_design'), page: $r('app.media.ic_ft_page_design'),
    line: $r('app.media.ic_ft_line_design'), tileBackground: $r('app.color.file_tile_design')
  },
  { // DATABASE
    tile: $r('app.media.ic_ft_tile_database'), page: $r('app.media.ic_ft_page_database'),
    line: $r('app.media.ic_ft_line_database'), tileBackground: $r('app.color.file_tile_database')
  },
  { // CONFIG
    tile: $r('app.media.ic_ft_tile_config'), page: $r('app.media.ic_ft_page_config'),
    line: $r('app.media.ic_ft_line_config'), tileBackground: $r('app.color.file_tile_config')
  },
  { // TORRENT
    tile: $r('app.media.ic_ft_tile_torrent'), page: $r('app.media.ic_ft_page_torrent'),
    line: $r('app.media.ic_ft_line_torrent'), tileBackground: $r('app.color.file_tile_torrent')
  },
  { // CERT
    tile: $r('app.media.ic_ft_tile_cert'), page: $r('app.media.ic_ft_page_cert'),
    line: $r('app.media.ic_ft_line_cert'), tileBackground: $r('app.color.file_tile_cert')
  },
  { // SUBTITLE
    tile: $r('app.media.ic_ft_tile_subtitle'), page: $r('app.media.ic_ft_page_subtitle'),
    line: $r('app.media.ic_ft_line_subtitle'), tileBackground: $r('app.color.file_tile_subtitle')
  },
  { // WEB
    tile: $r('app.media.ic_ft_tile_web'), page: $r('app.media.ic_ft_page_web'),
    line: $r('app.media.ic_ft_line_web'), tileBackground: $r('app.color.file_tile_web')
  }
]

/** 一组扩展名（或无扩展名的整个文件名，均为小写）归到同一类别 */
interface CategoryGroup {
  category: FileIconCategory
  keys: string[]
}

// 图标专用的「扩展名 → 类别」，只列 getFileType 不认识、或图标归类与它不同的扩展名，其余回落到 getFileType。
// getFileType 还决定预览与文本查看方式，图标要细分的类别不去改它。ts 留给 TypeScript，不当视频（MPEG-TS）
const EXTENSION_GROUPS: CategoryGroup[] = [
  {
    category: FileIconCategory.IMAGE,
    keys: ['tif', 'tiff', 'ico', 'icns', 'avif', 'jxl', 'jfif', 'apng', 'tga', 'raw', 'cr2', 'cr3', 'nef',
      'nrw', 'arw', 'dng', 'raf', 'orf', 'rw2', 'srw', 'pef']
  },
  {
    category: FileIconCategory.VIDEO,
    keys: ['m2ts', 'mts', 'vob', 'ogv', 'f4v', 'asf', 'rm', 'divx', '3g2', 'm2v', 'mxf']
  },
  {
    category: FileIconCategory.AUDIO,
    keys: ['wma', 'ape', 'aiff', 'aif', 'mid', 'midi', 'amr', 'alac', 'dsf', 'dff', 'm4b', 'm4r', 'mka', 'wv',
      'ac3', 'dts', 'caf', 'ra', 'mp2']
  },
  {
    category: FileIconCategory.WORD,
    keys: ['rtf', 'odt', 'wps', 'pages', 'dot', 'dotx', 'docm', 'dotm']
  },
  {
    category: FileIconCategory.EXCEL,
    keys: ['ods', 'numbers', 'et', 'ett', 'xlsm', 'xlsb', 'xlt', 'xltx', 'tsv']
  },
  {
    category: FileIconCategory.PPT,
    keys: ['odp', 'dps', 'pps', 'ppsx', 'pot', 'potx', 'pptm']
  },
  {
    category: FileIconCategory.ARCHIVE,
    keys: ['tgz', 'tbz', 'tbz2', 'txz', 'lz', 'lzma', 'lz4', 'zst', 'cab', 'z', 'lzh', 'arj', 'cpio', 'jar',
      'war', 'ear']
  },
  {
    category: FileIconCategory.TEXT,
    keys: ['nfo', 'text', 'rst', 'adoc', 'asciidoc', 'org', 'tex']
  },
  {
    category: FileIconCategory.MARKDOWN,
    keys: ['mdx', 'mkd', 'mdown']
  },
  {
    category: FileIconCategory.CODE,
    keys: ['js', 'mjs', 'cjs', 'jsx', 'ts', 'tsx', 'ets', 'css', 'scss', 'sass', 'less', 'styl', 'vue',
      'svelte', 'astro', 'py', 'pyw', 'pyi', 'ipynb', 'java', 'kt', 'kts', 'scala', 'groovy', 'go', 'rs', 'c', 'h',
      'cpp', 'hpp', 'cc', 'cxx', 'cs', 'fs', 'fsx', 'vb', 'swift', 'm', 'mm', 'dart', 'rb', 'php', 'pl', 'pm', 'lua',
      'r', 'jl', 'hs', 'ml', 'elm', 'ex', 'exs', 'erl', 'clj', 'nim', 'zig', 'asm', 's', 'sol', 'wasm', 'ps1', 'psm1',
      'sh', 'bash', 'zsh', 'fish', 'bat', 'cmd', 'gradle', 'cmake', 'mk', 'proto', 'graphql', 'gql', 'tf', 'hcl',
      'coffee', 'jsp', 'asp', 'aspx', 'f90']
  },
  {
    category: FileIconCategory.APP,
    keys: ['apk', 'apks', 'xapk', 'aab', 'hap', 'app', 'ipa', 'exe', 'msi', 'msix', 'msixbundle', 'appx',
      'appxbundle', 'dmg', 'pkg', 'deb', 'rpm', 'appimage', 'run', 'snap', 'flatpak']
  },
  {
    category: FileIconCategory.DISK,
    keys: ['iso', 'img', 'vhd', 'vhdx', 'vmdk', 'qcow2', 'vdi', 'ova', 'ovf', 'esd', 'wim', 'cue', 'nrg', 'ccd']
  },
  {
    category: FileIconCategory.FONT,
    keys: ['ttf', 'otf', 'ttc', 'woff', 'woff2', 'fon', 'fnt', 'eot']
  },
  {
    category: FileIconCategory.EBOOK,
    keys: ['epub', 'mobi', 'azw', 'azw3', 'kfx', 'fb2', 'djvu', 'cbz', 'cbr', 'cb7', 'chm']
  },
  {
    category: FileIconCategory.DESIGN,
    keys: ['psd', 'psb', 'ai', 'eps', 'sketch', 'fig', 'xd', 'afdesign', 'afphoto', 'afpub', 'cdr', 'indd',
      'xcf', 'kra', 'procreate', 'blend', 'c4d', 'skp', 'dwg', 'dxf']
  },
  {
    category: FileIconCategory.DATABASE,
    keys: ['mdb', 'accdb', 'dbf', 'db3', 'realm', 'frm', 'ibd']
  },
  {
    category: FileIconCategory.CONFIG,
    keys: ['cfg', 'jsonc', 'plist', 'reg', 'inf', 'lock', 'htaccess', 'gitignore', 'gitattributes',
      'gitmodules', 'editorconfig', 'npmrc', 'nvmrc', 'dockerignore', 'prettierrc', 'eslintrc', 'babelrc', 'service',
      'desktop']
  },
  {
    category: FileIconCategory.TORRENT,
    keys: ['torrent', 'metalink']
  },
  {
    category: FileIconCategory.CERT,
    keys: ['pem', 'crt', 'cer', 'der', 'key', 'p12', 'pfx', 'jks', 'keystore', 'bks', 'csr', 'pub', 'gpg',
      'pgp', 'asc', 'sig', 'p7b', 'p7c', 'p8', 'ppk', 'mobileprovision', 'kdbx']
  },
  {
    category: FileIconCategory.SUBTITLE,
    keys: ['srt', 'ass', 'ssa', 'vtt', 'sub', 'smi', 'lrc', 'sbv']
  },
  {
    category: FileIconCategory.WEB,
    keys: ['html', 'htm', 'xhtml', 'shtml', 'mhtml', 'mht', 'url', 'webloc']
  }
]

// 没有扩展名、靠整个文件名认的
const NAME_GROUPS: CategoryGroup[] = [
  {
    category: FileIconCategory.CODE,
    keys: ['dockerfile', 'makefile', 'cmakelists.txt', 'jenkinsfile', 'vagrantfile', 'gemfile', 'rakefile']
  },
  {
    category: FileIconCategory.TEXT,
    keys: ['readme', 'license', 'changelog', 'authors', 'contributing', 'notice', 'copying']
  }
]

function buildCategoryMap(groups: CategoryGroup[]): Map<string, FileIconCategory> {
  const map = new Map<string, FileIconCategory>()
  for (const group of groups) {
    for (const key of group.keys) {
      map.set(key, group.category)
    }
  }
  return map
}

const EXTENSION_CATEGORIES: Map<string, FileIconCategory> = buildCategoryMap(EXTENSION_GROUPS)
const NAME_CATEGORIES: Map<string, FileIconCategory> = buildCategoryMap(NAME_GROUPS)

/**
 * 文件 / 文件夹图标主题：「文件名 → 类别」只在 categoryOf 做一次，「类别 → 图标 / 网格卡片底色」查 FILE_ICON_SETS。
 * 新增类别：生成三套 ic_ft_<主题>_<类别>.svg（base + dark）与 file_tile_<类别> 颜色，枚举末尾追加，FILE_ICON_SETS 补一行，
 * EXTENSION_GROUPS 里登记扩展名。新增主题：每行加一个字段，在 iconOf 与 FILE_ICON_THEMES 里注册。
 * 显示处用 @StorageProp(Constant.FILE_ICON_THEME) 读当前主题，切换后即时刷新。
 */
export class FileIcons {
  static getTheme(): string {
    const theme = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.FILE_ICON_THEME,
      FILE_ICON_THEME_TILE) as string
    return FILE_ICON_THEMES.indexOf(theme) >= 0 ? theme : FILE_ICON_THEME_TILE
  }

  static setTheme(theme: string): void {
    const next = FILE_ICON_THEMES.indexOf(theme) >= 0 ? theme : FILE_ICON_THEME_TILE
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.FILE_ICON_THEME, next)
    AppStorage.setOrCreate(Constant.FILE_ICON_THEME, next)
  }

  /** 启动时把持久化的主题镜像进 AppStorage，供各显示处 @StorageProp 读取 */
  static mirrorTheme(): void {
    AppStorage.setOrCreate(Constant.FILE_ICON_THEME, FileIcons.getTheme())
  }

  static categoryOf(fileName: string): FileIconCategory {
    const lowerName = fileName.toLowerCase()
    const byName = NAME_CATEGORIES.get(lowerName)
    if (byName !== undefined) {
      return byName
    }
    const byExtension = EXTENSION_CATEGORIES.get(CommonUtil.getFileExtention(lowerName))
    if (byExtension !== undefined) {
      return byExtension
    }
    switch (CommonUtil.getFileType(lowerName)) {
      case FileType.IMAGE:
        return FileIconCategory.IMAGE
      case FileType.VIDEO:
        return FileIconCategory.VIDEO
      case FileType.MUSIC:
        return FileIconCategory.AUDIO
      case FileType.PDF:
        return FileIconCategory.PDF
      case FileType.WORD:
        return FileIconCategory.WORD
      case FileType.EXCEL:
        return FileIconCategory.EXCEL
      case FileType.PPT:
        return FileIconCategory.PPT
      case FileType.COMPRESSED:
        return FileIconCategory.ARCHIVE
      case FileType.TXT:
      case FileType.DOCUMENT:
        return FileIconCategory.TEXT
      case FileType.MARKDOWN:
        return FileIconCategory.MARKDOWN
      case FileType.CODE:
        return FileIconCategory.CODE
      case FileType.JSON:
      case FileType.XML:
      case FileType.YAML:
      case FileType.TOML:
      case FileType.CONF:
        return FileIconCategory.CONFIG
      case FileType.DB:
        return FileIconCategory.DATABASE
      default:
        return FileIconCategory.OTHER
    }
  }

  static fileIcon(theme: string, fileName: string): Resource {
    return FileIcons.iconOf(theme, FileIcons.categoryOf(fileName))
  }

  static folderIcon(theme: string): Resource {
    return FileIcons.iconOf(theme, FileIconCategory.FOLDER)
  }

  static iconOf(theme: string, category: FileIconCategory): Resource {
    const set = FILE_ICON_SETS[category]
    if (theme === FILE_ICON_THEME_PAGE) {
      return set.page
    }
    if (theme === FILE_ICON_THEME_LINE) {
      return set.line
    }
    return set.tile
  }

  /** 网格卡片（无缩略图时）顶部图块的底色：色块主题按类型铺极浅色，其余主题用通用浅底 */
  static tileBackground(theme: string, fileName: string): ResourceColor {
    if (theme === FILE_ICON_THEME_TILE) {
      return FILE_ICON_SETS[FileIcons.categoryOf(fileName)].tileBackground
    }
    return CloudThemeToken.surfaceSubtle
  }
}
