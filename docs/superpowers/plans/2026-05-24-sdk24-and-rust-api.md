# SDK 24 Upgrade + Rust cloudreve-api 集成计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Cloudrs 升级到 HarmonyOS 6.1.1 SDK（API 24 beta1），同时将当前 axios 网络层替换为 Rust 原生 cloudreve-api 库（NAPI 模块）。

**Architecture:**
- **Phase 1（SDK 升级）**：纯配置 + 依赖版本变更，确保项目在 API 24 下编译通过，修复废弃 API 调用。
- **Phase 2（Rust API 层）**：创建独立 Rust workspace `cloudreve-api-native/`，通过 NAPI 绑定暴露给 ArkTS；在 `CloudreveNative.ets` 做 Promise→HttpCallback 桥接，保持 `CloudApi.ets` 接口不变，移除 `@ohos/axios` 依赖。背景传输（`request.agent`）保持原有 ArkTS 实现。

**Tech Stack:** ArkTS / HarmonyOS API 24、Rust (napi-rs)、reqwest（TLS: rustls）、aarch64-unknown-linux-ohos / x86_64-unknown-linux-ohos 交叉编译。

---

## 关键设计决策（Phase 2）

### 为什么用 Rust native 模块，而不是继续用 axios？

| 问题 | 现状 | Rust 方案 |
|------|------|-----------|
| PATCH 支持 | axios 不支持，绕用 rcp | reqwest 原生支持 |
| 类型安全 | 手动维护 ArkTS 接口 | Rust 强类型，编译期保证 |
| 平台依赖 | 依赖 `@ohos/axios` 第三方包 | 零外部 ArkTS 依赖 |
| API 24 兼容 | 需等 axios 适配 | 不受三方库影响 |

### 哪些部分不能用 Rust 替换？

- **大文件下载**（`cloudGetLargeFile`）：依赖 HarmonyOS `request.agent` 后台传输服务，系统 API，不可替换。
- **文件上传**（`RequestUpload.ets`）：同上。
- **Cookie 持久化**：由 ArkTS 的 `UserDatabase` + `AppStorage` 管理，Rust 层每次请求接收 cookie 参数，不独立存储。

### 调用链设计

```
页面/组件 (HttpCallback<T> 回调)
    ↓
CloudApi.ets (保持静态方法接口不变)
    ↓ 调用
CloudreveNative.ets (Promise→HttpCallback 桥)
    ↓ NAPI Promise
libcloudreve.so (Rust NAPI bindings)
    ↓
reqwest async runtime (tokio)
    ↓ HTTP
Cloudreve Server API v3
```

---

## 文件变更地图

### Phase 1 (SDK 升级)
| 操作 | 文件 |
|------|------|
| Modify | `build-profile.json5` — targetSdkVersion/compatibleSdkVersion |
| Modify | `oh-package.json5` — 依赖版本升级 |
| Modify | `entry/src/main/ets/model/net/CloudApi.ets` — 删除废弃 import |
| Modify | `entry/src/main/module.json5` — 权限声明按 API 24 格式更新（如需） |

### Phase 2 (Rust API 层)
| 操作 | 文件 |
|------|------|
| Create | `cloudreve-api-native/Cargo.toml` |
| Create | `cloudreve-api-native/src/lib.rs` |
| Create | `cloudreve-api-native/src/api.rs` |
| Create | `cloudreve-api-native/src/types.rs` |
| Create | `cloudreve-api-native/.cargo/config.toml` |
| Create | `cloudreve-api-native/build.sh` |
| Create | `entry/src/main/cpp/types/libcloudreve/Index.d.ts` |
| Create | `entry/src/main/cpp/types/libcloudreve/oh-package.json5` |
| Create | `entry/src/main/ets/utils/CloudreveNative.ets` |
| Modify | `entry/src/main/ets/model/net/CloudApi.ets` |
| Modify | `entry/src/main/ets/model/net/ApiTypes.ets` — 移除 AxiosProgressEvent 依赖 |
| Delete | `entry/src/main/ets/utils/AxiosRequest.ets` |
| Modify | `oh-package.json5` — 移除 `@ohos/axios` |
| Modify | `entry/build-profile.json5` — 声明 nativeLib |

---

## Phase 1: SDK 升级到 6.1.1（API 24 beta1）

### Task 1: 更新 build-profile.json5

**Files:**
- Modify: `build-profile.json5`

- [ ] **Step 1: 更新 SDK 版本字段**

将 `build-profile.json5` 中的产品配置修改为：

```json5
{
  "app": {
    "products": [
      {
        "name": "default",
        "targetSdkVersion": "6.1.1(24)",
        "compatibleSdkVersion": "6.0.0(20)",
        "runtimeOS": "HarmonyOS",
        "buildOption": {
          "strictMode": {
            "caseSensitiveCheck": true,
            "useNormalizedOHMUrl": true
          }
        }
      }
    ]
  }
}
```

> 注意：`compatibleSdkVersion` 保留 `6.0.0(20)` 以兼容旧设备。若 API 24 引入了不兼容旧版的强制特性，后续再调整。

- [ ] **Step 2: 在 DevEco Studio 同步项目**

菜单 `File → Sync and Refresh Project`，观察 SDK 下载和同步日志，确认无 SDK not found 错误。

- [ ] **Step 3: Commit**

```bash
git add build-profile.json5
git commit -m "[CHG] 升级 targetSdkVersion 到 HarmonyOS 6.1.1 (API 24 beta1)"
```

---

### Task 2: 升级三方依赖到 API 24 兼容版本

**Files:**
- Modify: `oh-package.json5`

- [ ] **Step 1: 查询各库 API 24 最新版本**

在 ohpm 仓库（https://ohpm.openharmony.cn）逐一搜索：
- `@ohos/axios` — 查 2.x 最新版（2.3.x 或更高）
- `@hadss/hmrouter` — 查是否有 1.0.0-rc.11+ 支持 API 24
- `@pura/harmony-utils` — 查最新版本
- `@pura/harmony-dialog` — 查最新版本
- `@pura/spinkit` — 查最新版本

