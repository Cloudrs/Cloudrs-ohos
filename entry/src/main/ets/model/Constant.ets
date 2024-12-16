
/**
 * 通用常量类
 */
class Constant {
  USER_PREFERENCES = 'UserPreference'
  ACTIVE_USER_KEY = 'ActiveUser'
  REQUEST_TIMEOUT: number = 3000
  SYSTEM_TOP_RECT_HEIGHT: string = 'sysTopRectHeight'
  APP_VERSION: string = 'appVersion'
  NAV_BOTTOM_RECT_HEIGHT: string = 'navBottomRectHeight'
  TAB_BAR_HEIGHT: string = 'tabBarHeight'
  CLOUD_COOKIE: string = 'cloudCookie'
  CLOUD_COOKIE_EXPIRES: string = 'cloudCookieExpires'
  HOME_PAGE = 'HomePage'
  LOGIN_PAGE = 'LoginPage'
  IAMGE_PREVIEW_PAGE = 'ImagePreviewPage'
  ABOUT_PAGE = 'AboutPage'
  ACCESS_INTERCEPTOR = 'AccessInterceptor'
  CURRENT_PATH = 'currentPath'
  CURRENT_SORT_TYPE = 'sortType'
  CURRENT_SORT_TYPE_RESERVE = 'sortTypeReverse'
  CURRENT_SHOW_TYPE = 'showType'
  OBJECT_DIR_TYPE = 'dir'
  OBJECT_FILE_TYPE = 'file'
}

const constant = new Constant();
export default constant as Constant;