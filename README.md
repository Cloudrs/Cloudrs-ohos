# Cloudrs

[English](README.en.md) | 简体中文

[![Version](https://img.shields.io/github/v/tag/Cloudrs/Cloudrs-ohos?label=%E7%89%88%E6%9C%AC&sort=semver)](https://github.com/Cloudrs/Cloudrs-ohos/tags)
[![License](https://img.shields.io/badge/%E5%8D%8F%E8%AE%AE-GPL--3.0-blue)](LICENSE)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-6.1.0(23)-1F6FEB)](https://www.harmonyos.com/)
[![AppGallery](https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-%E5%8D%8E%E4%B8%BA%E5%BA%94%E7%94%A8%E5%B8%82%E5%9C%BA-red)](https://appgallery.huawei.com/app/detail?id=com.dreamflytech.cloudrs&channelId=SHARE&source=appshare)

> 中文 | [English](README.en.md)

Cloudrs 是 [Cloudreve](https://github.com/cloudreve/Cloudreve) 云存储的 **HarmonyOS Next 原生客户端**，使用 ArkTS 编写界面，底层网络层由 Rust 实现，同时支持 Cloudreve V3 / V4 服务端 API。

## <img src="docs/images/appgallery.png" width="26" align="top" alt="" /> 下载

[**华为应用市场 (AppGallery)**](https://appgallery.huawei.com/app/detail?id=com.dreamflytech.cloudrs&channelId=SHARE&source=appshare) — 推荐普通用户下载安装，开箱即用。

如果你是开发者，或想体验最新功能，可参照下方 [构建](#构建) 章节自行编译。

- **Bundle**: `com.dreamflytech.cloudrs`
- **目标 SDK**: HarmonyOS 6.1.0(23)

## 功能特性

### 文件管理

- **浏览与整理** — 目录浏览、图标 / 列表双视图、按名称 / 时间 / 大小 / 类型排序，多选批量操作
- **文件操作** — 新建文件夹 / 新建文件、上传、下载、重命名、复制、移动、删除、查看详情
- **搜索** — 支持「当前目录 / 全部文件」两种范围，优先走服务端搜索，服务端不支持时自动回落为全站遍历；保留搜索历史
- **分享** — 创建 / 管理分享链接，可设置有效期与提取码；也可经系统分享面板发送给其他应用

### 预览与编辑

- **图片** — 手势缩放、2in1 鼠标滚轮缩放；接入系统 AI 识图（长按提取主体与文字）；可将图片拖拽到其他应用
- **视频** — 内置播放器与视频缩略图，支持全屏、PC / 2in1 键盘快捷控制
- **文本 / 代码** — 基于 CodeMirror 6 的编辑器（行号、查找、跳转行、16 种语言高亮），Markdown 渲染预览与编辑工具条；自动识别 UTF-8 / GBK / UTF-16 编码，认不出的二进制直接拒绝显示而不是糊一屏乱码
- **在线编辑保存** — 保存前比对服务端基线，检测到他端改动会先提示；保存失败自动落本地草稿，下次打开可恢复
- **存入系统相册** — 云端图片 / 视频可一键保存到本机图库

### 相册

- **统一相册** — 云端与本机媒体合并展示，按「时间 / 相册」分段浏览，瀑布流缩略图、大图预览与视频播放
- **自动备份** — 本地相册自动上传到云端，可配置备份目录、仅 Wi-Fi 备份、同时上传数量
- **可靠性** — 断点续传、后台持续备份、网络状态感知、云端删除对账、上传保留原始修改时间

### 传输

- **后台队列** — 基于系统 `request.agent` 的后台上传 / 下载队列，退到后台仍继续
- **上传策略** — 并发数可调（默认 3，最多 10）；同名冲突可选「跳过已有」或「全部覆盖」
- **远程下载** — 对接服务端 Aria2 离线下载，支持 HTTP(S) 与磁力链接，任务创建、进度查看与管理

### 跨设备协同

- **碰一碰分享** — 已下载的文件直接传本体（媒体进对端图库、其他文件进「华为分享」目录），未下载的则发送分享直链
- **碰一碰接收** — 平板 / 2in1 支持接收对端碰传的文件并落入沙箱
- **应用接续** — 视频播放可在手机 / 平板 / PC 间接力，播放进度与状态一并带走

### 多端适配与个性化

- **三形态适配** — 手机 / 平板 / 2in1 同一模块，宽屏自动切换布局；2in1 上支持挂接状态栏后台常驻
- **外观偏好** — 亮色 / 暗色主题切换
- **多账号** — 多用户凭据本地加密存储（S4 安全等级）、一键切换

### 安全与诊断

- **应用锁** — 人脸 / 指纹解锁，锁定态开启隐私窗口，任务视图与截屏中不暴露内容
- **日志与诊断** — 内置日志查看，一键复制脱敏后的诊断信息用于反馈

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
| `web-editor/` | 文本编辑器用的 CodeMirror 6 打包源码，产物提交在 `entry/src/main/resources/rawfile/editor/` |
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

4. **（可选）重新打包编辑器资源**：CodeMirror 产物已提交在 `entry/src/main/resources/rawfile/editor/`，日常开发同样无需 Node 环境。仅当改动 `web-editor/src/main.js` 或其依赖时，在 `web-editor/` 执行 `npm install && npm run build` 并提交重新生成的产物。

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