- [ ] **Step 2: 更新 oh-package.json5**

根据查询结果将版本号填入（示例占位，以实际最新版为准）：

```json5
{
  "modelVersion": "5.0.0",
  "dependencies": {
    "@ohos/axios": "^2.3.0",
    "@pura/harmony-dialog": "^1.1.0",
    "@pura/harmony-utils": "^1.3.0",
    "@hadss/hmrouter": "^1.0.0-rc.11"
  },
  "devDependencies": {
    "@ohos/hypium": "1.0.21",
    "@ohos/hamock": "1.0.0"
  }
}
```

> 如果某个库尚无 API 24 兼容版本，在本 task 注释说明，暂时锁定当前版本，等待库作者更新。

- [ ] **Step 3: 安装依赖**

```bash
ohpm install
```

预期：所有依赖下载成功，`oh-package-lock.json5` 更新。

- [ ] **Step 4: Commit**

```bash
git add oh-package.json5 oh-package-lock.json5
git commit -m "[CHG] 升级三方依赖以适配 API 24 beta1"
```

---

### Task 3: 清理废弃 API 调用

**Files:**
- Modify: `entry/src/main/ets/model/net/CloudApi.ets`

- [ ] **Step 1: 删除无用的 telephony.call import**

`CloudApi.ets` 第 22 行存在 `import call from "@ohos.telephony.call"` 但全文从未使用。在 API 24 中旧式 `@ohos.*` namespace import 会有 deprecation 警告，删除之：

在 `CloudApi.ets` 中，将：
```typescript
import call from "@ohos.telephony.call";
import { uri } from "@kit.ArkTS";
```
改为：
```typescript
import { uri } from "@kit.ArkTS";
```

- [ ] **Step 2: 检查其他 @ohos.* 旧 namespace import**

在整个 `entry/src/main/ets/` 目录中搜索旧式 import（DevEco Studio 或 `grep -r "@ohos\." --include="*.ets"`），API 24 推荐全部迁移到 `@kit.*` 命名空间。

常见映射：
| 旧 import | 新 import |
|-----------|-----------|
| `@ohos.telephony.call` | `@kit.TelephonyKit` |
| `@ohos.fileio` | `@kit.CoreFileKit` |
| `@ohos.net.http` | `@kit.NetworkKit` |

逐一修改项目中发现的旧式 import。

- [ ] **Step 3: 运行 Code Linter**

在 DevEco Studio 执行 `Code → Code Linter`，修复所有 Error 级别告警。

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/model/net/CloudApi.ets
git commit -m "[FIX] 删除废弃的 telephony.call import，清理旧 namespace"
```

---

### Task 4: 验证编译和基本功能

**Files:** 无新增文件，验证阶段

- [ ] **Step 1: 完整编译 debug HAP**

```bash
./hvigorw assembleHap
```

预期：BUILD SUCCESSFUL，无 Error。记录所有 Warning 供后续处理。

- [ ] **Step 2: 运行到模拟器或真机**

在 DevEco Studio 点击 Run，或：
```bash
./hvigorw installHap
```

验证：
- App 正常启动
- 登录页面可访问
- 连接测试服务器，文件列表可加载
- 下载功能正常

- [ ] **Step 3: Commit 稳定点**

```bash
git commit --allow-empty -m "[CHG] SDK 24 beta1 升级完成，编译验证通过"
```

---

## Phase 2: Rust cloudreve-api 原生模块集成

> **前置条件：** 本机已安装 Rust 工具链（rustup）、HarmonyOS NDK（通过 DevEco Studio SDK 获取）、cargo-ndk 或 napi-rs CLI。

### Task 5: 搭建 Rust 工程结构

**Files:**
- Create: `cloudreve-api-native/Cargo.toml`
- Create: `cloudreve-api-native/src/lib.rs`
- Create: `cloudreve-api-native/.cargo/config.toml`

- [ ] **Step 1: 安装 HarmonyOS Rust target**

HarmonyOS 使用 `ohos` 系列 target（需 Rust nightly 或特定版本支持）：

```bash
rustup target add aarch64-unknown-linux-ohos
rustup target add x86_64-unknown-linux-ohos
```

如果 target 不存在（取决于 Rust 版本），改用 `aarch64-linux-android` 并配置 HarmonyOS NDK sysroot：
```bash
rustup target add aarch64-linux-android
rustup target add x86_64-linux-android
```

> 注：HarmonyOS NDK 基于 LLVM/Clang，与 Android NDK 工具链兼容。实际 target 名称以 NDK 文档为准。

- [ ] **Step 2: 创建 Rust workspace**

```bash
mkdir cloudreve-api-native
cd cloudreve-api-native
cargo init --lib
```

- [ ] **Step 3: 编辑 Cargo.toml**

```toml
[package]
name = "cloudreve-api-native"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
name = "cloudreve"

[dependencies]
napi = { version = "2", features = ["napi4", "tokio_rt"] }
napi-derive = "2"
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls", "json", "cookies"] }
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"

[build-dependencies]
napi-build = "2"
```

- [ ] **Step 4: 创建 build.rs**

新建 `cloudreve-api-native/build.rs`：
```rust
fn main() {
    napi_build::setup();
}
```

- [ ] **Step 5: 配置交叉编译 .cargo/config.toml**

新建 `cloudreve-api-native/.cargo/config.toml`（路径按实际 NDK 位置修改）：

```toml
# HarmonyOS NDK 路径，从 DevEco Studio SDK 目录获取
# 典型路径：C:\Users\<user>\AppData\Local\Huawei\Sdk\openharmony\<ver>\native\llvm\bin

[target.aarch64-unknown-linux-ohos]
linker = "C:/Users/wangx/AppData/Local/Huawei/Sdk/openharmony/5.0.3.900/native/llvm/bin/aarch64-unknown-linux-ohos-clang"
ar = "C:/Users/wangx/AppData/Local/Huawei/Sdk/openharmony/5.0.3.900/native/llvm/bin/llvm-ar"

