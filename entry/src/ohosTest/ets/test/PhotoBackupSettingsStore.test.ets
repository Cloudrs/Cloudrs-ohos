import { describe, it, expect } from '@ohos/hypium';
import { PhotoBackupSettingsStore } from '../../../../main/ets/model/PhotoBackupSettingsStore';

export default function photoBackupSettingsStoreTest() {
  describe('PhotoBackupSettingsStore', () => {
    it('normalizeConcurrent_clampsRange', 0, () => {
      expect(PhotoBackupSettingsStore.normalizeConcurrent(0)).assertEqual(1);
      expect(PhotoBackupSettingsStore.normalizeConcurrent(99)).assertEqual(10);
      expect(PhotoBackupSettingsStore.normalizeConcurrent(3)).assertEqual(3);
    });
    it('normalizeConcurrent_nanReturnsDefault', 0, () => {
      expect(PhotoBackupSettingsStore.normalizeConcurrent(NaN)).assertEqual(3);
    });
    it('normalizeConcurrent_floorsDecimal', 0, () => {
      expect(PhotoBackupSettingsStore.normalizeConcurrent(2.9)).assertEqual(2);
    });
    it('normalizeRemotePath_addsLeadingSlashAndTrimsTrailing', 0, () => {
      expect(PhotoBackupSettingsStore.normalizeRemotePath('Photos/Camera/')).assertEqual('/Photos/Camera');
      expect(PhotoBackupSettingsStore.normalizeRemotePath('')).assertEqual('/Photos/Camera');
    });
    it('normalizeRemotePath_rootSlashPreserved', 0, () => {
      expect(PhotoBackupSettingsStore.normalizeRemotePath('/')).assertEqual('/');
    });
    it('normalizeRemotePath_trimsMultipleTrailingSlashes', 0, () => {
      expect(PhotoBackupSettingsStore.normalizeRemotePath('Photos///')).assertEqual('/Photos');
    });
  });
}
