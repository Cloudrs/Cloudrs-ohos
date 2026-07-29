import { util } from '@kit.ArkTS';

/**
 * 文本文件解码。
 *
 * 只负责"这堆字节是不是文本、是什么编码、换行符是什么"，不碰网络与 UI。
 * 编码判定顺序：BOM > UTF-8 严格解码 > GBK 严格解码，都不成立就当作二进制拒绝显示——
 * 宁可明确说"认不出"，也不要用替换字符糊一屏乱码给用户。
 */

const TAG: string = 'TextFileCodec'

/** UTF-8 严格解码失败后的兜底尝试；GB18030 几乎不拒绝任何字节序列，不参与探测 */
const ENCODING_UTF8: string = 'utf-8'
const ENCODING_GBK: string = 'gbk'
const ENCODING_UTF16LE: string = 'utf-16le'
const ENCODING_UTF16BE: string = 'utf-16be'

const LABEL_UTF8: string = 'UTF-8'
const LABEL_UTF8_BOM: string = 'UTF-8 BOM'
const LABEL_GBK: string = 'GBK'
const LABEL_UTF16LE: string = 'UTF-16 LE'
const LABEL_UTF16BE: string = 'UTF-16 BE'

const BOM_UTF8_0: number = 0xEF
const BOM_UTF8_1: number = 0xBB
const BOM_UTF8_2: number = 0xBF
const BOM_UTF16_FF: number = 0xFF
const BOM_UTF16_FE: number = 0xFE
const NUL_BYTE: number = 0

/** 二进制探测只看开头这么多字节，整文件扫一遍对大文件不划算 */
const BINARY_PROBE_BYTES: number = 8192

export enum TextLineEnding {
  LF = 'LF',
  CRLF = 'CRLF',
  CR = 'CR',
  MIXED = '混合'
}

export enum TextDecodeFailure {
  NONE = 'none',
  /** 含 NUL 字节或所有候选编码都严格解码失败，判定为非文本 */
  BINARY = 'binary',
  /** 手动指定的编码与文件实际内容对不上 */
  ENCODING_MISMATCH = 'encoding_mismatch'
}

export class TextDecodeResult {
  ok: boolean = false
  text: string = ''
  /** 展示用编码名，如 'UTF-8' / 'UTF-8 BOM' / 'GBK' */
  encoding: string = ''
  lineEnding: TextLineEnding = TextLineEnding.LF
  /** 写回时需要原样补回 BOM，P0 只读用它做展示 */
  hasBom: boolean = false
  failure: TextDecodeFailure = TextDecodeFailure.NONE
}

class BomInfo {
  encoding: string = ''
  label: string = ''
  size: number = 0
}

/** 写回时要还原的原文件特征，取自加载时的 TextDecodeResult */
export class TextEncodeOptions {
  lineEnding: TextLineEnding = TextLineEnding.LF
  hasBom: boolean = false

  constructor(lineEnding: TextLineEnding, hasBom: boolean) {
    this.lineEnding = lineEnding
    this.hasBom = hasBom
  }
}

export class TextFileCodec {
  static decode(buffer: ArrayBuffer): TextDecodeResult {
    const result = new TextDecodeResult()
    const bytes = new Uint8Array(buffer)

    if (bytes.length === NUL_BYTE) {
      result.ok = true
      result.encoding = LABEL_UTF8
      return result
    }

    const bom = TextFileCodec.detectBom(bytes)
    if (bom.size > 0) {
      // BOM 已经指明编码，不再做二进制探测：UTF-16 正文本来就满是 0x00
      const decoded = TextFileCodec.tryDecode(bytes, bom.encoding, false)
      if (decoded === undefined) {
        result.failure = TextDecodeFailure.BINARY
        return result
      }
      return TextFileCodec.finish(result, decoded, bom.label, true)
    }

    if (TextFileCodec.looksBinary(bytes)) {
      result.failure = TextDecodeFailure.BINARY
      return result
    }

    const asUtf8 = TextFileCodec.tryDecode(bytes, ENCODING_UTF8, true)
    if (asUtf8 !== undefined) {
      return TextFileCodec.finish(result, asUtf8, LABEL_UTF8, false)
    }

    const asGbk = TextFileCodec.tryDecode(bytes, ENCODING_GBK, true)
    if (asGbk !== undefined) {
      return TextFileCodec.finish(result, asGbk, LABEL_GBK, false)
    }

    result.failure = TextDecodeFailure.BINARY
    return result
  }