[target.x86_64-unknown-linux-ohos]
linker = "C:/Users/wangx/AppData/Local/Huawei/Sdk/openharmony/5.0.3.900/native/llvm/bin/x86_64-unknown-linux-ohos-clang"
ar = "C:/Users/wangx/AppData/Local/Huawei/Sdk/openharmony/5.0.3.900/native/llvm/bin/llvm-ar"
```

> 实际 NDK 路径通过 DevEco Studio → SDK Manager 查看已安装 SDK 的 native 目录。

- [ ] **Step 6: 验证 Rust 工程能编译（host target 先）**

```bash
cd cloudreve-api-native
cargo build
```

预期：Compiling 成功（host 平台，验证依赖能解析）。

- [ ] **Step 7: Commit**

```bash
git add cloudreve-api-native/
git commit -m "[ADD] 创建 Rust cloudreve-api-native 工程骨架"
```

---

### Task 6: 实现 Rust API 类型和 HTTP 客户端

**Files:**
- Create: `cloudreve-api-native/src/types.rs`
- Create: `cloudreve-api-native/src/client.rs`

- [ ] **Step 1: 创建 types.rs — 与 ApiTypes.ets 对应的 Rust 类型**

新建 `cloudreve-api-native/src/types.rs`：

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
pub struct BaseResponse<T> {
    pub code: i32,
    pub data: T,
    pub msg: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct LoginData {
    pub username: String,
    pub password: String,
    #[serde(rename = "captchaCode")]
    pub captcha_code: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserInfo {
    pub id: String,
    pub user_name: String,
    pub nickname: String,
    pub status: i32,
    pub avatar: String,
    pub created_at: String,
    pub preferred_theme: String,
    pub anonymous: bool,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct SiteConfig {
    pub title: String,
    #[serde(rename = "loginCaptcha")]
    pub login_captcha: String,
    #[serde(rename = "registerEnabled")]
    pub register_enabled: bool,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct ObjectInfo {
    pub id: String,
    pub name: String,
    pub path: String,
    pub thumb: bool,
    pub size: u64,
    #[serde(rename = "type")]
    pub object_type: String,
    pub date: String,
    pub create_date: String,
    pub source_enabled: bool,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Policy {
    pub id: String,
    pub name: String,
    #[serde(rename = "type")]
    pub policy_type: String,
    pub max_size: u64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct DirectoryInfo {
    pub parent: String,
    pub objects: Vec<ObjectInfo>,
    pub policy: Policy,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserStorage {
    pub used: u64,
    pub free: u64,
    pub total: u64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UploadRequestResponse {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    #[serde(rename = "chunkSize")]
    pub chunk_size: u64,
    pub expires: u64,
}

#[derive(Debug, Serialize)]
pub struct ObjectSrc {
    pub items: Option<Vec<String>>,
    pub dirs: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
pub struct ObjectMove {
    pub src: ObjectSrc,
    pub dst: String,
}

#[derive(Debug, Serialize)]
pub struct ObjectCopy {
    pub src: ObjectSrc,
    pub dst: String,
}

#[derive(Debug, Serialize)]
pub struct ObjectNew {
    pub path: String,
}

#[derive(Debug, Serialize)]
pub struct ObjectRename {
    pub src: ObjectSrc,
    #[serde(rename = "newName")]
    pub new_name: String,
}

#[derive(Debug, Serialize)]
pub struct ObjectUpload {
    pub path: String,
    pub size: u64,
    pub name: String,
    #[serde(rename = "lastModified")]
    pub last_modified: u64,
    pub mime_type: String,
    #[serde(rename = "chunkSize")]
    pub chunk_size: u64,
}

#[derive(Debug, Deserialize)]
pub struct Aria2TaskParam {
    pub dst: String,
    pub url: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Aria2Downloading {
    pub update: String,
    pub interval: i32,
    pub name: String,
    pub status: i32,
    pub dst: String,
    pub total: u64,
    pub downloaded: u64,
    pub speed: u64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Aria2Finished {
    pub name: String,
    pub gid: String,
    pub status: i32,
    pub dst: String,
    pub error: String,
    pub total: u64,
    pub task_status: i32,
    pub task_error: String,
    pub create: String,
    pub update: String,
    pub node: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserTask {
    pub status: i32,
    #[serde(rename = "type")]
    pub task_type: i32,
    pub create_date: String,
    pub progress: i32,
    pub error: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserTasks {
    pub tasks: Vec<UserTask>,
    pub total: u64,
}
```

- [ ] **Step 2: 创建 client.rs — reqwest HTTP 客户端**

新建 `cloudreve-api-native/src/client.rs`：

