fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();

    if target_os == "ohos" {
        let ndk_root = std::env::var("OHOS_NDK_ROOT")
            .unwrap_or_else(|_| r"D:\Huawei\DevEco Studio\sdk\default\openharmony\native".to_string());
        let arch_triple = match target_arch.as_str() {
            "aarch64" => "aarch64-linux-ohos",
            "x86_64" => "x86_64-linux-ohos",
            _ => "aarch64-linux-ohos",
        };
        let lib_path = format!(r"{}\sysroot\usr\lib\{}", ndk_root, arch_triple);
        println!("cargo:rustc-link-search={}", lib_path);
        println!("cargo:rustc-link-lib=ace_napi.z");
    } else {
        napi_build::setup();
    }
}