  /** 用户可手动切换的编码，探测错时兜底 */
  static supportedEncodings(): string[] {
    return [LABEL_UTF8, LABEL_GBK, LABEL_UTF16LE, LABEL_UTF16BE]
  }

  /**
   * 按指定编码强行解码，供用户手动纠正探测结果。
   *
   * 必须严格校验，不能"照做并把结果呈现出来"：解码结果会参与 canEdit 判定，
   * 一旦放行乱码，用户编辑后保存就会用替换字符覆盖掉原文件，且不可逆。
   * 三道校验缺一不可：
   *   1. fatal 解码——非法字节序列直接失败；
   *   2. BOM 一致性——文件自带 BOM 却被要求按别的编码解，说明选错了；
   *   3. 二进制探测——UTF-16 正文在 UTF-8 眼里全是合法字节（NUL 也合法），
   *      fatal 拦不住，只能靠 NUL 探测把它挡回去。
   */
  static decodeAs(buffer: ArrayBuffer, encodingLabel: string): TextDecodeResult {
    const result = new TextDecodeResult()
    const bytes = new Uint8Array(buffer)
    const codec = TextFileCodec.codecOf(encodingLabel)
    const bom = TextFileCodec.detectBom(bytes)

    if (bom.size > 0 && bom.encoding !== codec) {
      result.failure = TextDecodeFailure.ENCODING_MISMATCH
      return result
    }
    const isUtf16 = codec === ENCODING_UTF16LE || codec === ENCODING_UTF16BE
    if (!isUtf16 && TextFileCodec.looksBinary(bytes)) {
      result.failure = TextDecodeFailure.ENCODING_MISMATCH
      return result
    }

    const decoded = TextFileCodec.tryDecode(bytes, codec, true)
    if (decoded === undefined) {
      result.failure = TextDecodeFailure.ENCODING_MISMATCH
      return result
    }
    const label = bom.size > 0 && encodingLabel === LABEL_UTF8 ? LABEL_UTF8_BOM : encodingLabel
    return TextFileCodec.finish(result, decoded, label, bom.size > 0)
  }

  private static codecOf(encodingLabel: string): string {
    if (encodingLabel === LABEL_GBK) {
      return ENCODING_GBK
    }
    if (encodingLabel === LABEL_UTF16LE) {
      return ENCODING_UTF16LE
    }
    if (encodingLabel === LABEL_UTF16BE) {
      return ENCODING_UTF16BE
    }
    return ENCODING_UTF8
  }

  /** 按行切分，同时吃掉 CRLF / CR / LF 三种换行 */
  static splitLines(text: string): string[] {
    return text.split(/\r\n|\r|\n/)
  }

  /**
   * 只有 UTF-8（含 BOM）允许写回。
   * GBK/UTF-16 用 UTF-8 覆盖回去就是把用户的文件写坏，宁可只读。
   */
  static isWritableEncoding(encoding: string): boolean {
    return encoding === LABEL_UTF8 || encoding === LABEL_UTF8_BOM
  }

  /**
   * 文本 → 字节，还原原文件的换行符与 BOM。
   * 编辑器交回来的正文一律是 LF，不还原的话打开再保存就是全文件 diff。
   */
  static encode(text: string, options: TextEncodeOptions): ArrayBuffer {
    const normalized = TextFileCodec.applyLineEnding(text, options.lineEnding)
    const body = new util.TextEncoder().encodeInto(normalized)
    if (!options.hasBom) {
      return TextFileCodec.toArrayBuffer(body)
    }
    const withBom = new Uint8Array(body.length + 3)
    withBom[0] = BOM_UTF8_0
    withBom[1] = BOM_UTF8_1
    withBom[2] = BOM_UTF8_2
    withBom.set(body, 3)
    return TextFileCodec.toArrayBuffer(withBom)
  }

