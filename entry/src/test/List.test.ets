import localUnitTest from './LocalUnit.test';
import settingsRulesTest from './SettingsRules.test';
import loginHistoryRulesTest from './LoginHistoryRules.test';
import archiveRulesTest from './ArchiveRules.test';

export default function testsuite() {
  localUnitTest();
  settingsRulesTest();
  loginHistoryRulesTest();
  archiveRulesTest();
}