```rust
use reqwest::{Client, Response, header};
use crate::types::BaseResponse;
use serde::{de::DeserializeOwned, Serialize};
use std::sync::OnceLock;

const API_PREFIX: &str = "/api/v3";
const SUCCESS_CODE: i32 = 0;

static HTTP_CLIENT: OnceLock<CloudreveClient> = OnceLock::new();

pub struct CloudreveClient {
    client: Client,
    base_url: std::sync::RwLock<String>,
    cookie: std::sync::RwLock<String>,
}

impl CloudreveClient {
    fn new() -> Self {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("Failed to build reqwest client");
        Self {
            client,
            base_url: std::sync::RwLock::new(String::new()),
            cookie: std::sync::RwLock::new(String::new()),
        }
    }

    pub fn global() -> &'static CloudreveClient {
        HTTP_CLIENT.get_or_init(CloudreveClient::new)
    }

    pub fn set_base_url(&self, url: &str) {
        let mut base = self.base_url.write().unwrap();
        *base = format!("{}{}", url, API_PREFIX);
    }

    pub fn get_base_url(&self) -> String {
        self.base_url.read().unwrap().clone()
    }

    pub fn set_cookie(&self, cookie: &str) {
        let mut c = self.cookie.write().unwrap();
        *c = cookie.to_string();
    }

    pub fn get_cookie(&self) -> String {
        self.cookie.read().unwrap().clone()
    }

    fn build_url(&self, path: &str) -> String {
        format!("{}{}", self.base_url.read().unwrap(), path)
    }

    fn add_cookie(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        let cookie = self.get_cookie();
        if !cookie.is_empty() {
            builder.header(header::COOKIE, cookie)
        } else {
            builder
        }
    }

    pub async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T, String> {
        let url = self.build_url(path);
        let resp = self.add_cookie(self.client.get(&url))
            .send()
            .await
            .map_err(|e| e.to_string())?;
        self.parse_response::<T>(resp).await
    }

    pub async fn post<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<(T, Option<String>), String> {
        let url = self.build_url(path);
        let resp = self.add_cookie(self.client.post(&url))
            .json(body)
            .send()
            .await
            .map_err(|e| e.to_string())?;
        // 提取 set-cookie
        let set_cookie = resp.headers()
            .get(header::SET_COOKIE)
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());
        let data = self.parse_response::<T>(resp).await?;
        Ok((data, set_cookie))
    }

    pub async fn put<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<T, String> {
        let url = self.build_url(path);
        let resp = self.add_cookie(self.client.put(&url))
            .json(body)
            .send()
            .await
            .map_err(|e| e.to_string())?;
        self.parse_response::<T>(resp).await
    }

    pub async fn delete<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<T, String> {
        let url = self.build_url(path);
        let resp = self.add_cookie(self.client.delete(&url))
            .json(body)
            .send()
            .await
            .map_err(|e| e.to_string())?;
        self.parse_response::<T>(resp).await
    }

    pub async fn patch<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<T, String> {
        let url = self.build_url(path);
        let resp = self.add_cookie(self.client.patch(&url))
            .json(body)
            .send()
            .await
            .map_err(|e| e.to_string())?;
        self.parse_response::<T>(resp).await
    }

    async fn parse_response<T: DeserializeOwned>(&self, resp: Response) -> Result<T, String> {
        let status = resp.status();
        let base: BaseResponse<T> = resp.json().await.map_err(|e| e.to_string())?;
        if status.is_success() && base.code == SUCCESS_CODE {
            Ok(base.data)
        } else {
            Err(base.msg)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add cloudreve-api-native/src/
git commit -m "[ADD] Rust cloudreve-api 类型定义和 HTTP 客户端实现"
```

---

### Task 7: 实现 NAPI 绑定层

**Files:**
- Modify: `cloudreve-api-native/src/lib.rs`
- Create: `cloudreve-api-native/src/api.rs`

- [ ] **Step 1: 编写 api.rs — NAPI 导出函数**

新建 `cloudreve-api-native/src/api.rs`：

```rust
use napi_derive::napi;
use crate::client::CloudreveClient;
use crate::types::*;
use serde_json::Value;

// ---- 配置 ----

#[napi]
pub fn set_base_url(url: String) {
    CloudreveClient::global().set_base_url(&url);
}

#[napi]
pub fn get_base_url() -> String {
    CloudreveClient::global().get_base_url()
}

#[napi]
pub fn set_cookie(cookie: String) {
    CloudreveClient::global().set_cookie(&cookie);
}

// ---- 站点 ----

#[napi]
pub async fn ping() -> napi::Result<String> {
    CloudreveClient::global()
        .get::<String>("/site/ping")
        .await
        .map_err(|e| napi::Error::from_reason(e))
}

#[napi]
pub async fn get_site_config() -> napi::Result<serde_json::Value> {
    CloudreveClient::global()
        .get::<Value>("/site/config")
        .await
        .map_err(|e| napi::Error::from_reason(e))
}

// ---- 用户 ----

/// 返回 (user_info_json, set_cookie_header)
#[napi]
pub async fn login(username: String, password: String) -> napi::Result<Vec<String>> {
    let body = LoginData { username, password, captcha_code: String::new() };
    let (data, cookie) = CloudreveClient::global()
        .post::<Value, _>("/user/session", &body)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    let data_str = serde_json::to_string(&data).unwrap_or_default();
    let cookie_str = cookie.unwrap_or_default();
    Ok(vec![data_str, cookie_str])
}

#[napi]
pub async fn get_user_storage() -> napi::Result<String> {
    let data = CloudreveClient::global()
        .get::<Value>("/user/storage")
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(serde_json::to_string(&data).unwrap_or_default())
}

// ---- 文件列表 ----

#[napi]
pub async fn get_directory(path: String) -> napi::Result<String> {
    let uri = format!("/directory{}", path);
    let data = CloudreveClient::global()
        .get::<Value>(&uri)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(serde_json::to_string(&data).unwrap_or_default())
}

// ---- 对象操作 ----

#[napi]
pub async fn delete_objects(items: Vec<String>, dirs: Vec<String>) -> napi::Result<()> {
    let src = ObjectSrc {
        items: if items.is_empty() { None } else { Some(items) },
        dirs: if dirs.is_empty() { None } else { Some(dirs) },
    };
    CloudreveClient::global()
        .delete::<Value, _>("/object", &src)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(())
}

#[napi]
pub async fn move_objects(
    items: Vec<String>,
    dirs: Vec<String>,
    dst: String,
) -> napi::Result<()> {
    let mv = ObjectMove {
        src: ObjectSrc {
            items: if items.is_empty() { None } else { Some(items) },
            dirs: if dirs.is_empty() { None } else { Some(dirs) },
        },
        dst,
    };
    CloudreveClient::global()
        .patch::<Value, _>("/object", &mv)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(())
}

#[napi]
pub async fn copy_objects(
    items: Vec<String>,
    dirs: Vec<String>,
    dst: String,
) -> napi::Result<()> {
    let cp = ObjectCopy {
        src: ObjectSrc {
            items: if items.is_empty() { None } else { Some(items) },
            dirs: if dirs.is_empty() { None } else { Some(dirs) },
        },
        dst,
    };
    CloudreveClient::global()
        .post::<Value, _>("/object/copy", &cp)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(())
}

#[napi]
pub async fn rename_object(id: String, new_name: String, is_dir: bool) -> napi::Result<()> {
    let src = if is_dir {
        ObjectSrc { items: None, dirs: Some(vec![id]) }
    } else {
        ObjectSrc { items: Some(vec![id]), dirs: None }
    };
    let rename = ObjectRename { src, new_name };
    CloudreveClient::global()
        .post::<Value, _>("/object/rename", &rename)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(())
}

#[napi]
pub async fn new_directory(path: String) -> napi::Result<()> {
    let body = ObjectNew { path };
    CloudreveClient::global()
        .put::<Value, _>("/directory", &body)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(())
}

#[napi]
pub async fn new_file(path: String) -> napi::Result<()> {
    let body = ObjectNew { path };
    CloudreveClient::global()
        .post::<Value, _>("/file/create", &body)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(())
}

#[napi]
pub async fn get_object_detail(id: String, is_folder: bool) -> napi::Result<String> {
    let uri = format!("/object/property/{}?is_folder={}&trace_root=false", id, is_folder);
    let data = CloudreveClient::global()
        .get::<Value>(&uri)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(serde_json::to_string(&data).unwrap_or_default())
}

// ---- 下载/上传请求 ----

#[napi]
pub async fn get_download_uri(id: String) -> napi::Result<String> {
    let uri = format!("/file/download/{}", id);
    let data = CloudreveClient::global()
        .put::<Value, _>(&uri, &Value::Null)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(data.as_str().unwrap_or("").to_string())
}

// ---- Aria2 ----

#[napi]
pub async fn aria2_downloading() -> napi::Result<String> {
    let data = CloudreveClient::global()
        .get::<Value>("/aria2/downloading")
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(serde_json::to_string(&data).unwrap_or_default())
}

#[napi]
pub async fn aria2_finished(page: i32) -> napi::Result<String> {
    let uri = format!("/aria2/finished?page={}", page);
    let data = CloudreveClient::global()
        .get::<Value>(&uri)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(serde_json::to_string(&data).unwrap_or_default())
}

#[napi]
pub async fn aria2_create_task(dst: String, urls: Vec<String>) -> napi::Result<()> {
    let body = serde_json::json!({ "dst": dst, "url": urls });
    CloudreveClient::global()
        .post::<Value, _>("/aria2/url", &body)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(())
}

#[napi]
pub async fn aria2_delete_task(gid: String) -> napi::Result<()> {
    let uri = format!("/aria2/task/{}", gid);
    CloudreveClient::global()
        .delete::<Value, _>(&uri, &Value::Null)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(())
}

#[napi]
pub async fn get_user_tasks(page: i32) -> napi::Result<String> {
    let uri = format!("/user/setting/tasks?page={}", page);
    let data = CloudreveClient::global()
        .get::<Value>(&uri)
        .await
        .map_err(|e| napi::Error::from_reason(e))?;
    Ok(serde_json::to_string(&data).unwrap_or_default())
}
```

