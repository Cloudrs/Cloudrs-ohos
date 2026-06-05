---
name: harmonyos-debug-pipeline
description: Run repeatable HarmonyOS local workflows. For normal requests, build HAP with hvigor, install via hdc, and start the app. Collect hilog and screenshots only when troubleshooting, debugging, or explicitly requested.
---

# HarmonyOS 调试与安装流水线

## 概述

该 skill 用于标准化 HarmonyOS 本地运行流程。默认区分两类场景：

1. 日常编译安装运行：只构建 HAP、安装到模拟器/真机、启动应用。
2. 排查问题/调试：在日常流程外，再采集 hilog、截图并回传到电脑。

适用于在 HarmonyOS 项目（尤其是本项目）中固定一套可复用的运行和调试步骤。

## 触发场景

- 需要一键完成“编译-安装-运行”。
- 明确需要排查问题、调试、抓日志或截图回传。
- 需要统一输出目录，方便多人复现。 
- 需要将运行或调试动作写成可复用流程。

## 日常执行（推荐）

脚本路径：`scripts/install-run.ps1`

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\harmonyos-debug-pipeline\scripts\install-run.ps1 `
  -ProjectRoot "D:\Code\HarmonyOSNext\DevEcoStudioProjects\Cloudrs" `
  -Target "127.0.0.1:5555" `
  -NoDaemon
```

可通过参数覆盖：`NodeExe`、`HvigorJs`、`HdcExe`、`BundleName`、`AbilityName`、`HapPath`。

## 调试排查执行

只有在需要日志、截图或问题排查时才使用完整调试脚本。

脚本路径：`scripts/debug-loop.ps1`

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\harmonyos-debug-pipeline\scripts\debug-loop.ps1 `
  -ProjectRoot "D:\Code\HarmonyOSNext\DevEcoStudioProjects\Cloudrs" `
  -Target "127.0.0.1:5555" `
  -NoDaemon
```

该脚本会额外导出 hilog、截图并拉回 `harmonyos-debug-pipeline\artifacts`。

## 手工标准流程

### 1) 设备与工具检查

```powershell
& "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" list targets
& "C:\Program Files\nodejs\node.exe" "D:\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js" -h
```

### 2) 构建签名 HAP

```powershell
& "C:\Program Files\nodejs\node.exe" "D:\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js" assembleHap --no-daemon
```

默认产物：`entry\build\default\outputs\default\entry-default-signed.hap`

### 3) 安装到设备

```powershell
& "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" -t 127.0.0.1:5555 install "D:\Code\HarmonyOSNext\DevEcoStudioProjects\Cloudrs\entry\build\default\outputs\default\entry-default-signed.hap"
```

### 4) 启动应用

```powershell
& "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" -t 127.0.0.1:5555 shell aa start -b com.dreamflytech.cloudrs -a EntryAbility
```

### 5) 调试时采集 hilog

```powershell
& "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" -t 127.0.0.1:5555 shell hilog -x -t app > "D:\Code\HarmonyOSNext\DevEcoStudioProjects\Cloudrs\harmonyos-debug-pipeline\artifacts\hilog.txt"
```

可按 tag/domain/pid 过滤，如：

```powershell
& "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" -t 127.0.0.1:5555 shell hilog -x -t app -T cloudrs
```

### 6) 调试时截图并拉回电脑

```powershell
$remote = "/data/local/tmp/CloudRs-debug.jpeg"
& "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" -t 127.0.0.1:5555 shell "snapshot_display -f $remote"
& "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" -t 127.0.0.1:5555 file recv $remote "D:\Code\HarmonyOSNext\DevEcoStudioProjects\Cloudrs\harmonyos-debug-pipeline\artifacts\CloudRs-debug.jpeg"
& "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" -t 127.0.0.1:5555 shell "rm $remote"
```

> 注意：`snapshot_display` 仅在该验证环境下要求输出文件后缀为 `.jpeg`。

## 脚本参数说明

- `ProjectRoot`：项目根目录（默认当前路径）。
- `Target`：`hdc` 目标（如 `127.0.0.1:5555`）。
- `BundleName`：应用 `bundleName`，默认 `com.dreamflytech.cloudrs`。
- `HvigorJs`：`hvigor.js` 路径。
- `HdcExe`：`hdc.exe` 路径。
- `HapPath`：可选，指定 HAP 文件；为空时自动匹配 `entry-default-signed.hap`。
- `OutputDir`：输出目录，默认 `harmonyos-debug-pipeline\artifacts`。
- `NoDaemon`：是否加 `--no-daemon`。

## 常见问题

- `installHap` 不存在：本项目使用 `hdc install`。
- `hvigor` lock 卡住：清理锁后再执行 `--no-daemon`。
- 截图提示后缀不合法：改为 `.jpeg`。

## 资源

- `agents/openai.yaml`
- `references/hdc-commands.md`
- `scripts/debug-loop.ps1`
