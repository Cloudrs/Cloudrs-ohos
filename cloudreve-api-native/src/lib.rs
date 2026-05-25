#![deny(clippy::all)]

pub mod api;
pub mod logger;

extern crate napi_derive;

// OHOS uses napi_module_register() + .init_array constructor instead of
// Node.js-style napi_register_module_v1 entry point.
#[cfg(target_env = "ohos")]
mod _ohos_register {
    use core::ffi::c_void;

    type NapiEnv = *mut c_void;
    type NapiValue = *mut c_void;

    #[repr(C)]
    struct NapiModule {
        nm_version: i32,
        nm_flags: u32,
        nm_filename: *const u8,
        nm_register_func: unsafe extern "C" fn(NapiEnv, NapiValue) -> NapiValue,
        nm_modname: *const u8,
        nm_priv: *mut c_void,
        reserved: [*mut c_void; 4],
    }

    #[allow(clippy::non_send_fields_in_send_ty)]
    unsafe impl Sync for NapiModule {}

    extern "C" {
        // Defined by napi-rs proc macros in this crate
        fn napi_register_module_v1(env: NapiEnv, exports: NapiValue) -> NapiValue;
        // From libace_napi.z.so (pre-loaded by OHOS runtime)
        fn napi_module_register(module: *mut NapiModule);
    }

    static MODNAME: &[u8] = b"libcloudreve\0";

    static mut OHOS_MODULE: NapiModule = NapiModule {
        nm_version: 1,
        nm_flags: 0,
        nm_filename: core::ptr::null(),
        nm_register_func: napi_register_module_v1,
        nm_modname: MODNAME.as_ptr(),
        nm_priv: core::ptr::null_mut(),
        reserved: [core::ptr::null_mut(); 4],
    };

    #[used]
    #[link_section = ".init_array"]
    static OHOS_INIT: unsafe extern "C" fn() = register_module;

    unsafe extern "C" fn register_module() {
        crate::logger::init();
        napi_module_register(core::ptr::addr_of_mut!(OHOS_MODULE));
    }
}