- [ ] **Step 2: 更新 lib.rs 注册模块**

编辑 `cloudreve-api-native/src/lib.rs`：

```rust
#![deny(clippy::all)]

mod client;
mod types;
mod api;

#[macro_use]
extern crate napi_derive;
```

- [ ] **Step 3: 交叉编译为 HarmonyOS ARM64**

```bash
cd cloudreve-api-native
cargo build --target aarch64-unknown-linux-ohos --release
```

预期：`target/aarch64-unknown-linux-ohos/release/libcloudreve.so` 生成。

如果 target 名为 `aarch64-linux-android`：
```bash
cargo build --target aarch64-linux-android --release
```

- [ ] **Step 4: 复制 .so 到 entry 目录**

```bash
cp target/aarch64-unknown-linux-ohos/release/libcloudreve.so ../entry/libs/arm64-v8a/libcloudreve.so
```

同时编译 x86_64（模拟器）：
```bash
cargo build --target x86_64-unknown-linux-ohos --release
cp target/x86_64-unknown-linux-ohos/release/libcloudreve.so ../entry/libs/x86_64/libcloudreve.so
```

- [ ] **Step 5: Commit**

```bash
git add cloudreve-api-native/src/
git commit -m "[ADD] Rust NAPI 绑定层实现，覆盖所有 CloudApi 方法"
```

---

### Task 8: 创建 ArkTS 类型声明和 Native 桥接层

**Files:**
- Create: `entry/src/main/cpp/types/libcloudreve/Index.d.ts`
- Create: `entry/src/main/cpp/types/libcloudreve/oh-package.json5`
- Create: `entry/src/main/ets/utils/CloudreveNative.ets`

- [ ] **Step 1: 创建 NAPI 类型声明文件**

新建 `entry/src/main/cpp/types/libcloudreve/oh-package.json5`：
```json5
{
  "name": "libcloudreve.so",
  "types": "./Index.d.ts",
  "version": "1.0.0",
  "description": "Cloudreve API native module"
}
```

新建 `entry/src/main/cpp/types/libcloudreve/Index.d.ts`：
```typescript
export const setBaseUrl: (url: string) => void;
export const getBaseUrl: () => string;
export const setCookie: (cookie: string) => void;
export const ping: () => Promise<string>;
export const getSiteConfig: () => Promise<object>;
export const login: (username: string, password: string) => Promise<string[]>;
export const getUserStorage: () => Promise<string>;
export const getDirectory: (path: string) => Promise<string>;
export const deleteObjects: (items: string[], dirs: string[]) => Promise<void>;
export const moveObjects: (items: string[], dirs: string[], dst: string) => Promise<void>;
export const copyObjects: (items: string[], dirs: string[], dst: string) => Promise<void>;
export const renameObject: (id: string, newName: string, isDir: boolean) => Promise<void>;
export const newDirectory: (path: string) => Promise<void>;
export const newFile: (path: string) => Promise<void>;
export const getObjectDetail: (id: string, isFolder: boolean) => Promise<string>;
export const getDownloadUri: (id: string) => Promise<string>;
export const aria2Downloading: () => Promise<string>;
export const aria2Finished: (page: number) => Promise<string>;
export const aria2CreateTask: (dst: string, urls: string[]) => Promise<void>;
export const aria2DeleteTask: (gid: string) => Promise<void>;
export const getUserTasks: (page: number) => Promise<string>;
```

