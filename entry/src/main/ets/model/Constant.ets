
/**
 * 通用常量类
 */
class Constant {
  USER_PREFERENCES = 'UserPreference'

  ACTIVE_USER_KEY = 'ActiveUser'

  ACTIVE_USER_URL_KEY = 'ActiveUserUrl'

  REQUEST_TIMEOUT: number = 5000

  HTTP_STATUS_OK: number = 200

  SCAN_CANCEL_CODE: number = 1000500002

  IMAGE_PREVIEW_MAX_DOWNLOAD_BYTES: number = 100 * 1024 * 1024

  BACKGROUND_TASK_FLUSH_INTERVAL_MS: number = 2000

  TRANSFER_PERSIST_INTERVAL_MS: number = 2000

  BACKGROUND_TASK_COMPLETE_PERCENT: number = 100

  BACKGROUND_TASK_EMPTY_SIZE: number = 0

  TASK_FAULTS_NONE: number = 0

  PERMISSION_AUTH_GRANTED: number = 0

  STORAGE_POLICY_LOCAL: string = 'local'

  STORAGE_POLICY_REMOTE: string = 'remote'

  REMOTE_NODE_UPLOAD_URL_COUNT: number = 1

  REQUEST_METHOD_GET: string = 'GET'

  REQUEST_METHOD_POST: string = 'POST'

  REQUEST_TITLE_UPLOAD: string = 'upload'

  REQUEST_TITLE_DOWNLOAD: string = 'download'

  REQUEST_SAVE_AS_PREFIX: string = './'

  REQUEST_GAUGE_ENABLED: boolean = true

  REQUEST_OVERWRITE_ENABLED: boolean = true

  EXIT_BACK_PRESS_INTERVAL_MS: number = 1000

  MILLISECONDS_PER_SECOND: number = 1000

  ARIA2_MIN_UPDATE_INTERVAL_SECONDS: number = 3

  TOAST_DEFAULT_DURATION_MS: number = 1500

  TOAST_TIPS_DEFAULT_DURATION_MS: number = 3000

  LOGIN_RESULT_USER_INDEX: number = 0

  LOGIN_RESULT_TOKEN_INDEX: number = 1

  LOGIN_RESULT_REFRESH_TOKEN_INDEX: number = 2

  LOGIN_RESULT_VERSION_INDEX: number = 3

  LOGIN_RESULT_REFRESH_EXPIRES_INDEX: number = 4

  LOGIN_TWO_FACTOR_REQUIRED: string = '2fa_required'

  CLOUD_VERSION_V3: string = 'v3'

  CLOUD_V3_COOKIE_PREFIX: string = 'cloudreve-session='

  CLOUD_V4_COOKIE_PREFIX: string = 'v4:'

  CLOUD_COOKIE_EXPIRE_DAYS: number = 30

  PROTOCOL_HTTPS_INDEX: number = 0

  PROTOCOL_HTTP_INDEX: number = 1

  PROTOCOL_HTTPS_LABEL: string = 'https'

  PROTOCOL_HTTP_LABEL: string = 'http'

  PROTOCOL_HTTPS_SCHEME: string = 'https://'

  PROTOCOL_HTTP_SCHEME: string = 'http://'

  SECONDS_PER_MINUTE: number = 60

  MINUTES_PER_HOUR: number = 60

  HOURS_PER_DAY: number = 24

  BYTE_UNIT_SIZE: number = 1024

  FILE_COPY_CHUNK_SIZE: number = 128 * 1024

  FILE_COPY_YIELD_DELAY_MS: number = 1

  DATE_PAD_THRESHOLD: number = 10

  VIDEO_HOLD_SEEK_STEP_SECONDS: number = 2

  VIDEO_HOLD_SEEK_INTERVAL_MS: number = 300

  VIDEO_HOLD_FAST_PLAY_SPEED: number = 2

  VIDEO_NORMAL_PLAY_SPEED: number = 1

  VIDEO_SEEK_SYNC_TOLERANCE_SECONDS: number = 2

  VIDEO_SEEK_SYNC_MAX_IGNORED: number = 10

  FIRST_ARRAY_INDEX: number = 0

  SYSTEM_TOP_RECT_HEIGHT: string = 'sysTopRectHeight'

  APP_VERSION: string = 'appVersion'

  NAV_BOTTOM_RECT_HEIGHT: string = 'navBottomRectHeight'

  TAB_BAR_HEIGHT: string = 'tabBarHeight'

  WINDOW_WIDTH_VP: string = 'windowWidthVp'

  WINDOW_HEIGHT_VP: string = 'windowHeightVp'

  LAYOUT_MODE: string = 'layoutMode'

  SIDEBAR_VISIBLE: string = 'sidebarVisible'

  CLOUD_BASE_URL: string = 'cloudBaseUrl'

  CLOUD_COOKIE: string = 'cloudCookie'

  CLOUD_COOKIE_EXPIRES: string = 'cloudCookieExpires'

  CLOUD_REFRESH_TOKEN: string = 'cloudRefreshToken'

  HOME_PAGE = 'HomePage'

  LOGIN_PAGE = 'LoginPage'

  IAMGE_PREVIEW_PAGE = 'ImagePreviewPage'

  VIDEO_PREVIEW_PAGE = 'VideoPreviewPage'

  FILE_SEARCH_PAGE = 'FileSearchPage'

  ABOUT_PAGE = 'AboutPage'

  PHOTO_LOCAL_PREVIEW_PAGE = 'PhotoLocalPreviewPage'

  ACCESS_INTERCEPTOR = 'AccessInterceptor'

  CURRENT_PATH = 'currentPath'

  CURRENT_SORT_TYPE = 'sortType'

  CURRENT_SORT_TYPE_RESERVE = 'sortTypeReverse'

  CURRENT_SHOW_TYPE = 'showType'

  PHOTO_BACKUP_SETTINGS = 'photoBackupSettings'

  PHOTO_BACKUP_DONE_IDS = 'photoBackupDoneIds'

  PHOTO_BACKUP_ITEMS = 'photoBackupItems'

  OBJECT_DIR_TYPE = 'dir'

  OBJECT_FILE_TYPE = 'file'

  TOAST_BOTTOM: number = 135;

  UPLOAD_TOKEN: string = 'upload_token';

  TASK_MAX: number = 5;

  TASK_PAUSE_MSG: number = -1;

  TASK_RESUME_MSG: number = -2;

  TASK_NET_PAUSE_MSG: number = -3;

  TASK_NET_RESUME_MSG: number = -4;

  UPLOAD_MAX_CONCURRENT: string = 'upload_max_concurrent';

  UPLOAD_CONCURRENT_MIN: number = 1;

  UPLOAD_CONCURRENT_DEFAULT: number = 3;

  UPLOAD_CONCURRENT_MAX: number = 10;

  APP_THEME_MODE: string = 'app_theme_mode';

  APP_THEME_LIGHT: string = 'light';

  APP_THEME_DARK: string = 'dark';

  PRIVACY_SYSTEM_AUTH_ENABLED: string = 'privacy_system_auth_enabled';

  APP_FOREGROUND_TICK: string = 'appForegroundTick';

  APP_LOCKED: string = 'appLocked';

  SYSTEM_BAR_TRANSPARENT_COLOR: string = '#00000000';

  SYSTEM_BAR_DARK_CONTENT_COLOR: string = '#FF182030';

  SYSTEM_BAR_LIGHT_CONTENT_COLOR: string = '#FFFFFFFF';

  SYSTEM_BAR_ANIMATION_ENABLED: boolean = false;
}

const constant = new Constant();
export default constant as Constant;
