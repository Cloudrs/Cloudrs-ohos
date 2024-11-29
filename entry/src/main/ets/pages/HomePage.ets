import { DbUserInfo, DirectoryInfo, ObjectInfo, Policy, SiteConfig, SiteURI, UserStorage } from '../common/ApiTypes';
import { baseUrlSet, cloudGet, cloudPost, cookieSet } from '../utils/AxiosRequest';
import Constant from '../common/Constant';
import UserPrivData from '../model/UserPreferences';
import UserDatabase from '../model/UserDatabase';
import { HMRouter } from '@hadss/hmrouter';

@HMRouter({pageUrl: Constant.HOME_PAGE, interceptors: [Constant.ACCESS_INTERCEPTOR]})
@Component
export struct HomePage {
  @StorageProp(Constant.STORAGE_TOP_RECT_HEIGHT)
  topRectHeight: number = 0;
  @StorageProp(Constant.STORAGE_BOTTOM_RECT_HEIGHT)
  bottomRectHeight: number = 0;

  @State selectIndex:number = 0;
  @State objects: ObjectInfo[] = [];
  private titleHeight: number = 100 + this.topRectHeight;
  private toolBarHeight: number = 80;
  private policy?: Policy;
  private siteConfig?: SiteConfig;

  async aboutToAppear(): Promise<void> {
    let currentUser = UserPrivData.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY);
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

    let config: SiteConfig | null = await cloudGet(SiteURI.CONFIG)
    if (config) {
      this.siteConfig = config
      if (config.user.status !== 0) {
        // TODO: 重新登录
      }
    }

    let userStorage: UserStorage | null = await cloudGet(SiteURI.USER_STORAGE)
    if (userStorage) {
      let used:number = userStorage.used/(1024*1024*1024)
      let total:number = userStorage.total/(1024*1024*1024)
      console.debug('IndexPage', `Storage: ${used.toFixed(2)}G/${total.toFixed(2)}G`)
    }

    let dirInfo: DirectoryInfo | null = await cloudGet(SiteURI.LIST_DIR + '/')
    if (dirInfo) {
      this.objects = dirInfo.objects
      this.policy = dirInfo.policy
      console.debug('IndexPage', `Objects: ` + JSON.stringify(this.objects))
    }
  }

  build() {
    Column() {
      Navigation() {
        Flex() {
          List({ space: 10 }) {
            ForEach(this.objects, (item: ObjectInfo, index) => {
              ListItem() {
                Button(item.name)
                  .width(150)
                  .fontColor(Color.Black)
                  .backgroundColor(Color.White)
                  .borderRadius(1)
                  .borderColor($r('app.color.light_light_gray'))
                  .onClick(async () => {
                    let dirInfo: DirectoryInfo | null = await cloudGet(SiteURI.LIST_DIR + item.path + item.name)
                    if (dirInfo) {
                      console.debug('IndexPage', `${item.path}${item.name}: ` + JSON.stringify(dirInfo.objects))
                    }
                  })
              }
            })
          }
          .alignListItem(ListItemAlign.Start)
        }
        .layoutWeight(1)
        // .backgroundColor(Color.Red)
      }
      .title({builder: this.titleBarBuilder('存储', '默认存储策略'), height: this.titleHeight})
      .toolbarConfiguration(this.toolBarBuilder())
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.nav_background'))
  }

  @Builder
  titleBarBuilder(main: string, sub?: string) {
    Column({space: 10}) {
      this.headerBuilder()

      Row() {
        Column() {
          Text(main)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)

          Text(sub)
            .fontSize(9)
        }
        .height(30)
        .justifyContent(FlexAlign.SpaceBetween)

        Button() {
          Text('...')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
        }
        .backgroundColor($r('app.color.light_light_gray'))
        .width(30)
        .height(30)
      }
      .padding(10)
      .width('100%')
      .height(40)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .height('100%')
    .padding({top: this.topRectHeight})
    // .backgroundColor(Color.Blue)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  headerBuilder() {
    Row() {
      Search({placeholder: $r('app.string.navigation_menu_search')})
        .height(36)
        .width('60%')
        .searchIcon({color: Color.Black})

      Row({space: 5}) {
        Button() {
          Image($r('app.media.ic_transport'))
            .height(30)
            .padding(5)
            .fillColor(Color.Black)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.light_light_gray'))

        Button() {
          Image($r('app.media.ic_person'))
            .height(30)
            .padding(5)
            .fillColor(Color.Black)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.light_light_gray'))
      }
    }
    .padding({left: 10, right: 10, top: 10})
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.SpaceBetween)
    // .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)
  }

  @Builder
  toolBarBuilder() {
    Row() {
      Column({space: 2}) {
        Image($r("app.media.ic_cloud_fill"))
          .width(20)
          .fillColor($r('app.color.nav_toolbar_default'))
        Text($r("app.string.navigation_toolbar_files"))
          .fontSize(12)
          .fontColor($r('app.color.nav_toolbar_default'))
      }
      .onClick(() => {

      })

      Column({space: 2}) {
        Image($r("app.media.ic_picture_fill"))
          .width(20)
          .fillColor($r('app.color.nav_toolbar_default'))
        Text($r("app.string.navigation_toolbar_photos"))
          .fontSize(12)
          .fontColor($r('app.color.nav_toolbar_default'))
      }

      Column({space: 2}) {
        Image($r("app.media.ic_remote_download"))
          .width(20)
          .fillColor($r('app.color.nav_toolbar_default'))
        Text($r("app.string.navigation_toolbar_remote_download"))
          .fontSize(12)
          .fontColor($r('app.color.nav_toolbar_default'))
      }

      Column({space: 2}) {
        Image($r("app.media.ic_me"))
          .width(20)
          .fillColor($r('app.color.nav_toolbar_default'))
        Text($r("app.string.navigation_toolbar_me"))
          .fontSize(12)
          .fontColor($r('app.color.nav_toolbar_default'))
      }
    }
    .padding({bottom: this.bottomRectHeight})
    // .backgroundColor($r('app.color.nav_toolbar_background'))
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .width('100%')
    .height(this.toolBarHeight)
    .justifyContent(FlexAlign.SpaceAround)
  }
}
