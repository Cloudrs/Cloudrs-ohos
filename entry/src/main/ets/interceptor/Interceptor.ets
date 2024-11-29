import { HMInterceptor, HMInterceptorAction, HMInterceptorInfo, HMRouterMgr, IHMInterceptor } from "@hadss/hmrouter";
import { DbUserInfo } from "../common/ApiTypes";
import Constant from "../common/Constant";
import { LoginParam } from "../model/LoginParam";
import UserDatabase from "../model/UserDatabase";
import UserPreferences from "../model/UserPreferences";
import { baseUrlSet, cookieSet } from "../utils/AxiosRequest";

@HMInterceptor({ interceptorName: Constant.ACCESS_INTERCEPTOR, global: false })
export class LoginInterceptor implements IHMInterceptor {
  handle(info: HMInterceptorInfo): HMInterceptorAction {
    let dbUserInfo: DbUserInfo|null = null
    let connectionInfo: string = info.type === 'push' ? 'jump to' : 'back to'

    console.log('Interceptor', `${info.srcName} ${connectionInfo} ${info.targetName}`)

    // 目标为非登录页面时需先判断是否已登录
    if (info.targetName !== Constant.LOGIN_PAGE) {
      let currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY) as string ?? ''
      if (currentUser !== '') {
        dbUserInfo = UserDatabase.getUserInfo(currentUser)
        if (dbUserInfo) {
          console.debug('Interceptor', `获取用户信息成功，url:${dbUserInfo.url}, cookie:${dbUserInfo.cookie}`)

          //TODO: 判断cookie是否过期，暂时写死不过期
          if (true) {
            baseUrlSet(dbUserInfo.url)
            cookieSet(dbUserInfo.cookie)
            return HMInterceptorAction.DO_NEXT;
          }
        }
      }

      let loginParam = new LoginParam(false, info.targetName)
      HMRouterMgr.push({ pageUrl: Constant.LOGIN_PAGE, param: loginParam })
      return HMInterceptorAction.DO_REJECT
    }

    return HMInterceptorAction.DO_NEXT
  }
}