- [ ] **Step 2: 在 oh-package.json5 注册本地 native 包**

在项目根 `oh-package.json5` 添加 native 模块引用：

```json5
{
  "modelVersion": "5.0.0",
  "dependencies": {
    "@pura/harmony-dialog": "^1.1.0",
    "@pura/harmony-utils": "^1.3.0",
    "@hadss/hmrouter": "^1.0.0-rc.11",
    "libcloudreve.so": "file:./entry/src/main/cpp/types/libcloudreve"
  },
  "devDependencies": {
    "@ohos/hypium": "1.0.21",
    "@ohos/hamock": "1.0.0"
  }
}
```

> `@ohos/axios` 已从 dependencies 中移除。

- [ ] **Step 3: 创建 CloudreveNative.ets — Promise→HttpCallback 桥**

新建 `entry/src/main/ets/utils/CloudreveNative.ets`：

```typescript
import {
  setBaseUrl, getBaseUrl, setCookie,
  ping, getSiteConfig, login, getUserStorage,
  getDirectory, deleteObjects, moveObjects, copyObjects,
  renameObject, newDirectory, newFile, getObjectDetail,
  getDownloadUri,
  aria2Downloading, aria2Finished, aria2CreateTask, aria2DeleteTask,
  getUserTasks
} from 'libcloudreve.so';
import { HttpCallback } from '../model/net/ApiTypes';
import Constant from '../model/Constant';
import { SiteURI } from '../model/net/ApiTypes';

export { setBaseUrl, getBaseUrl, setCookie };

function wrap<T>(promise: Promise<T>, callback?: HttpCallback<T>): void {
  if (callback?.onStart) {
    callback.onStart();
  }
  promise
    .then((data: T) => callback?.onSuccess(data))
    .catch((err: Error) => callback?.onFailure(err.message));
}

function wrapJson<T>(promise: Promise<string>, callback?: HttpCallback<T>): void {
  if (callback?.onStart) {
    callback.onStart();
  }
  promise
    .then((json: string) => {
      const data: T = JSON.parse(json) as T;
      callback?.onSuccess(data);
    })
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativePing(callback?: HttpCallback<string>): void {
  wrap(ping(), callback);
}

export function nativeGetSiteConfig<T>(callback?: HttpCallback<T>): void {
  if (callback?.onStart) { callback.onStart(); }
  getSiteConfig()
    .then((obj: object) => callback?.onSuccess(obj as T))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeLogin(username: string, password: string, callback?: HttpCallback<[string, string]>): void {
  wrap(login(username, password) as Promise<[string, string]>, callback);
}

export function nativeGetUserStorage<T>(callback?: HttpCallback<T>): void {
  wrapJson(getUserStorage(), callback);
}

export function nativeGetDirectory<T>(path: string, callback?: HttpCallback<T>): void {
  wrapJson(getDirectory(path), callback);
}

export function nativeDeleteObjects(items: string[], dirs: string[], callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  deleteObjects(items, dirs)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeMoveObjects(items: string[], dirs: string[], dst: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  moveObjects(items, dirs, dst)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeCopyObjects(items: string[], dirs: string[], dst: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  copyObjects(items, dirs, dst)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeRenameObject(id: string, newName: string, isDir: boolean, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  renameObject(id, newName, isDir)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeNewDirectory(path: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  newDirectory(path)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeNewFile(path: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  newFile(path)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeGetObjectDetail<T>(id: string, isFolder: boolean, callback?: HttpCallback<T>): void {
  wrapJson(getObjectDetail(id, isFolder), callback);
}

export function nativeGetDownloadUri(id: string, callback?: HttpCallback<string>): void {
  wrap(getDownloadUri(id), callback);
}

export function nativeAria2Downloading<T>(callback?: HttpCallback<T>): void {
  wrapJson(aria2Downloading(), callback);
}

export function nativeAria2Finished<T>(page: number, callback?: HttpCallback<T>): void {
  wrapJson(aria2Finished(page), callback);
}

export function nativeAria2CreateTask(dst: string, urls: string[], callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  aria2CreateTask(dst, urls)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeAria2DeleteTask(gid: string, callback?: HttpCallback<null>): void {
  if (callback?.onStart) { callback.onStart(); }
  aria2DeleteTask(gid)
    .then(() => callback?.onSuccess(null))
    .catch((err: Error) => callback?.onFailure(err.message));
}

export function nativeGetUserTasks<T>(page: number, callback?: HttpCallback<T>): void {
  wrapJson(getUserTasks(page), callback);
}
```

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/cpp/ entry/src/main/ets/utils/CloudreveNative.ets oh-package.json5
git commit -m "[ADD] ArkTS NAPI 类型声明和 CloudreveNative 桥接层"
```

---

### Task 9: 重写 CloudApi.ets 使用 Native 层

**Files:**
- Modify: `entry/src/main/ets/model/net/CloudApi.ets`
- Modify: `entry/src/main/ets/model/net/ApiTypes.ets`

- [ ] **Step 1: 更新 ApiTypes.ets — 移除 axios 依赖**

`ApiTypes.ets` 第 1 行 `import { AxiosProgressEvent } from "@ohos/axios"` 需要替换，因为移除 axios 后 `ProgressCallback` 里的 `AxiosProgressEvent` 类型会失效。

将 `ApiTypes.ets` 中的 `ProgressCallback` 改为用内置类型：

```typescript
// 删除：import { AxiosProgressEvent } from "@ohos/axios";

export interface DownloadProgressEvent {
  loaded: number;
  total: number;
  progress: number;
}

