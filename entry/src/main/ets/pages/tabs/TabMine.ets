import { HMRouterMgr } from "@hadss/hmrouter";
import { UserStorage } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import UserDatabase from "../../model/UserDatabase";
import UserPreferences from "../../model/UserPreferences";
import { cloudUserStorage } from "../../model/net/Api";

@Component
export struct TabMine {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0;
  @State userStorage: UserStorage | null = null;
  @State currentUser: string = ''

  aboutToAppear() {
    this.currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY) as string

    cloudUserStorage({
      onSuccess: (data: UserStorage) => {
        this.userStorage = data
        let used:number = this.userStorage.used/(1024*1024*1024)
        let total:number = this.userStorage.total/(1024*1024*1024)
        console.debug('TabMine', `Storage: ${used.toFixed(2)}G/${total.toFixed(2)}G`)
      },
      onFailure: () => {

      }
    })
  }

  build() {
    Flex() {
      Column() {
        this.logoutBuilder()
      }
      .padding(20)
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  rowWithNext(icon: string|Resource, title: string|Resource) {
    Row() {
      Image(icon)

      Text(title)
    }
  }

  @Builder
  logoutBuilder() {
    Button() {
      Row({space: 10}) {
        Image($r('app.media.ic_square_logout'))
          .width(24)
          .height(24)
          .borderRadius(12)
          .fillColor(Color.Red)
          .objectFit(ImageFit.Cover)

        Text($r('app.string.logout'))
          .fontColor(Color.Red)
          .fontSize(16)
      }
      .width('100%')
      .height('100%')
    }
    .type(ButtonType.Normal)
    .width('100%')
    .height(40)
    .borderRadius(10)
    .backgroundColor($r('app.color.logout_background'))
    .padding({ left: 10, right: 15 })
    .onClick(() => {
      UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY)
      UserDatabase.deleteUserInfo(this.currentUser)
      HMRouterMgr.push({ pageUrl: Constant.LOGIN_PAGE })
    })
  }
}