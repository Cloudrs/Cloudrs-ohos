import { describe, it, expect } from '@ohos/hypium';
import { PhotoBadge, badgeForStatus, GallerySegment,
  groupByDate, groupByAlbum, PhotoGroup, justifyRows, JustifiedRow } from '../../../main/ets/model/PhotoGalleryModel';
import { PhotoBackupStatus, PhotoBackupItem } from '../../../main/ets/model/PhotoBackupModel';

export default function photoGalleryModelTest() {
  describe('PhotoGalleryModel', () => {
    it('completed_alwaysCloud_evenWhenDisabled', 0, () => {
      expect(badgeForStatus(PhotoBackupStatus.COMPLETED, true)).assertEqual(PhotoBadge.CLOUD);
      expect(badgeForStatus(PhotoBackupStatus.COMPLETED, false)).assertEqual(PhotoBadge.CLOUD);
    });
    it('uploading_failed_onlyWhenEnabled', 0, () => {
      expect(badgeForStatus(PhotoBackupStatus.UPLOADING, true)).assertEqual(PhotoBadge.UPLOADING);
      expect(badgeForStatus(PhotoBackupStatus.FAILED, true)).assertEqual(PhotoBadge.FAILED);
      expect(badgeForStatus(PhotoBackupStatus.UPLOADING, false)).assertEqual(PhotoBadge.NONE);
      expect(badgeForStatus(PhotoBackupStatus.FAILED, false)).assertEqual(PhotoBadge.NONE);
    });
    it('waiting_neverShowsBadge', 0, () => {
      expect(badgeForStatus(PhotoBackupStatus.WAITING, true)).assertEqual(PhotoBadge.NONE);
    });
    it('segmentEnum_hasTwoDimensions', 0, () => {
      expect(GallerySegment.TIME).assertEqual(0);
      expect(GallerySegment.ALBUM).assertEqual(1);
    });
    it('groupByAlbum_groupsAndPreservesOrder', 0, () => {
      const a = new PhotoBackupItem('u1', 'a.jpg', 1, 100); a.albumName = '相机';
      const b = new PhotoBackupItem('u2', 'b.jpg', 1, 200); b.albumName = '截图';
      const c = new PhotoBackupItem('u3', 'c.jpg', 1, 300); c.albumName = '相机';
      const groups: PhotoGroup[] = groupByAlbum([a, b, c]);
      expect(groups.length).assertEqual(2);
      expect(groups[0].title).assertEqual('相机');
      expect(groups[0].items.length).assertEqual(2);
    });
    it('groupByDate_sameDaySameGroup', 0, () => {
      const day = new Date(2024, 4, 24, 9, 0, 0).getTime();
      const day2 = new Date(2024, 4, 24, 20, 0, 0).getTime();
      const x = new PhotoBackupItem('u1', 'a.jpg', 1, day);
      const y = new PhotoBackupItem('u2', 'b.jpg', 1, day2);
      const groups: PhotoGroup[] = groupByDate([x, y], new Date(2024, 4, 25));
      expect(groups.length).assertEqual(1);
      expect(groups[0].items.length).assertEqual(2);
    });
    it('justifyRows_fillsContainerWidth', 0, () => {
      const rows: JustifiedRow[] = justifyRows([1, 1, 1], 300, 100, 0);
      expect(rows.length).assertEqual(1);
      expect(Math.round(rows[0].height)).assertEqual(100);
      expect(Math.round(rows[0].widths[0])).assertEqual(100);
    });
    it('justifyRows_wrapsWhenExceedTarget', 0, () => {
      const rows: JustifiedRow[] = justifyRows([1, 1, 1, 1], 300, 100, 0);
      expect(rows.length).assertEqual(2);
    });
  });
}
