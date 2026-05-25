use log::{Level, LevelFilter, Log, Metadata, Record};
use std::ffi::CString;

const LOG_APP: i32 = 0;
const LOG_DEBUG: i32 = 3;
const LOG_INFO: i32 = 4;
const LOG_WARN: i32 = 5;
const LOG_ERROR: i32 = 6;
const DOMAIN: u32 = 0x0001;

#[cfg(target_env = "ohos")]
#[link(name = "hilog_ndk.z")]
extern "C" {
    // Declared without variadic `...`; we always pass exactly one `%s` arg.
    fn OH_LOG_Print(
        log_type: i32,
        level: i32,
        domain: u32,
        tag: *const u8,
        fmt: *const u8,
        arg: *const u8,
    ) -> i32;
}

struct HiLogger;

impl Log for HiLogger {
    fn enabled(&self, _: &Metadata) -> bool {
        true
    }

    fn log(&self, record: &Record) {
        let level = match record.level() {
            Level::Error => LOG_ERROR,
            Level::Warn => LOG_WARN,
            Level::Info => LOG_INFO,
            Level::Debug | Level::Trace => LOG_DEBUG,
        };
        let msg = format!("[{}] {}", record.target(), record.args());
        if let Ok(c_msg) = CString::new(msg) {
            #[cfg(target_env = "ohos")]
            unsafe {
                OH_LOG_Print(
                    LOG_APP,
                    level,
                    DOMAIN,
                    b"CloudreveNative\0".as_ptr(),
                    b"%{public}s\0".as_ptr(),
                    c_msg.as_ptr() as *const u8,
                );
            }
            #[cfg(not(target_env = "ohos"))]
            eprintln!("[CloudreveNative][{}] {}", record.level(), c_msg.to_string_lossy());
        }
    }

    fn flush(&self) {}
}

static LOGGER: HiLogger = HiLogger;

pub fn init() {
    let _ = log::set_logger(&LOGGER);
    log::set_max_level(LevelFilter::Debug);
}
