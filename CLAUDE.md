# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cloudrs is a HarmonyOS Next native client app for [Cloudreve](https://github.com/cloudreve/Cloudreve) cloud storage (API v3). Written in ArkTS (`.ets` files), built with hvigor, packaged as a single `entry` HAP module.

- **Bundle**: `com.dreamflytech.cloudrs`
- **Target SDK**: HarmonyOS 6.0.2(22), compatible with 6.0.0(20)

## Build & Development Commands

Build and run are primarily done through **DevEco Studio IDE**. CLI equivalents via the hvigor wrapper:

```bash
# Install dependencies
ohpm install

# Build debug HAP
./hvigorw assembleHap

# Build release HAP
./hvigorw assembleHap --mode release

# Run tests (ohosTest module)
./hvigorw test -p module=entry@ohosTest
```

Code linting uses the rules in `code-linter.json5` (`@performance/recommended` + `@typescript-eslint/recommended`). Run via DevEco Studio's "Code Linter" action or:
```bash
./hvigorw codeLinter
```

## Architecture

### Navigation

All navigation is managed by `@hadss/hmrouter`. Every page registers itself with `@HMRouter({pageUrl: '...'})`. Page URL constants live in `entry/src/main/ets/model/Constant.ets`.

- **Root**: `pages/Index.ets` wraps `HMNavigation` in Stack mode as the single navigation container.
- **Home**: `pages/HomePage.ets` — 4-tab layout: Files, Pictures, Remote Download (Aria2), Mine.
- **Login**: `pages/LoginPage.ets` — two-step flow: website URL → credentials.

Navigation guard: `interceptor/Interceptor.ets` (`LoginInterceptor`) runs on all non-login pages. It checks cookie validity against `UserDatabase`; if expired, redirects to login.

### API Layer

All Cloudreve API calls go through `model/net/CloudApi.ets` (static methods). The HTTP transport is `utils/AxiosRequest.ets`, which holds a singleton `axiosInstance` (axios) configured with the user's server base URL and cookie at login time.

**Callback pattern** — all API calls use `HttpCallback<T>`:
```ts
interface HttpCallback<T> {
  onStart?: () => void
  onSuccess: (data: T) => void
  onFailure: (msg: string) => void
}
```

`cloudPatch` uses `rcp` (RemoteCommunicationKit) instead of axios because axios lacks proper PATCH support.

### Data Persistence

| Store | Class | Purpose |
|---|---|---|
| SQLite (`relationalStore`) | `model/UserDatabase.ets` | User credentials, cookies, expiry, profile (security level S4) |
| Encrypted preferences (`sendablePreferences`) | `model/UserPreferences.ets` | Active user key |
| `AppStorage` | — | Runtime state: cookie, screen insets, version, tab height |

### Background Transfer

`utils/RequestDownload.ets` and `utils/RequestUpload.ets` use `@kit.BasicServicesKit`'s `request.agent` for background transfers. Both follow the same pattern:

- A wait queue is flushed every 2 seconds.
- Max 5 concurrent `request.agent.Task`s (`Constant.TASK_MAX`).
- Progress/completion/pause/resume/failure are reported via `FileModel.callback`.

### State Management

Reactive state uses `@ObservedV2` + `@Trace`. `DirFileInfo` in `model/net/ApiTypes.ets` is the primary observable model for file listings; it splits `objects` into `dirObjects` and `fileObjects` and handles sorting.

### Key Dependencies

| Package | Version | Use |
|---|---|---|
| `@ohos/axios` | 2.2.4 | HTTP client |
| `@hadss/hmrouter` | 1.0.0-rc.10 | Page navigation |
| `@pura/harmony-utils` | 1.2.4 | File utilities (`FileUtil`) |
| `@pura/harmony-dialog` | 1.0.6 | Dialog helpers |
| `@pura/spinkit` | 1.0.4 | Loading spinners |

The hvigor plugin `@hadss/hmrouter-plugin` (in `hvigor/hvigor-config.json5`) runs at build time to generate the router map from `@HMRouter` decorators.
