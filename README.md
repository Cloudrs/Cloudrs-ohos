# Cloudrs

[English](README.en.md) | 简体中文

[![Version](https://img.shields.io/github/v/tag/Cloudrs/Cloudrs-ohos?label=%E7%89%88%E6%9C%AC&sort=semver)](https://github.com/Cloudrs/Cloudrs-ohos/tags)
[![License](https://img.shields.io/badge/%E5%8D%8F%E8%AE%AE-GPL--3.0-blue)](LICENSE)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-6.1.0(23)-1F6FEB)](https://www.harmonyos.com/)
[![AppGallery](https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-%E5%8D%8E%E4%B8%BA%E5%BA%94%E7%94%A8%E5%B8%82%E5%9C%BA-red)](https://appgallery.huawei.com/app/detail?id=com.dreamflytech.cloudrs&channelId=SHARE&source=appshare)

> 中文 | [English](README.en.md)

Cloudrs 是 [Cloudreve](https://github.com/cloudreve/Cloudreve) 云存储的 **HarmonyOS Next 原生客户端**，使用 ArkTS 编写界面，底层网络层由 Rust 实现，同时支持 Cloudreve V3 / V4 服务端 API。

## 💾 下载

[**华为应用市场 (AppGallery)**](https://appgallery.huawei.com/app/detail?id=com.dreamflytech.cloudrs&channelId=SHARE&source=appshare) — 推荐普通用户下载安装，开箱即用。

如果你是开发者，或想体验最新功能，可参照下方 [构建](#构建) 章节自行编译。

- **Bundle**: `com.dreamflytech.cloudrs`
- **目标 SDK**: HarmonyOS 6.1.0(23)

## 功能特性

- **文件管理** — 目录浏览、搜索、上传 / 下载、重命名、移动、删除、分享链接管理
- **相册** — 云端图片 / 视频瀑布流浏览、大图预览、视频播放、保存到本地相册
- **相册备份** — 本地相册自动备份到云端，支持断点续传与云端删除对账
- **远程下载** — 对接服务端 Aria2 离线下载，创建 / 管理下载任务
- **多账号** — 多用户凭据本地加密存储（S4 安全等级）、一键切换
- **后台传输** — 基于系统 `request.agent` 的后台上传 / 下载队列，最多 5 个并发任务
- **响应式布局** — 适配手机与 2in1（平板 / PC）双形态，宽屏自动切换布局
- **安全** — 生物识别解锁、隐私窗口防截屏

## 技术架构

```
┌──────────────────────────────────────────┐
│  ArkTS UI (entry)                        │
│  · 自研 CloudRouter（NavPathStack）导航    │
│  · @ObservedV2/@Trace 响应式状态          │
│  · relationalStore + sendablePreferences │
├──────────────────────────────────────────┤
│  Rust Native (cloudreve-api-native)      │
│  · napi-rs 绑定，编译为 libcloudreve.so   │
│  · reqwest + tokio 异步网络               │
│  · 同时封装 Cloudreve V3 / V4 客户端      │
└──────────────────────────────────────────┘
```

### 目录结构

| 路径 | 说明 |
|---|---|
| `entry/` | 主 HAP 模块（ArkTS 源码、资源） |
| `entry/src/main/ets/pages/` | 页面：登录、主页（文件 / 相册 / 远程下载 / 我的 四个 Tab）、预览、搜索等 |
| `entry/src/main/ets/components/` | 可复用组件（半模态弹层、相册网格、传输列表等） |
| `entry/libs/` | 预编译的 Rust native 产物（`arm64-v8a` / `x86_64`，有意纳入版本管理） |
| `cloudreve-api-native/` | Rust napi 绑定层源码 |
| `docs/` | 隐私政策、开发计划等文档 |

## 构建

### 环境要求

- DevEco Studio（HarmonyOS SDK 6.1.0(23)）
- ohpm / hvigor（随 DevEco Studio 提供）
- Rust 工具链（仅在需要重新编译 native 层时）

### 步骤

1. **配置签名**：复制 `build-profile.json5.template` 为 `build-profile.json5`，在 DevEco Studio 的 *File > Project Structure > Signing Configs* 中配置签名（真实签名文件已被 `.gitignore` 忽略，请勿提交）。

2. **构建**：在 DevEco Studio 中打开项目，通过 *Build > Build Hap(s)/APP(s)* 构建（项目未包含 `hvigorw` 命令行包装器，使用 IDE 自带的 hvigor 集成即可）。项目无第三方 ohpm 依赖。单 `entry` 模块面向手机/平板/2in1；2in1 上桌面入口 `EntryAbility` 作为跳板以状态栏模式拉起 `MainAbility`。

3. **（可选）重新编译 Rust native 层**：`entry/libs/` 中已包含预编译的 `.so`，日常开发无需 Rust 环境。如需修改 native 代码，进入 `cloudreve-api-native/` 执行 `build-ohos.ps1`（依赖本地的 `cloudreve-api` crate）。

## 开源协议

本项目基于 [**GPL-3.0**](LICENSE) 协议开源，Copyright © 2026 Dreamfly Tech and Cloudrs contributors。

- 本仓库（Cloudrs 客户端）与子模块 [`cloudreve-api-native`](cloudreve-api-native/) 均采用 GPL-3.0。
- Cloudrs 客户端是独立作品，仅通过 HTTP API 对接 Cloudreve 服务端，与 [Cloudreve 服务端](https://github.com/cloudreve/Cloudreve)（同为 GPL-3.0）相互独立。
- 所使用的第三方组件（CodeMirror、napi-rs、reqwest、tokio 等）均为 MIT / Apache-2.0 协议，详见 [第三方组件声明](THIRD_PARTY_NOTICES.md)。

任何二次分发或网络服务化均需遵守 GPL-3.0 条款，包括开源全部代码。

## 相关文档

- [隐私政策](docs/privacy.md)
- [第三方组件声明](THIRD_PARTY_NOTICES.md)

## ☕ 请作者喝杯咖啡

Cloudrs 是一个用爱发电的开源项目，所有开发和维护都在业余时间完成。如果它为你带来了便利，欢迎请作者喝杯咖啡 ☕ ——你的支持是这个项目持续更新的动力。

| 微信 | 支付宝 |
|:---:|:---:|
| <img src="docs/images/donate-wechat.png" width="220" alt="微信赞赏码" /> | <img src="docs/images/donate-alipay.jpg" width="220" alt="支付宝收款码" /> |

> 任意金额都是鼓励，感谢每一份支持 ❤️

## 致谢

- [Cloudreve](https://github.com/cloudreve/Cloudreve) — 优秀的开源云存储程序
- [napi-rs](https://napi.rs/)、[reqwest](https://github.com/seanmonstar/reqwest)、[tokio](https://tokio.rs/) 等 Rust 开源组件（完整列表见 [第三方组件声明](THIRD_PARTY_NOTICES.md)）