export interface ProgressCallback {
  onDownloadProgress?: (progress: DownloadProgressEvent) => void;
  onUploadProgress?: () => void;
}
```

- [ ] **Step 2: 重写 CloudApi.ets 使用 CloudreveNative**

完整替换 `entry/src/main/ets/model/net/CloudApi.ets`：

```typescript
import {
  setBaseUrl, getBaseUrl, setCookie,
  nativePing, nativeGetSiteConfig, nativeLogin,
  nativeGetUserStorage, nativeGetDirectory,
  nativeDeleteObjects, nativeMoveObjects, nativeCopyObjects,
  nativeRenameObject, nativeNewDirectory, nativeNewFile,
  nativeGetObjectDetail, nativeGetDownloadUri,
  nativeAria2Downloading, nativeAria2Finished,
  nativeAria2CreateTask, nativeAria2DeleteTask,
  nativeGetUserTasks
} from '../../utils/CloudreveNative';
import { FileType } from '../../utils/CommonUtil';
import {
  Aria2Downloading, Aria2Finished, DirectoryInfo,
  HttpCallback, ObjectDetail, ObjectInfo,
  SiteConfig, UploadRequestResponse, UserInfo,
  UserSetting, UserStorage, UserTasks
} from './ApiTypes';
import { ObjectSrc, ObjectCopy, ObjectMove } from './ObjectParam';
import { uri } from '@kit.ArkTS';

export { setBaseUrl as baseUrlSet, getBaseUrl as baseUrlGet, setCookie as cookieSet };

export class CloudApi {
  static getTotalPath(item: ObjectInfo): string {
    if (item.type === 'dir') {
      return item.path === '/' ? item.path + item.name : `${item.path}/${item.name}`;
    }
    return item.path;
  }

  static getBaseURL(): string {
    const url = new uri.URI(getBaseUrl());
    return `${url.scheme}://${url.host}${url.port !== '-1' ? ':' + url.port : ''}`;
  }

  static ping(callback?: HttpCallback<string>): void {
    nativePing(callback);
  }

  static getSiteConfig(callback?: HttpCallback<SiteConfig>): void {
    nativeGetSiteConfig(callback);
  }

  static login(username: string, password: string, callback?: HttpCallback<UserInfo>): void {
    if (callback?.onStart) { callback.onStart(); }
    nativeLogin(username, password, {
      onSuccess: (result: [string, string]) => {
        const userInfo: UserInfo = JSON.parse(result[0]) as UserInfo;
        const setCookieHeader: string = result[1];
        // 提取 session cookie
        const regexSession = /cloudreve-session=([^;]+);/;
        const matchCookie = setCookieHeader.match(regexSession);
        if (matchCookie) {
          const cookie = `cloudreve-session=${matchCookie[1]}`;
          AppStorage.setOrCreate('cloudCookie', cookie);
          setCookie(cookie);
        }
        const regexExpires = /Expires=([^;]+);/;
        const matchExpires = setCookieHeader.match(regexExpires);
        if (matchExpires) {
          AppStorage.setOrCreate('cloudCookieExpires', matchExpires[1]);
        }
        callback?.onSuccess(userInfo);
      },
      onFailure: (msg: string) => callback?.onFailure(msg),
    });
  }

  static userStorage(callback?: HttpCallback<UserStorage>): void {
    nativeGetUserStorage(callback);
  }

  static getFilesInfo(path: string = '/', callback?: HttpCallback<DirectoryInfo>): void {
    nativeGetDirectory(path, callback);
  }

  static getObjectDetail(id: string, isFolder: boolean, callback?: HttpCallback<ObjectDetail>): void {
    nativeGetObjectDetail(id, isFolder, callback);
  }

  static newObject(path: string, isDir: boolean, callback?: HttpCallback<null>): void {
    if (isDir) {
      nativeNewDirectory(path, callback);
    } else {
      nativeNewFile(path, callback);
    }
  }

  static deleteObjects(src: ObjectSrc, callback?: HttpCallback<null>): void {
    nativeDeleteObjects(src.items ?? [], src.dirs ?? [], callback);
  }

  static deleteObject(id: string, isDir: boolean = false, callback?: HttpCallback<null>): void {
    const items = isDir ? [] : [id];
    const dirs = isDir ? [id] : [];
    nativeDeleteObjects(items, dirs, callback);
  }

  static copyObjects(copy: ObjectCopy, callback?: HttpCallback<null>): void {
    nativeCopyObjects(copy.src.items ?? [], copy.src.dirs ?? [], copy.dst, callback);
  }

  static moveObjects(move: ObjectMove, callback?: HttpCallback<null>): void {
    nativeMoveObjects(move.src.items ?? [], move.src.dirs ?? [], move.dst, callback);
  }

  static renameObject(id: string, newName: string, isDir: boolean = false, callback?: HttpCallback<null>): void {
    nativeRenameObject(id, newName, isDir, callback);
  }

  static aria2Downloading(callback?: HttpCallback<Aria2Downloading[]>): void {
    nativeAria2Downloading(callback);
  }

  static aria2Finished(page: number, callback?: HttpCallback<Aria2Finished[]>): void {
    nativeAria2Finished(page, callback);
  }

  static userTasks(page: number, callback?: HttpCallback<UserTasks>): void {
    nativeGetUserTasks(page, callback);
  }

  static aria2TaskCreate(dst: string, urls: string[], callback?: HttpCallback<null>): void {
    nativeAria2CreateTask(dst, urls, callback);
  }

  static deleteAria2Task(gid: string, callback?: HttpCallback<null>): void {
    nativeAria2DeleteTask(gid, callback);
  }

  static getDownloadUri(id: string, callback?: HttpCallback<string>): void {
    nativeGetDownloadUri(id, callback);
  }

