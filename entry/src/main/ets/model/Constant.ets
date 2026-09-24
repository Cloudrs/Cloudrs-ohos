
/**
 * 通用常量类
 */
class Constant {
  APP_DISPLAY_NAME = 'Cloudrs'

  USER_PREFERENCES = 'UserPreference'

  ACTIVE_USER_KEY = 'ActiveUser'

  ACTIVE_USER_URL_KEY = 'ActiveUserUrl'

  /** AppStorage：当前账号作用域(url|username)，账号切换的广播信号 */
  ACTIVE_ACCOUNT_SCOPE: string = 'activeAccountScope'

  REQUEST_TIMEOUT: number = 5000

  HTTP_STATUS_OK: number = 200

  SCAN_CANCEL_CODE: number = 1000500002

  PRIVACY_POLICY_URL: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1579234134935491520'

  IMAGE_PREVIEW_MAX_DOWNLOAD_BYTES: number = 100 * 1024 * 1024

  // 文本预览走全量渲染，没有虚拟化的文本控件兜底，超过该大小不给入口
  TEXT_PREVIEW_MAX_BYTES: number = 2 * 1024 * 1024

  TEXT_EDITOR_FONT_SIZE: string = 'text_editor_font_size'
  TEXT_EDITOR_LINE_WRAP: string = 'text_editor_line_wrap'
  TEXT_EDITOR_FONT_SIZE_DEFAULT: number = 15
  TEXT_EDITOR_FONT_SIZE_MIN: number = 11
  TEXT_EDITOR_FONT_SIZE_MAX: number = 24
  TEXT_EDITOR_FONT_SIZE_STEP: number = 1

  FILE_SEARCH_HISTORY: string = 'file_search_history'

  BACKGROUND_TASK_FLUSH_INTERVAL_MS: number = 2000

  TRANSFER_PERSIST_INTERVAL_MS: number = 2000

  /**
   * 传输进度刷新到 UI 的最小间隔。
   * 上传的进度回调来自 native，是按字节步长（每 4MB）触发的，网速快时一秒能来十几次，
   * 百分比和字节数会跳得很碎。下载那边由 request.agent 按时间节奏回调，大约一秒一次，
   * 这里对齐它，让两个列表的观感一致；顺带让速度值变成稳定的一秒均值。
   */
  TRANSFER_PROGRESS_UI_INTERVAL_MS: number = 1000

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

  // Cloudreve v4 离线下载任务真正挂在下载器上的阶段，只有这个阶段服务端才接受取消
  ARIA2_PHASE_MONITOR: string = 'monitor'

  // native 在「服务端说这个任务已经不在跑了」时给错误串打的前缀
  ARIA2_CANCEL_ERR_NOT_RUNNING: string = 'TASK_NOT_RUNNING'

  TOAST_DEFAULT_DURATION_MS: number = 1500

  // 含路径等较长内容的提示用 3 秒，给用户留够阅读时间
  TOAST_LONG_DURATION_MS: number = 3000

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

  /**
   * 凭证有效期的兜底值，只在拿不到服务端真值时用。
   * v4 登录会返回 refresh token 的真实到期时间，走不到这里；
   * v3 只有 session，Cloudreve 默认就是 7 天，估得比实际长会让过期凭证看起来还能用。
   */
  CLOUD_COOKIE_EXPIRE_DAYS: number = 7

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

  // 视频播放出错时自动换新直链重试的最大次数
  VIDEO_PLAY_MAX_AUTO_RETRY: number = 2

  // Video 挂载后超过该时长仍未 onPrepared 视为失败，不陪系统等 30s 超时
  VIDEO_PREPARE_TIMEOUT_MS: number = 15000

  /** 本地续播记录表，整表一个 JSON 数组存在 USER_PREFERENCES 下 */
  VIDEO_PROGRESS_KEY: string = 'VideoPlayProgress'

  // 片头片尾各留这么大比例的"不记录区"：开头没看几眼的不记，接近看完的清掉。
  // 按比例而非绝对秒数，才能同时伺候十几秒的短片和几十分钟的长片
  VIDEO_PROGRESS_EDGE_RATIO: number = 0.05

  // 不记录区的绝对下限。短片按 5% 算出来只有零点几秒，等于没有门槛；
  // 同时这条下限天然排除了 10 秒以内的视频——它的可记录区间是空的
  VIDEO_PROGRESS_EDGE_MIN_SECONDS: number = 5

  // 续播表上限，超出按最后播放时间 LRU 裁剪
  VIDEO_PROGRESS_MAX_RECORDS: number = 200

