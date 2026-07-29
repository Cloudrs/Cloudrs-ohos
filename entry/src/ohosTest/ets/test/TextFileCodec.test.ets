import { describe, it, expect } from '@ohos/hypium'
import { util } from '@kit.ArkTS'
import {
  TextDecodeFailure, TextEncodeOptions, TextFileCodec, TextLineEnding
} from '../../../main/ets/utils/TextFileCodec'

function utf8Buffer(text: string): ArrayBuffer {
  return new util.TextEncoder().encodeInto(text).buffer as ArrayBuffer
}

function gbkBuffer(text: string): ArrayBuffer {
  return util.TextEncoder.create('gbk').encodeInto(text).buffer as ArrayBuffer
}

function bytesBuffer(bytes: number[]): ArrayBuffer {
  return new Uint8Array(bytes).buffer as ArrayBuffer
}

export default function textFileCodecTest() {
  describe('TextFileCodec_decode', () => {
    it('decode_plainUtf8', 0, () => {
      const result = TextFileCodec.decode(utf8Buffer('hello\nworld'))
      expect(result.ok).assertTrue()
      expect(result.text).assertEqual('hello\nworld')
      expect(result.encoding).assertEqual('UTF-8')
      expect(result.hasBom).assertFalse()
    })

    it('decode_utf8WithChinese', 0, () => {
      const result = TextFileCodec.decode(utf8Buffer('中文内容'))
      expect(result.ok).assertTrue()
      expect(result.text).assertEqual('中文内容')
      expect(result.encoding).assertEqual('UTF-8')
    })

    it('decode_utf8BomStrippedFromText', 0, () => {
      const result = TextFileCodec.decode(bytesBuffer([0xEF, 0xBB, 0xBF, 0x61, 0x62, 0x63]))
      expect(result.ok).assertTrue()
      expect(result.encoding).assertEqual('UTF-8 BOM')
      expect(result.hasBom).assertTrue()
      // BOM 必须不落进正文，否则首行会多出一个不可见字符
      expect(result.text).assertEqual('abc')
    })

    it('decode_gbkFallbackWhenNotUtf8', 0, () => {
      const result = TextFileCodec.decode(gbkBuffer('中文内容'))
      expect(result.ok).assertTrue()
      expect(result.encoding).assertEqual('GBK')
      expect(result.text).assertEqual('中文内容')
    })

    it('decode_emptyFileIsOk', 0, () => {
      const result = TextFileCodec.decode(bytesBuffer([]))
      expect(result.ok).assertTrue()
      expect(result.text).assertEqual('')
    })

    it('decode_rejectsBinaryWithNulByte', 0, () => {
      const result = TextFileCodec.decode(bytesBuffer([0x50, 0x4B, 0x03, 0x04, 0x00, 0x61]))
      expect(result.ok).assertFalse()
      expect(result.failure).assertEqual(TextDecodeFailure.BINARY)
    })
  })

  describe('TextFileCodec_lineEnding', () => {
    it('lineEnding_lf', 0, () => {
      expect(TextFileCodec.decode(utf8Buffer('a\nb\nc')).lineEnding).assertEqual(TextLineEnding.LF)
    })

    it('lineEnding_crlf', 0, () => {
      expect(TextFileCodec.decode(utf8Buffer('a\r\nb\r\nc')).lineEnding).assertEqual(TextLineEnding.CRLF)
    })

    it('lineEnding_cr', 0, () => {
      expect(TextFileCodec.decode(utf8Buffer('a\rb\rc')).lineEnding).assertEqual(TextLineEnding.CR)
    })

    it('lineEnding_mixed', 0, () => {
      expect(TextFileCodec.decode(utf8Buffer('a\r\nb\nc')).lineEnding).assertEqual(TextLineEnding.MIXED)
    })

    it('lineEnding_singleLineReportsLf', 0, () => {
      expect(TextFileCodec.decode(utf8Buffer('no newline here')).lineEnding).assertEqual(TextLineEnding.LF)
    })
  })

  describe('TextFileCodec_encode', () => {
    it('encode_roundTripsPlainUtf8', 0, () => {
      const text = 'hello\nworld 中文'
      const buffer = TextFileCodec.encode(text, new TextEncodeOptions(TextLineEnding.LF, false))
      const back = TextFileCodec.decode(buffer)
      expect(back.ok).assertTrue()
      expect(back.text).assertEqual(text)
      expect(back.hasBom).assertFalse()
    })

    it('encode_restoresCrlf', 0, () => {
      // 编辑器交回来的永远是 LF，写回时必须还原成原文件的 CRLF
      const buffer = TextFileCodec.encode('a\nb\nc', new TextEncodeOptions(TextLineEnding.CRLF, false))
      const bytes = new Uint8Array(buffer)
      expect(bytes.length).assertEqual(7)
      const back = TextFileCodec.decode(buffer)
      expect(back.text).assertEqual('a\r\nb\r\nc')
      expect(back.lineEnding).assertEqual(TextLineEnding.CRLF)
    })

    it('encode_restoresCr', 0, () => {
      const buffer = TextFileCodec.encode('a\nb', new TextEncodeOptions(TextLineEnding.CR, false))
      expect(TextFileCodec.decode(buffer).text).assertEqual('a\rb')
    })

    it('encode_restoresBom', 0, () => {
      const buffer = TextFileCodec.encode('abc', new TextEncodeOptions(TextLineEnding.LF, true))
      const bytes = new Uint8Array(buffer)
      expect(bytes[0]).assertEqual(0xEF)
      expect(bytes[1]).assertEqual(0xBB)
      expect(bytes[2]).assertEqual(0xBF)
      const back = TextFileCodec.decode(buffer)
      expect(back.encoding).assertEqual('UTF-8 BOM')
      expect(back.hasBom).assertTrue()
      // BOM 不能重复写进正文
      expect(back.text).assertEqual('abc')
    })

    it('encode_mixedFallsBackToLf', 0, () => {
      const buffer = TextFileCodec.encode('a\nb', new TextEncodeOptions(TextLineEnding.MIXED, false))
      expect(TextFileCodec.decode(buffer).text).assertEqual('a\nb')
    })

    it('encode_decodeRoundTripKeepsBomAndCrlfTogether', 0, () => {
      const buffer = TextFileCodec.encode('x\ny', new TextEncodeOptions(TextLineEnding.CRLF, true))
      const back = TextFileCodec.decode(buffer)
      expect(back.text).assertEqual('x\r\ny')
      expect(back.hasBom).assertTrue()
      expect(back.lineEnding).assertEqual(TextLineEnding.CRLF)
    })
  })

  describe('TextFileCodec_decodeAs', () => {
    it('decodeAs_forcesGbk', 0, () => {
      const result = TextFileCodec.decodeAs(gbkBuffer('中文内容'), 'GBK')
      expect(result.ok).assertTrue()
      expect(result.encoding).assertEqual('GBK')
      expect(result.text).assertEqual('中文内容')
    })

    it('decodeAs_forcesUtf8EvenWhenDetectionWouldDiffer', 0, () => {
      const result = TextFileCodec.decodeAs(utf8Buffer('plain'), 'UTF-8')
      expect(result.ok).assertTrue()
      expect(result.text).assertEqual('plain')
    })

    it('decodeAs_keepsBomFlagForUtf8', 0, () => {
      const result = TextFileCodec.decodeAs(bytesBuffer([0xEF, 0xBB, 0xBF, 0x61]), 'UTF-8')
      expect(result.encoding).assertEqual('UTF-8 BOM')
      expect(result.hasBom).assertTrue()
      expect(result.text).assertEqual('a')
    })

    it('supportedEncodings_listsSwitchableOnes', 0, () => {
      const list = TextFileCodec.supportedEncodings()
      expect(list.includes('UTF-8')).assertTrue()
      expect(list.includes('GBK')).assertTrue()
      expect(list.length).assertEqual(4)
    })
  })

  describe('TextFileCodec_writable', () => {
    it('writable_onlyUtf8', 0, () => {
      expect(TextFileCodec.isWritableEncoding('UTF-8')).assertTrue()
      expect(TextFileCodec.isWritableEncoding('UTF-8 BOM')).assertTrue()
    })

    it('writable_rejectsGbkAndUtf16', 0, () => {
      expect(TextFileCodec.isWritableEncoding('GBK')).assertFalse()
      expect(TextFileCodec.isWritableEncoding('UTF-16 LE')).assertFalse()
      expect(TextFileCodec.isWritableEncoding('UTF-16 BE')).assertFalse()
    })
  })

  describe('TextFileCodec_splitLines', () => {
    it('splitLines_handlesAllThreeEndings', 0, () => {
      expect(TextFileCodec.splitLines('a\r\nb\nc\rd').length).assertEqual(4)
    })

    it('splitLines_keepsTrailingEmptyLine', 0, () => {
      const lines = TextFileCodec.splitLines('a\n')
      expect(lines.length).assertEqual(2)
      expect(lines[1]).assertEqual('')
    })
  })
}
