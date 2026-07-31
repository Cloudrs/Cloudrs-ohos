# Cloudrs

English | [简体中文](README.md)

[![Version](https://img.shields.io/github/v/tag/Cloudrs/Cloudrs-ohos?label=version&sort=semver)](https://github.com/Cloudrs/Cloudrs-ohos/tags)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-6.1.0(23)-1F6FEB)](https://www.harmonyos.com/)
[![AppGallery](https://img.shields.io/badge/download-AppGallery-red)](https://appgallery.huawei.com/app/detail?id=com.dreamflytech.cloudrs&channelId=SHARE&source=appshare)

> English | [中文](README.md)

Cloudrs is a **native HarmonyOS Next client** for [Cloudreve](https://github.com/cloudreve/Cloudreve) cloud storage. The UI is written in ArkTS, the networking layer is implemented in Rust, and both Cloudreve V3 / V4 server APIs are supported.

## <img src="docs/images/appgallery.png" width="26" align="top" alt="" /> Download

[**Huawei AppGallery**](https://appgallery.huawei.com/app/detail?id=com.dreamflytech.cloudrs&channelId=SHARE&source=appshare) — recommended for end users, install and go.

If you're a developer or want the latest features, see [Build](#build) below to compile from source.

- **Bundle**: `com.dreamflytech.cloudrs`
- **Target SDK**: HarmonyOS 6.1.0(23)

## Features

### File management

- **Browse & organize** — directory browsing, icon / list views, sort by name / time / size / type, multi-select batch actions
- **File operations** — new folder / new file, upload, download, rename, copy, move, delete, details
- **Search** — scoped to the current directory or all files; uses server-side search when available and falls back to a full traversal when it is not; keeps search history
- **Sharing** — create / manage share links with expiry and access code; or send files to other apps through the system share sheet

### Preview & editing

- **Images** — pinch-to-zoom and mouse-wheel zoom on 2in1; system AI vision (long-press to lift the subject or extract text); drag images out to other apps
- **Video** — built-in player with video thumbnails, fullscreen, and keyboard controls on PC / 2in1
- **Text / code** — CodeMirror 6 editor (line numbers, find, go-to-line, 16 language grammars), Markdown rendered preview and an editing toolbar; encoding auto-detection for UTF-8 / GBK / UTF-16, with binary files refused outright instead of shown as garbage
- **Edit & save in place** — the server baseline is compared before saving so concurrent edits are flagged first; a failed save is kept as a local draft you can restore next time
- **Save to system gallery** — cloud photos / videos can be saved to the device gallery in one tap

### Album

- **Unified album** — cloud and on-device media in one view, segmented by time / album, with waterfall thumbnails, full-screen preview and video playback
- **Automatic backup** — uploads the local album to the cloud, with configurable backup folder, Wi-Fi-only mode and concurrent upload count
- **Robustness** — resume-on-restart, background backup, network-state awareness, reconciliation against cloud deletions, original mtime preserved on upload

### Transfers

- **Background queues** — upload / download queues built on the system `request.agent`, running on after the app goes to background
- **Upload policy** — adjustable concurrency (3 by default, 10 max); name conflicts resolve as "skip existing" or "overwrite all"
- **Remote download** — integrates with the server-side Aria2 offline downloader, HTTP(S) and magnet links, task creation, progress and management

### Cross-device

- **Tap-to-share (Knock)** — already-downloaded files are sent as the file itself (media lands in the peer's gallery, other types in its Huawei Share folder); files not yet downloaded are sent as a share link
- **Tap-to-receive** — tablet / 2in1 can receive knocked files into the app sandbox
- **App continuation** — video playback hands off between phone / tablet / PC, carrying playback position and state

### Multi-device & personalization

- **Three form factors** — one module for phone / tablet / 2in1, layout switching on wide screens; status-bar background residency on 2in1
- **Appearance** — light / dark theme
- **Multi-account** — locally encrypted credential storage for multiple users (S4 security level), one-tap switching

### Security & diagnostics

- **App lock** — face / fingerprint unlock; while locked the privacy window keeps content out of the task switcher and screenshots
- **Logs & diagnostics** — built-in log viewer, one-tap copy of redacted diagnostics for bug reports

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
| `web-editor/` | CodeMirror 6 bundle source for the text editor; the built artifact is committed under `entry/src/main/resources/rawfile/editor/` |
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

4. **(Optional) Rebuild the editor bundle**: the CodeMirror artifact is committed under `entry/src/main/resources/rawfile/editor/`, so Node is not needed either. Only when changing `web-editor/src/main.js` or its dependencies, run `npm install && npm run build` in `web-editor/` and commit the regenerated bundle.

## License

This project is open-sourced under [**GPL-3.0**](LICENSE), Copyright © 2026 Dreamfly Tech and Cloudrs contributors.

- Both this repository (the Cloudrs client) and the submodule [`cloudreve-api-native`](cloudreve-api-native/) are licensed under GPL-3.0.
- The Cloudrs client is an independent work that talks to the Cloudreve server via HTTP API only; it is independent of the [Cloudreve server](https://github.com/cloudreve/Cloudreve) (also GPL-3.0).
- All third-party components used (CodeMirror, napi-rs, reqwest, tokio, etc.) are MIT / Apache-2.0 licensed — see the [third-party notices](THIRD_PARTY_NOTICES.md).

Any redistribution or network-serving of this work must comply with the GPL-3.0 terms, including open-sourcing all code.

## Related docs

- [Privacy Policy](docs/privacy.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## ☕ Sponsor

Cloudrs is a free, open-source project built and maintained in spare time. If it makes your life easier, consider buying the author a coffee ☕ — your support keeps the project going.

| WeChat | Alipay |
|:---:|:---:|
| <img src="docs/images/donate-wechat.png" width="220" alt="WeChat" /> | <img src="docs/images/donate-alipay.jpg" width="220" alt="Alipay" /> |

> Any amount is appreciated — thank you for your support ❤️

## Acknowledgements

- [Cloudreve](https://github.com/cloudreve/Cloudreve) — the excellent open-source cloud storage program
- [napi-rs](https://napi.rs/), [reqwest](https://github.com/seanmonstar/reqwest), [tokio](https://tokio.rs/) and other Rust open-source components (full list in the [third-party notices](THIRD_PARTY_NOTICES.md))
