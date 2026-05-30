import { HMInterceptor, HMInterceptorAction, HMInterceptorInfo, HMRouterMgr, IHMInterceptor } from "@hadss/hmrouter";
import { DbUserInfo } from "../model/net/ApiTypes";
import Constant from "../model/Constant";
import { LoginParam } from "../model/net/LoginParam";
import UserDatabase from "../model/UserDatabase";
import UserPreferences from "../model/UserPreferences";
import { CloudApi } from "../model/net/CloudApi";
import { showToastTips, ToastType } from "../utils/ToastUtil";

@HMInterceptor({ interceptorName: Constant.ACCESS_INTERCEPTOR, global: false })
export class LoginInterceptor implements IHMInterceptor {
  handle(info: HMInterceptorInfo): HMInterceptorAction {
    let dbUserInfo: DbUserInfo|null = null
    let connectionInfo: string = info.type === 'push' ? 'jump to' : 'back to'

    console.log('Interceptor', `${info.srcName} ${connectionInfo} ${info.targetName}`)

    if (info.targetName !== Constant.LOGIN_PAGE) {
      let currentUser = UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY) as string ?? ''
      if (currentUser !== '') {
        dbUserInfo = UserDatabase.getUserInfo(currentUser)
        if (dbUserInfo) {
          console.debug('Interceptor', `获取用户信息成功，url:${dbUserInfo.url}, expires:${dbUserInfo.expires}`)
          let expiresDate = new Date(dbUserInfo.expires)
          let now = new Date()
          if (now < expiresDate) {
            const cookie = dbUserInfo.cookie;
            const isV3 = !cookie.startsWith(Constant.CLOUD_V4_COOKIE_PREFIX);
            const token = isV3 ? cookie : cookie.slice(Constant.CLOUD_V4_COOKIE_PREFIX.length);
            const refreshToken = dbUserInfo.refresh_token ?? '';
            CloudApi.restoreSession(dbUserInfo.url, token, refreshToken, isV3);
            return HMInterceptorAction.DO_NEXT;
          }
          else {
            showToastTips('登录信息过期，重新登录!', ToastType.Warn)
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
