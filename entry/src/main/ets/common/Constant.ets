
/**
 * 通用常量类
 */
class Constant {
  USER_PREFERENCES = 'UserPreference'
  ACTIVE_USER_KEY = 'ActiveUser'
  REQUEST_TIMEOUT: number = 3000
  STORAGE_TOP_RECT_HEIGHT: string = 'TopRectHeight'
  STORAGE_BOTTOM_RECT_HEIGHT: string = 'BottomRectHeight'
  HOME_PAGE = 'HomePage'
  LOGIN_PAGE = 'LoginPage'
  ACCESS_INTERCEPTOR = 'AccessInterceptor'
}

const constant = new Constant();
export default constant as Constant;