  private static toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const copy = new Uint8Array(bytes.length)
    copy.set(bytes)
    return copy.buffer as ArrayBuffer
  }

  /**
   * MIXED 按 LF 落盘：原文件本来就不一致，没有"原样"可还原，
   * 统一成 LF 至少是个确定结果，也不会比原状态更糟。
   */
  private static applyLineEnding(text: string, lineEnding: TextLineEnding): string {
    if (lineEnding === TextLineEnding.CRLF) {
      return text.replace(/\n/g, '\r\n')
    }
    if (lineEnding === TextLineEnding.CR) {
      return text.replace(/\n/g, '\r')
    }
    return text
  }

  private static finish(
    result: TextDecodeResult, text: string, encodingLabel: string, hasBom: boolean
  ): TextDecodeResult {
    result.ok = true
    result.text = text
    result.encoding = encodingLabel
    result.hasBom = hasBom
    result.lineEnding = TextFileCodec.detectLineEnding(text)
    return result
  }

  private static detectBom(bytes: Uint8Array): BomInfo {
    const info = new BomInfo()
    if (bytes.length >= 3 &&
      bytes[0] === BOM_UTF8_0 && bytes[1] === BOM_UTF8_1 && bytes[2] === BOM_UTF8_2) {
      info.encoding = ENCODING_UTF8
      info.label = LABEL_UTF8_BOM
      info.size = 3
      return info
    }
    if (bytes.length >= 2 && bytes[0] === BOM_UTF16_FF && bytes[1] === BOM_UTF16_FE) {
      info.encoding = ENCODING_UTF16LE
      info.label = LABEL_UTF16LE
      info.size = 2
      return info
    }
    if (bytes.length >= 2 && bytes[0] === BOM_UTF16_FE && bytes[1] === BOM_UTF16_FF) {
      info.encoding = ENCODING_UTF16BE
      info.label = LABEL_UTF16BE
      info.size = 2
      return info
    }
    return info
  }

  /**
   * NUL 字节是区分文本与二进制最省事也最可靠的信号。
   * 代价是无 BOM 的 UTF-16 会被误判成二进制——这类文件极少，且宁可拒绝也别显示乱码。
   */
  private static looksBinary(bytes: Uint8Array): boolean {
    const limit = Math.min(bytes.length, BINARY_PROBE_BYTES)
    for (let i = 0; i < limit; i++) {
      if (bytes[i] === NUL_BYTE) {
        return true
      }
    }
    return false
  }

  /** fatal 为 true 时非法字节序列会抛异常，正好用来判定"是不是这个编码" */
  private static tryDecode(bytes: Uint8Array, encoding: string, fatal: boolean): string | undefined {
    try {
      const options: util.TextDecoderOptions = { fatal: fatal, ignoreBOM: true }
      const decoder = util.TextDecoder.create(encoding, options)
      const decodeOptions: util.DecodeToStringOptions = { stream: false }
      return decoder.decodeToString(bytes, decodeOptions)
    } catch (err) {
      console.info(TAG, `decode as ${encoding} failed: ${(err as Error)?.message ?? err}`)
      return undefined
    }
  }

  private static detectLineEnding(text: string): TextLineEnding {
    const crlf = TextFileCodec.countOf(text, '\r\n')
    const lfTotal = TextFileCodec.countOf(text, '\n')
    const crTotal = TextFileCodec.countOf(text, '\r')
    const bareLf = lfTotal - crlf
    const bareCr = crTotal - crlf

    if (crlf > 0 && bareLf === 0 && bareCr === 0) {
      return TextLineEnding.CRLF
    }
    if (crlf === 0 && bareCr === 0) {
      // 单行文件（一个换行都没有）按 LF 报，不值得为它单列一种状态
      return TextLineEnding.LF
    }
    if (crlf === 0 && bareLf === 0) {
      return TextLineEnding.CR
    }
    return TextLineEnding.MIXED
  }

  private static countOf(text: string, token: string): number {
    let count = 0
    let index = text.indexOf(token)
    while (index >= 0) {
      count++
      index = text.indexOf(token, index + token.length)
    }
    return count
  }
}
