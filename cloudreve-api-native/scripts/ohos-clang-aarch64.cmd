@echo off
"D:\Huawei\DevEco Studio\sdk\default\openharmony\native\llvm\bin\clang.exe" -target aarch64-linux-ohos --sysroot="D:\Huawei\DevEco Studio\sdk\default\openharmony\native\sysroot" -D__MUSL__ %*