  // 播放中定期回写进度的心跳间隔，防进程被系统回收后丢记录
  VIDEO_PROGRESS_SAVE_INTERVAL_MS: number = 30000

  // 续播浮条自动消失时长
  VIDEO_RESUME_BANNER_DURATION_MS: number = 4000

  FIRST_ARRAY_INDEX: number = 0

  SYSTEM_TOP_RECT_HEIGHT: string = 'sysTopRectHeight'

  APP_VERSION: string = 'appVersion'

  NAV_BOTTOM_RECT_HEIGHT: string = 'navBottomRectHeight'

  KEYBOARD_HEIGHT_VP: string = 'keyboardHeightVp'

  TAB_BAR_HEIGHT: string = 'tabBarHeight'

  WINDOW_WIDTH_VP: string = 'windowWidthVp'

  WINDOW_HEIGHT_VP: string = 'windowHeightVp'

  LAYOUT_MODE: string = 'layoutMode'

  SIDEBAR_VISIBLE: string = 'sidebarVisible'
  // 2in1 隐藏标题栏后，右上角窗口三键区占用的宽度（vp，含距右边缘距离）；非 2in1 恒为 0
  TITLE_BUTTON_INSET_END: string = 'titleButtonInsetEnd'
  // 2in1 主窗口状态（window.WindowStatusType），自绘窗口三键据此切换最大化/还原、全屏时隐藏
  WINDOW_STATUS: string = 'windowStatus'
  // 2in1 系统三键已隐藏、改由应用自绘（WindowControls）
  WINDOW_CONTROLS_CUSTOM: string = 'windowControlsCustom'

  CLOUD_BASE_URL: string = 'cloudBaseUrl'

  CLOUD_COOKIE: string = 'cloudCookie'

  CLOUD_COOKIE_EXPIRES: string = 'cloudCookieExpires'

  CLOUD_REFRESH_TOKEN: string = 'cloudRefreshToken'

  HOME_PAGE = 'HomePage'

  LOGIN_PAGE = 'LoginPage'

  IAMGE_PREVIEW_PAGE = 'ImagePreviewPage'

  VIDEO_PREVIEW_PAGE = 'VideoPreviewPage'

  TEXT_PREVIEW_PAGE = 'TextPreviewPage'

  FILE_SEARCH_PAGE = 'FileSearchPage'

  ABOUT_PAGE = 'AboutPage'

  PHOTO_LOCAL_PREVIEW_PAGE = 'PhotoLocalPreviewPage'

  ACCESS_INTERCEPTOR = 'AccessInterceptor'

  CURRENT_PATH = 'currentPath'

  CURRENT_SORT_TYPE = 'sortType'

  CURRENT_SORT_TYPE_RESERVE = 'sortTypeReverse'

  /** 默认排序改为"时间倒序"的一次性迁移标记；已存在说明迁移过，不再覆盖用户后来的选择 */
  SORT_DEFAULT_TIME_DESC_APPLIED = 'sortDefaultTimeDescApplied'

  CURRENT_SHOW_TYPE = 'showType'

  PHOTO_BACKUP_SETTINGS = 'photoBackupSettings'

  PHOTO_BACKUP_DONE_IDS = 'photoBackupDoneIds'

  PHOTO_BACKUP_ITEMS = 'photoBackupItems'

  PHOTO_BACKUP_SESSIONS = 'photoBackupSessions'

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
  IMAGE_DRAGGABLE_ENABLED: string = 'image_draggable_enabled';
  IMAGE_AI_ANALYZER_ENABLED: string = 'image_ai_analyzer_enabled';

  APP_THEME_LIGHT: string = 'light';

  APP_THEME_DARK: string = 'dark';

  PRIVACY_SYSTEM_AUTH_ENABLED: string = 'privacy_system_auth_enabled';

  KNOCK_SHARE_USE_SHARE_LINK: string = 'knock_share_use_share_link';
  KNOCK_SHARE_EXPIRE_DAYS: string = 'knock_share_expire_days';
  KNOCK_SHARE_PASSWORD_ENABLED: string = 'knock_share_password_enabled';

  APP_FOREGROUND_TICK: string = 'appForegroundTick';

  APP_LOCKED: string = 'appLocked';

  SYSTEM_BAR_TRANSPARENT_COLOR: string = '#00000000';

  SYSTEM_BAR_DARK_CONTENT_COLOR: string = '#FF182030';

  SYSTEM_BAR_LIGHT_CONTENT_COLOR: string = '#FFFFFFFF';

  SYSTEM_BAR_ANIMATION_ENABLED: boolean = false;
}

const constant = new Constant();
export default constant as Constant;
