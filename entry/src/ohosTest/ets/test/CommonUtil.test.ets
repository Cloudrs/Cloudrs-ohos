import { describe, it, expect } from '@ohos/hypium'
import { CommonUtil } from '../../../main/ets/utils/CommonUtil'

export default function commonUtilTest() {
  describe('CommonUtil_album', () => {
    it('sanitize_stripsExtension', 0, () => {
      expect(CommonUtil.sanitizeAlbumTitle('photo.jpg')).assertEqual('photo')
    })
    it('sanitize_removesIllegalChars', 0, () => {
      expect(CommonUtil.sanitizeAlbumTitle('a/b:c*?.png')).assertEqual('abc')
    })
    it('sanitize_emptyFallback', 0, () => {
      expect(CommonUtil.sanitizeAlbumTitle('.jpg')).assertEqual('image')
      expect(CommonUtil.sanitizeAlbumTitle('')).assertEqual('image')
    })
    it('sanitize_truncates255', 0, () => {
      const long = 'a'.repeat(300) + '.jpg'
      expect(CommonUtil.sanitizeAlbumTitle(long).length).assertEqual(255)
    })
    it('isAllImages_trueWhenAllImages', 0, () => {
      expect(CommonUtil.isAllImages(['a.jpg', 'b.png'])).assertTrue()
    })
    it('isAllImages_falseWhenMixedOrEmpty', 0, () => {
      expect(CommonUtil.isAllImages(['a.jpg', 'c.pdf'])).assertFalse()
      expect(CommonUtil.isAllImages([])).assertFalse()
    })
  })
}
