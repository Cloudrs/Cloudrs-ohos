# build-ohos.ps1 - run from project root or cloudreve-api-native\ directory
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

Push-Location $scriptDir

Write-Host "Building arm64-v8a..."
cargo build --target aarch64-unknown-linux-ohos --release
Copy-Item "target\aarch64-unknown-linux-ohos\release\libcloudreve.so" "$projectRoot\entry\libs\arm64-v8a\libcloudreve.so" -Force

Write-Host "Building x86_64..."
cargo build --target x86_64-unknown-linux-ohos --release
Copy-Item "target\x86_64-unknown-linux-ohos\release\libcloudreve.so" "$projectRoot\entry\libs\x86_64\libcloudreve.so" -Force

Pop-Location
Write-Host "Done. .so files placed in entry\libs\"
