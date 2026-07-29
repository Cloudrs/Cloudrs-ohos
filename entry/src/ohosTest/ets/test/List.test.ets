import abilityTest from './Ability.test';
import photoBackupSettingsStoreTest from './PhotoBackupSettingsStore.test';
import photoGalleryModelTest from './PhotoGalleryModel.test';
import commonUtilTest from './CommonUtil.test';
import textFileCodecTest from './TextFileCodec.test';

export default function testsuite() {
  abilityTest();
  photoBackupSettingsStoreTest();
  photoGalleryModelTest();
  commonUtilTest();
  textFileCodecTest();
}
