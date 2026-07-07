# Cloudrs

Cloudrs 是 [Cloudreve](https://github.com/cloudreve/Cloudreve) 云存储的 **HarmonyOS Next 原生客户端**，使用 ArkTS 编写界面，底层网络层由 Rust 实现，同时支持 Cloudreve V3 / V4 服务端 API。

- **Bundle**: `com.dreamflytech.cloudrs`
- **当前版本**: 1.0.1
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

2. **构建**：在 DevEco Studio 中打开项目，通过 *Build > Build Hap(s)/APP(s)* 构建（项目未包含 `hvigorw` 命令行包装器，使用 IDE 自带的 hvigor 集成即可）。项目无第三方 ohpm 依赖。

3. **（可选）重新编译 Rust native 层**：`entry/libs/` 中已包含预编译的 `.so`，日常开发无需 Rust 环境。如需修改 native 代码，进入 `cloudreve-api-native/` 执行 `build-ohos.ps1`（依赖本地的 `cloudreve-api` crate）。

## 相关文档

- [隐私政策](docs/privacy.md)
- [第三方组件声明](THIRD_PARTY_NOTICES.md)

## 致谢

- [Cloudreve](https://github.com/cloudreve/Cloudreve) — 优秀的开源云存储程序
- [napi-rs](https://napi.rs/)、[reqwest](https://github.com/seanmonstar/reqwest)、[tokio](https://tokio.rs/) 等 Rust 开源组件（完整列表见 [第三方组件声明](THIRD_PARTY_NOTICES.md)）