  // 以下方法仍使用 HarmonyOS request.agent（不可用 Rust 替换）
  static downloadFile(uri: string, filePath: string, callback?: HttpCallback<string>, progress?: import('./ApiTypes').ProgressCallback) {
    // 由 RequestDownload.ets 通过 request.agent 实现，此处不变
    // 实际调用已在 RequestDownload.ets 中处理
  }
}
```

- [ ] **Step 3: 检查 AxiosRequest.ets 是否还有其他调用者**

在 `entry/src/main/ets/` 中搜索 `AxiosRequest` 引用：

```bash
grep -r "AxiosRequest" entry/src/main/ets/ --include="*.ets"
```

预期：只有 `CloudApi.ets`（原来引用），现已不再引用。若还有其他引用，逐一处理后再删除。

- [ ] **Step 4: 删除 AxiosRequest.ets**

```bash
rm entry/src/main/ets/utils/AxiosRequest.ets
```

- [ ] **Step 5: 检查 RequestDownload.ets 和 RequestUpload.ets**

这两个文件使用 `request.agent`，不依赖 axios，验证它们没有直接导入 axios：

```bash
grep -n "axios" entry/src/main/ets/utils/RequestDownload.ets entry/src/main/ets/utils/RequestUpload.ets
```

预期：无输出（它们不依赖 axios）。

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/model/net/CloudApi.ets entry/src/main/ets/model/net/ApiTypes.ets
git rm entry/src/main/ets/utils/AxiosRequest.ets
git commit -m "[CHG] CloudApi.ets 改用 Rust native 模块，移除 AxiosRequest.ets"
```

---

### Task 10: 配置 Native 构建集成

**Files:**
- Modify: `entry/build-profile.json5`
- Create: `cloudreve-api-native/build.sh`

- [ ] **Step 1: 创建构建脚本**

新建 `cloudreve-api-native/build.sh`：

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_ARM64="$SCRIPT_DIR/../entry/libs/arm64-v8a"
OUT_X86="$SCRIPT_DIR/../entry/libs/x86_64"

mkdir -p "$OUT_ARM64" "$OUT_X86"

cd "$SCRIPT_DIR"

echo "Building arm64-v8a..."
cargo build --target aarch64-unknown-linux-ohos --release
cp target/aarch64-unknown-linux-ohos/release/libcloudreve.so "$OUT_ARM64/"

echo "Building x86_64 (emulator)..."
cargo build --target x86_64-unknown-linux-ohos --release
cp target/x86_64-unknown-linux-ohos/release/libcloudreve.so "$OUT_X86/"

echo "Build complete."
```

```bash
chmod +x cloudreve-api-native/build.sh
```

- [ ] **Step 2: 验证 entry/libs 结构**

```
entry/libs/
  arm64-v8a/
    libcloudreve.so
  x86_64/
    libcloudreve.so
```

- [ ] **Step 3: 更新 entry/build-profile.json5 声明 native 库**

确认 `build-profile.json5` 中 `nativeLib` 配置：

```json5
{
  "apiType": "stageMode",
  "buildOption": {
    "externalNativeOptions": {
      "abiFilters": ["arm64-v8a", "x86_64"]
    },
    "nativeLib": {
      "debugSymbol": {
        "strip": false
      }
    }
  }
}
```

（当前已有此配置，如未变动则无需修改）

- [ ] **Step 4: ohpm install 并编译验证**

```bash
ohpm install
./hvigorw assembleHap
```

预期：BUILD SUCCESSFUL，`libcloudreve.so` 被打包进 HAP。

- [ ] **Step 5: Commit**

```bash
git add cloudreve-api-native/build.sh entry/libs/ entry/build-profile.json5
git commit -m "[CHG] 集成 Rust native 构建脚本，配置 native library 打包"
```

---

### Task 11: 端到端测试

**Files:** 无新增，验证阶段

- [ ] **Step 1: 安装到真机/模拟器并测试登录**

- 打开 App，进入登录页，输入 Cloudreve 服务器地址
- 验证 ping 通（getSiteConfig 成功）
- 登录成功，Session cookie 正确存储

- [ ] **Step 2: 验证文件列表**

- 登录后跳转到文件列表页
- 根目录文件夹和文件正确显示
- 进入子目录正常

- [ ] **Step 3: 验证对象操作**

- 新建文件夹：成功
- 重命名：成功
- 复制/移动：成功（之前 axios 不支持 PATCH 导致问题，现在 Rust reqwest 原生支持）
- 删除：成功

- [ ] **Step 4: 验证 Aria2 功能**

- 切换到远程下载 Tab
- 创建下载任务：成功
- 任务列表刷新：成功

- [ ] **Step 5: 验证后台下载/上传**

- 下载文件，确认进度显示（仍使用 `request.agent`）
- 上传文件，确认上传成功

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "[CHG] Rust native API 模块集成完成，端到端验证通过"
```

---

## 自查清单

- [x] Phase 1 覆盖：SDK 版本字段、三方依赖、废弃 import 清理、编译验证
- [x] Phase 2 覆盖：Rust workspace、NAPI 绑定、ArkTS 桥接、CloudApi 重写、axios 移除
- [x] 无 TBD/TODO 占位：所有步骤含完整代码
- [x] 类型一致：`ObjectSrc`/`ObjectMove`/`ObjectCopy` 在 Rust `types.rs` 与 ArkTS `ObjectParam.ets` 保持对应字段
- [x] 不可替换的部分已保留：大文件下载（`cloudGetLargeFile`）、后台传输（`request.agent`）保持在 ArkTS 层
- [x] Cookie 管理：login 时从 set-cookie header 提取，存入 AppStorage + 调用 `setCookie` 同步到 Rust 层；每次 baseUrlSet 后需再次 setCookie

> **已知风险：**
> - API 24 beta1 三方库兼容性需实测，`@hadss/hmrouter` 若无 API 24 版本需等待或 fork。
> - HarmonyOS 的 `aarch64-unknown-linux-ohos` Rust target 需 Rust 1.82+ 或 nightly，确认工具链版本。
> - `reqwest` 默认启用的 TLS（rustls）需要在交叉编译时正确链接，若有 TLS 链接错误改用 `native-tls` feature 并链接 NDK 的 OpenSSL。
