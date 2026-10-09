import localUnitTest from './LocalUnit.test';
import settingsRulesTest from './SettingsRules.test';

export default function testsuite() {
  localUnitTest();
  settingsRulesTest();
}
