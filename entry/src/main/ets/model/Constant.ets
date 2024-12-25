
/**
 * 通用常量类
 */
class Constant {
  USER_PREFERENCES = 'UserPreference'

  ACTIVE_USER_KEY = 'ActiveUser'

  REQUEST_TIMEOUT: number = 5000

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

  TOAST_BOTTOM: number = 135;

  UPLOAD_TOKEN: string = 'upload_token';

  TASK_MAX: number = 5;

  TASK_PAUSE_MSG: number = -1;

  TASK_RESUME_MSG: number = -2;

  TASK_NET_PAUSE_MSG: number = -3;

  TASK_NET_RESUME_MSG: number = -4;
}

const constant = new Constant();
export default constant as Constant;