import localUnitTest from './LocalUnit.test';
import settingsRulesTest from './SettingsRules.test';
import loginHistoryRulesTest from './LoginHistoryRules.test';

export default function testsuite() {
  localUnitTest();
  settingsRulesTest();
  loginHistoryRulesTest();
}
