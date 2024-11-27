import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DialogHelper } from '@pura/harmony-dialog'
import { PreferencesUtil } from '@pura/harmony-utils';
import { USERPRIVDATA_NAME, WEBSITE_CURRENT_USER_KEY } from '../common/Common';
import UserPrivData from '../utils/UserPrivData'
import UserDatabase from '../utils/UserDatabase';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    DialogHelper.setDefaultConfig((config) => {
      config.uiContext = this.context
    })
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 初始化用户加密首选项
    UserPrivData.init(this.context, USERPRIVDATA_NAME)

    // 初始化用户信息数据库
    await UserDatabase.init(this.context)

    // 根据当前保存用户进行跳转页面
    let defaultPagePath: string = 'pages/LoginPage'
    let currentUser = UserPrivData.getSync(USERPRIVDATA_NAME, WEBSITE_CURRENT_USER_KEY);
    if (currentUser && currentUser !== '') {
      //UserDatabase.deleteUserInfo(currentUser as string) //调试使用
      if (UserDatabase.checkUserValid(currentUser as string) ) {
        defaultPagePath = 'pages/IndexPage'
      }
    }

    windowStage.loadContent(defaultPagePath, (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
