# Cloudrs

English | [简体中文](README.md)

[![Version](https://img.shields.io/github/v/tag/Cloudrs/Cloudrs-ohos?label=version&sort=semver)](https://github.com/Cloudrs/Cloudrs-ohos/tags)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-6.1.0(23)-1F6FEB)](https://www.harmonyos.com/)

Cloudrs is a **native HarmonyOS Next client** for [Cloudreve](https://github.com/cloudreve/Cloudreve) cloud storage. The UI is written in ArkTS, the networking layer is implemented in Rust, and both Cloudreve V3 / V4 server APIs are supported.

- **Bundle**: `com.dreamflytech.cloudrs`
- **Target SDK**: HarmonyOS 6.1.0(23)

## Features

- **File management** — directory browsing, search, upload / download, rename, move, delete, share-link management
- **Album** — cloud photo / video waterfall browsing, full-screen preview, video playback, save to local album
- **Album backup** — automatic backup of local album to the cloud, with resume-on-restart and reconciliation against cloud deletions
- **Remote download** — integrates with the server-side Aria2 offline downloader to create / manage download tasks
- **Multi-account** — locally encrypted credential storage for multiple users (S4 security level), one-tap switching
- **Background transfer** — background upload / download queues built on the system `request.agent`, up to 5 concurrent tasks
- **Responsive layout** — adapts to both phone and 2in1 (tablet / PC) form factors, auto-switching layout on wide screens
- **Security** — biometric unlock, privacy window (screenshots disabled)

## Architecture

```
┌──────────────────────────────────────────┐
│  ArkTS UI (entry)                        │
│  · Custom CloudRouter (NavPathStack) nav │
│  · @ObservedV2/@Trace reactive state     │
│  · relationalStore + sendablePreferences│
├──────────────────────────────────────────┤
│  Rust Native (cloudreve-api-native)      │
│  · napi-rs bindings → libcloudreve.so    │
│  · reqwest + tokio async networking      │
│  · wraps both Cloudreve V3 / V4 clients  │
└──────────────────────────────────────────┘
```

### Project structure

| Path | Description |
|---|---|
| `entry/` | Main HAP module (ArkTS sources, resources) |
| `entry/src/main/ets/pages/` | Pages: login, home (Files / Album / Remote Download / Me tabs), preview, search, etc. |
| `entry/src/main/ets/components/` | Reusable components (half-modal sheets, album grid, transfer list, etc.) |
| `entry/libs/` | Pre-built Rust native artifacts (`arm64-v8a` / `x86_64`, intentionally version-controlled) |
| `cloudreve-api-native/` | Rust napi binding layer source |
| `docs/` | Privacy policy, roadmap, etc. |

## Build

### Prerequisites

- DevEco Studio (HarmonyOS SDK 6.1.0(23))
- ohpm / hvigor (bundled with DevEco Studio)
- Rust toolchain (only when recompiling the native layer)

### Steps

1. **Configure signing**: copy `build-profile.json5.template` to `build-profile.json5`, then configure signing in DevEco Studio via *File > Project Structure > Signing Configs* (the real signing material is `.gitignore`-d — do not commit it).

2. **Build**: open the project in DevEco Studio and build via *Build > Build Hap(s)/APP(s)* (the project ships no `hvigorw` CLI wrapper; the IDE's built-in hvigor integration is sufficient). There are no third-party ohpm dependencies. The single `entry` module targets phone / tablet / 2in1; on 2in1 the desktop entry `EntryAbility` acts as a launcher that brings up `MainAbility` in status-bar mode.

3. **(Optional) Rebuild the Rust native layer**: `entry/libs/` already ships pre-built `.so` files, so Rust is not needed for day-to-day development. To modify native code, go into `cloudreve-api-native/` and run `build-ohos.ps1` (depends on the local `cloudreve-api` crate).

## License

This project is open-sourced under [**GPL-3.0**](LICENSE), Copyright © 2026 Dreamfly Tech and Cloudrs contributors.

- Both this repository (the Cloudrs client) and the submodule [`cloudreve-api-native`](cloudreve-api-native/) are licensed under GPL-3.0.
- The Cloudrs client is an independent work that talks to the Cloudreve server via HTTP API only; it is independent of the [Cloudreve server](https://github.com/cloudreve/Cloudreve) (also GPL-3.0).
- All third-party components used (CodeMirror, napi-rs, reqwest, tokio, etc.) are MIT / Apache-2.0 licensed — see the [third-party notices](THIRD_PARTY_NOTICES.md).

Any redistribution or network-serving of this work must comply with the GPL-3.0 terms, including open-sourcing all code.

## Related docs

- [Privacy Policy](docs/privacy.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Acknowledgements

- [Cloudreve](https://github.com/cloudreve/Cloudreve) — the excellent open-source cloud storage program
- [napi-rs](https://napi.rs/), [reqwest](https://github.com/seanmonstar/reqwest), [tokio](https://tokio.rs/) and other Rust open-source components (full list in the [third-party notices](THIRD_PARTY_NOTICES.md))
