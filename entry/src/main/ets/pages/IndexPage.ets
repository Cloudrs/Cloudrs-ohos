import { CLOUDREVE_USER_STORAGE } from '../common/Common';
import { DbUserInfo, UserStorage } from '../types/ApiTypes';
import { baseUrlSet, cloudGet, cloudPost, cookieSet } from '../utils/AxiosRequest';
import { CLOUDREVE_CONFIG, CLOUDREVE_LOGIN, CLOUDREVE_PING, USERPRIVDATA_NAME,
  WEBSITE_CURRENT_USER_KEY} from '../common/Common';
import UserPrivData from '../utils/UserPrivData';
import UserDatabase from '../utils/UserDatabase';

@Entry
@Component
struct IndexPage {

  async aboutToAppear(): Promise<void> {
    let currentUser = UserPrivData.getSync(USERPRIVDATA_NAME, WEBSITE_CURRENT_USER_KEY);
    if (currentUser) {
      if (currentUser !== '') {
        let dbUserInfo:DbUserInfo|null = UserDatabase.getUserInfo(currentUser as string)
        if (dbUserInfo) {
          console.debug('IndexPage', `获取用户信息成功，url:${dbUserInfo.url}, cookie:${dbUserInfo.cookie}`)
          baseUrlSet(dbUserInfo.url)
          cookieSet(dbUserInfo.cookie)
        }
      }
    } else {
      // TODO：跳转到登录页

    }

    let userStorage: UserStorage | null = await cloudGet(CLOUDREVE_USER_STORAGE)
    if (userStorage) {
      let used:number = userStorage.used/1024*1024*1024
      let total:number = userStorage.total/1024*1024*1024
      console.debug('IndexPage', `Storage: ${used.toFixed(2)}G/${total.toFixed(2)}G`)
    }
  }

  build() {
    Column() {
      Navigation() {

      }
      .toolbarConfiguration([
        {
          value: $r("app.string.navigation_toolbar_files"),
          icon: $r("app.media.ic_cloud_fill")
        },
        {
          value: $r("app.string.navigation_toolbar_photos"),
          icon: $r("app.media.ic_picture_fill")
        },
        {
          value: $r("app.string.navigation_toolbar_remote_download"),
          icon: $r("app.media.ic_remote_download")
        },
        {
          value: $r("app.string.navigation_toolbar_me"),
          icon: $r("app.media.ic_me")
        }
      ])
    }
    .padding(10)
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
