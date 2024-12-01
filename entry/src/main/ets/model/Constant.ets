
/**
 * 通用常量类
 */
class Constant {
  USER_PREFERENCES = 'UserPreference'
  ACTIVE_USER_KEY = 'ActiveUser'
  REQUEST_TIMEOUT: number = 3000
  SYSTEM_TOP_RECT_HEIGHT: string = 'sysTopRectHeight'
  NAV_BOTTOM_RECT_HEIGHT: string = 'navBottomRectHeight'
  CLOUD_COOKIE: string = 'cloudCookie'
  CLOUD_COOKIE_EXPIRES: string = 'cloudCookieExpires'
  HOME_PAGE = 'HomePage'
  LOGIN_PAGE = 'LoginPage'
  ACCESS_INTERCEPTOR = 'AccessInterceptor'
}

const constant = new Constant();
export default constant as Constant;