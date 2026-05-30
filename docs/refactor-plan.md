# Cloudrs HarmonyOS 6.1 UI Refactor Plan

Date: 2026-05-26
Last updated: 2026-05-31

## Status

The modern cloud-drive UI refactor has completed the local code-side implementation pass. The main architecture, SDK upgrade, shared design system, primary page migration, photo backup center, upload/download fixes, official HDS floating bottom navigation, official Navigation routing migration, sheet consistency pass, and deep tokenization cleanup are implemented and build-verified.

Estimated progress: about 90%.

The remaining work is external acceptance: real-device layout validation, API behavior confirmation for server-dependent edge cases, and full manual regression testing.

## Completed

### Foundation

- Upgraded `targetSdkVersion` and `compatibleSdkVersion` to HarmonyOS `6.1.1(24)` after confirming local DevEco SDK support.
- Verified `hvigor assembleApp --no-daemon` builds successfully on the upgraded SDK.
- Cleaned the app-side ArkTS warnings found during refactor verification; current build is successful with only known non-blocking warnings recorded in Pending Acceptance.
- Added modern cloud design tokens in `CloudThemeToken`.
- Added light/dark appearance preference with persisted Harmony color mode and dark resource overrides.
- Added runtime permissions for local photo backup:
  - `READ_IMAGEVIDEO`
  - `WRITE_IMAGEVIDEO`
  - `GET_NETWORK_INFO`
- Migrated major deprecated context access patterns to component UI context.
- Migrated app-side deprecated `getStringSync` and `px2vp` usages.
- Hardened local user database reads/writes, result-set cleanup, cached user JSON fallback, and background transfer queue exception paths.
- Reduced third-party utility usage:
  - Replaced app-side `DialogHelper`, `FileUtil`, `DateUtil`, `NetworkUtil`, toast helper, and transfer helper imports with system APIs or local wrappers.
  - Removed direct `@pura/harmony-utils` dependency after app-side imports were eliminated.
  - Removed unused direct `@pura/harmony-dialog` usage after migrating dialogs.

### Shared UI System

- Added shared components:
  - `CloudScaffold`
  - `CloudTopBar`
  - `SectionHeader`
  - `EmptyState`
  - `GlassSurface`
  - `CloudActionButton`
- Migrated shared component metrics, colors, spacing, and typography to `CloudThemeToken`.
- Added shared semantic colors for primary, danger, success, translucent surfaces, lines, text, transparent, and preview backgrounds.
- Completed a broad tokenization sweep across:
  - File page
  - Photo backup page
  - Offline download page
  - Mine page
  - Login page
  - About page
  - Image preview
  - Common title and file icon surfaces
  - Path select, upload source, transfer, and detail sheets
- Completed a follow-up deep visual scan and tokenized remaining non-token menu margins, divider widths, grid gaps, refresh offsets, scrollbar width, shadow values, and animation duration values in the main tabs/components.
- Aligned the offline-download nested path sheet with the shared sheet background token.
- Tokenized remaining overlay z-index, hidden opacity, and transition scale values.
- Tokenized shared disabled opacity and remaining offline task-card minimum height.
- Tokenized square thumbnail aspect ratio and path history border width.
- Tokenized page scaffold padding, avatar circle math, avatar border width, and photo backup preview-progress timing values.
- Tokenized string-based divider/outline widths and remaining visual zero branches in shared components and login layout.
- Centralized login 2FA code length as a semantic token used by validation, input length, and OTP cell rendering.
- Normalized sheet dismiss state cleanup for transport, offline download path selection, and Mine settings sheets.
- Tokenized remaining grid width-change thresholds, single-column grid templates, and key lazy-list cached counts in file/offline-download surfaces.
- Tokenized responsive column counts for file grids, offline-download detail metadata grids, and photo-backup thumbnail grids.
- Completed a final local hardcoded-value scan across ArkTS pages/components and moved remaining numeric/semantic values into `CloudThemeToken` or `Constant`.

### Home And Navigation

- Replaced the custom floating tab overlay with official `@kit.UIDesignKit` `HdsTabs`.
- Replaced third-party `@hadss/hmrouter` routing with official ArkUI `Navigation`, `NavPathStack`, and `NavDestination`.
- Added `CloudRouter` as the app routing compatibility layer for:
  - Login guard/session restore
  - Push/pop navigation
  - Root route replacement after login/logout
  - Home-page back handling and double-back exit
- Removed HMRouter page decorators, interceptor, lifecycle, Hvigor plugin, and package dependency.
- Bottom navigation now uses:
  - `HdsTabs`
  - `BottomTabBarStyle`
  - `barFloatingStyle`
  - adaptive `systemMaterialEffect`
  - `BlurStyle.Regular`
- Bottom navigation press light, floating material, and tab transition behavior are delegated to the system HDS component.
- Removed app-side `FloatingCloudTabBar` and the custom touch-light implementation.
- Tokenized bottom navigation margin and item padding.
- Added a reusable Codex skill for this pattern:
  - `C:\Users\wangx\.codex\skills\harmonyos-hds-floating-tabs`
- System bottom sheets stay above the bottom navigation without toggling it, avoiding delayed tab-bar restoration after gesture dismiss.
- File detail overlay still hides/collapses the bottom navigation when needed.

### File Page

- Wrapped the page with `CloudScaffold`.
- Migrated header, search, transport badge, title, menus, file rows, file cards, and thumbnail surfaces to shared tokens.
- Promoted new-folder, view-toggle, and more actions into the visible top toolbar.
- Removed duplicate upload picker from `TabFilesTitle`; uploads now route through the parent file page flow.
- Kept the global bottom-right upload entry as the single upload action.
- Added current-directory search with empty-result state.
- Added unified empty directory state.
- Added loading and fetch-failure states with retry.
- Preserved current operations:
  - Directory enter/back
  - Refresh
  - Sorting
  - Grid/list toggle
  - Thumbnails
  - Details
  - Rename
  - Copy
  - Move
  - Delete
  - Download
- Improved long filename handling with middle truncation that preserves file extensions.
- Added responsive grid columns for phone, tablet, and 2-in-1 widths.
- Added chunked URI-to-cache copy progress before upload.
- Added native streaming progress callbacks for V4 remote direct uploads.
- Migrated download completion file move to local `FileSystemUtil`.

### Photo Backup

- Rebuilt `TabPictures` into a local album backup center.
- Added:
  - Backup enable/disable setting
  - Remote backup path setting
  - Wi-Fi-only / any-network setting
  - Auto backup setting
  - Concurrent upload setting with default 5 parallel backup workers
  - Local photo scan
  - System photo picker fallback
  - Persisted backup settings
  - Path-scoped completed state
  - Path-level backup history
  - Manual backup of all current waiting/failed items
  - Pause/resume for backup queue
  - Failure retry
  - Failed photo retry no longer blocks the waiting backup queue
  - Empty path guard
  - Partial permission / scan-limited hint
  - Simulator-friendly network override
  - Direct any-network recovery action for waiting-network and failed backup states
  - Explicit reactive summary counters so scan results refresh immediately in the overview card
  - Forced summary-card refresh revision for local/completed/waiting/failed counter updates
  - Summary counter string snapshots bound directly to the overview card
  - Compact backup-history preview with overflow summary for many remote paths
  - Tokenized photo picker limit, section preview limits, and completed-progress constants
- Added native local-file upload support with remote directory creation and upload policy resolution.
- Added skip-existing behavior for duplicate remote filenames.
- Added remote existence verification before upload.
- Added a per-backup remote filename cache so album backup no longer re-queries the same remote directory for every photo.
- Added cached section preview arrays and incremental counter updates so local, waiting, completed, failed, and uploading counts refresh immediately during backup.
- Added a single reactive metric snapshot for the photo backup overview card, including the active uploading count, so scan and backup counters repaint together during concurrent uploads.
- Scoped photo backup counter, queue, and progress state mutations through `UIContext.runScopedTask()` so async upload callbacks repaint the active page reliably.
- Replaced photo backup metric tiles with direct state bindings, invalidated the `photos` state array on status changes, and added a tokenized low-frequency active-backup stats refresh timer.
- Reduced active-backup repaint flicker by keeping the stats refresh counter-only, removing forced summary remount IDs, and showing a token-limited recent-completed thumbnail preview during backup.
- Stabilized active-backup photo grids by freezing the waiting preview, batching recent-completed preview updates, and rendering photo section counters directly inside `TabPictures` instead of through the shared `SectionHeader` component.
- Removed the active-backup full stats polling pass and split photo preview grids into a dedicated component so counter changes do not keep rebuilding the waiting/completed image grids.
- Migrated photo backup preview grids to the same `LazyDataSource` + `LazyForEach` pattern used by the file list, with tokenized cached count and explicit grid height for effective nested-grid lazy loading.
- Migrated the photo backup page container from `Scroll + Column` to page-level `List` sections so backup counter updates no longer force a full column remeasure of all preview sections.
- Switched photo backup previews from direct `Image(photoUri)` rendering to visible-item system thumbnail `PixelMap` loading and a bounded thumbnail cache, matching the file list cache pattern more closely.
- Debounced photo-record persistence during active backup and flushes records on pause, completion, or page exit to reduce backup-page jank.
- Serialized local photo URI copy into the app cache and reduced copy chunk pressure so backup upload concurrency does not run multiple synchronous photo reads on the UI thread.
- During active backup, replaced large waiting/completed thumbnail grids and backup-history rendering with compact count rows to avoid repeated image decoding and large `doneIds` scans.
- Debounced `photoBackupDoneIds` persistence during active backup so thousands of completed photos no longer trigger synchronous growing preference writes per item.
- Moved album-backup photo URI copying into Harmony `taskpool` so heavy local file reads no longer execute on the ArkUI main thread.
- Restored the waiting-photo thumbnail preview during active backup after moving the heavy copy path off the main thread.
- Restored uploading-photo thumbnails for the small active worker set while keeping completed/history sections lightweight during backup.
- Let the photo backup page render its own tokenized scroll scaffold so high-frequency backup counters update directly in the page build tree.
- Migrated Wi-Fi-only network check to local `NetworkStateUtil` backed by Harmony `connection` APIs.
- Added cleanup/migration path for known legacy `photoBackupDoneIds` records.
- Added responsive thumbnail grid for phone, tablet, and 2-in-1 widths.

### Offline Download

- Wrapped the page with `CloudScaffold`.
- Migrated segmented control, top create action, downloading cards, finished cards, failed cards, queue cards, empty states, create sheet, and finished-detail sheet to shared tokens.
- Preserved current operations:
  - Create offline download
  - Poll downloading tasks
  - Load completed tasks by page
  - Load queue tasks
  - Show detail
  - Delete task where the API supports it
- Improved task cards to show speed, file count, save path, and status more clearly.
- Kept create task as the top action.
- Added responsive metric grid for finished task detail.
- Hardened failed-task detail parsing so plain text errors do not crash JSON parsing.

### Mine Page

- Wrapped the page with `CloudScaffold`.
- Reworked account header, user metrics, storage panel, setting rows, feedback row, and logout row into tokenized surfaces.
- Fixed user info and storage display paths encountered during development.
- Added appearance preference sheet with light/dark modes.
- Moved upload concurrency setting into the More Settings sheet.
- Removed the remaining `@Preview` decorator from `TabMine`.
- Preserved current operations:
  - User info
  - Capacity info
  - About page entry
  - Logout
  - Upload concurrency setting

### Login Page

- Migrated background, input containers, OTP boxes, action buttons, logo, footer buttons, and privacy text to shared tokens.
- Simplified brand/input layout while preserving current flow:
  - Site binding
  - Account login
  - 2FA
  - Failure prompts
- Migrated window/keyboard setup context access to component UI context.
- Fixed post-login route target type by falling back to `HOME_PAGE` when `nextPage` is null.

### About, Preview, And Sheets

- Migrated About page surfaces, spacing, logo, info rows, and typography to shared tokens.
- Migrated Image Preview top bar, error image, title, divider, save/share action area, and black preview background handling.
- Guarded Image Preview save/share when image data is empty.
- Migrated Image Preview save/share temp-file write/cleanup to local `FileSystemUtil`.
- Renamed the Image Preview component struct to `ImagePreviewPage` while preserving the route constant.
- Migrated these sheets/panels to shared tokens:
  - File detail
  - Path select
  - Upload source
  - Download task
  - Upload task
  - Offline download create task
  - Offline download finished detail
  - Photo backup settings
- Added loading, failed, retry, and empty-directory states to the shared path selection sheet used by file operations, photo backup, and offline download.
- Added `CloudDialogUtil` and migrated delete-task, delete-file, and logout confirmation dialogs to a shared confirm-dialog path.
- Added picker-opening progress, disabled duplicate taps, and failure feedback to the upload source sheet.
- Added explicit transfer status text and state-colored progress bars for upload and download task sheets.
- Replaced remaining task/photo progress totals with the shared percentage token.
- Extended `CloudDialogUtil` for two-action dialogs and migrated the upload conflict dialog to the shared dialog path.
- Removed stale file-card TODO markers and tokenized file-card context-menu preview scale values.
- Hardened image-share temp-file cleanup when share creation fails after writing the sandbox file.
- Normalized bottom safe-area padding for path selection, offline download creation, and offline download detail sheets with shared sheet spacing tokens.
- Added bottom safe-area padding and internal scrolling to the file detail sheet so long metadata stays usable on compact layouts.
- Normalized bottom safe-area padding for upload source, file input, Mine appearance, and Mine more-settings sheets.
- Normalized bottom safe-area padding for the file transfer progress sheet and aligned upload/download task list scroll behavior.
- Centralized upload concurrency min/default/max values and reused them in both the Mine setting UI and upload scheduler.
- Centralized image preview download size limit and added tokenized bottom padding for the image-preview save area.
- Centralized shared UI/transport semantics for segment selected indexes, empty task counts, HTTP OK status, and upload server-processing progress threshold.
- Centralized background upload/download polling interval, completion percentage, first-progress-size index, and empty progress-size guard.
- Centralized background request-agent method, title, save-prefix, gauge, and overwrite config values used by upload/download tasks.
- Centralized the exit double-back interval as a lifecycle behavior constant.
- Centralized offline-download polling interval seconds-to-milliseconds conversion and minimum interval.
- Centralized toast and toast-tip default durations.
- Replaced native login-result array indexes, document-save result access, cookie version prefixes, cookie expiration days, and home tab indexes with semantic constants/enums.
- Replaced transfer speed conversion, thumbnail HTTP status checks, permission result checks, first-item accesses, and upload storage-policy string checks with shared constants.
- Centralized login HTTP/HTTPS protocol menu labels, protocol schemes, protocol indexes, and common time conversion factors.
- Centralized file-name middle-truncation thresholds, byte-unit conversion, date zero-padding threshold, file-copy chunk/yield settings, and explicit upload completion progress.
- Replaced remaining transfer/offline-download/storage percentage calculations with shared completion/percentage constants.
- Replaced remaining login empty-field checks with shared zero token.
- Added `TransferStateUtil` to share upload/download transfer status colors, icons, text, speed formatting, and server-processing detection.
- Re-ran a final local scan for non-token colors, visual dimensions, radii, opacity, and large numeric values outside `CloudThemeToken` / `Constant`; no actionable local UI hardcodes remain.

## Pending Acceptance

### Build

- Re-run `hvigor assembleApp --no-daemon` after each implementation batch.
- Current build passes.
- Current build reports the obfuscation-disabled tooling warning.
- Current build does not report HMRouter custom decorator warnings.

### Device Layout

- Validate on phone portrait:
  - Safe area
  - HDS floating bottom navigation
  - Upload floating action
  - File and photo grids
  - Long filenames
  - System sheets and custom overlays
- Validate on tablet landscape:
  - Responsive grid columns
  - Top toolbar density
  - HDS bottom navigation width and bottom margin
  - Detail sheets
- Validate on 2-in-1 / wide viewport:
  - Grid density
  - Navigation placement
  - Sheet width and content density

### Functional Regression

- File page:
  - Directory enter/back
  - Refresh
  - Sort
  - Grid/list toggle
  - Detail
  - Rename
  - Copy
  - Move
  - Delete
  - Download
  - Upload progress for small, large, direct, and chunked uploads
- Photo backup:
  - Unauthorized
  - Authorized
  - Partial authorization
  - Scan
  - Picker add
  - Enable/disable
  - Remote path switch
  - Wi-Fi-only
  - Any-network
  - Auto backup
  - Manual backup
  - Pause/resume
  - Failure retry
- Offline download:
  - Create
  - Refresh
  - Pagination
  - Queue loading
  - Detail
  - Delete where supported by API
- Mine:
  - User info
  - Storage
  - Appearance preference
  - More settings
  - Upload concurrency
  - About
  - Logout
- Login:
  - Site binding
  - Account login
  - 2FA
  - Failure prompt

## Remaining Work

### Local Code

- No known local code-side implementation item remains from this refactor plan.
- Keep future UI changes tokenized through `CloudThemeToken`; do not add new hardcoded visual values in page code.

### Navigation

- Validate official HDS floating bottom navigation on real phone, tablet, and wide layouts.
- Tune only token values if bottom margin, tab height, or page avoidance feels off.
- Keep using official `HdsTabs.barFloatingStyle`; do not restore app-side custom light effects.

### File Page

- Verify file detail overlay still fully covers or hides bottom navigation when expected.
- Review copy/move/rename/delete dialog and sheet consistency after full regression.

### Photo Backup

- Verify path-scoped completed-state migration with more real albums and remote paths.
- Validate compact backup-history preview with real multi-path albums.

### Offline Download

- Confirm API behavior for deleting failed tasks; keep the current fallback if server returns `Task not found`.
- Validate card density with real long task names and multi-file tasks.

### Mine And Settings

- Review More Settings hierarchy after device testing.
- Polish appearance preference and setting rows if system/HDS components expose better API 24 styles.

### Sheets

- Validate final consistency across:
  - File detail sheet
  - Path select sheet
  - Upload source sheet
  - Transfer progress sheets
  - Photo backup settings sheet
  - Offline download detail sheet
- Confirm all sheets avoid bottom navigation correctly and have no delayed navigation restoration.

## Notes

- The official HDS floating navigation pattern is documented as a local Codex skill:
  - `harmonyos-hds-floating-tabs`
- For future bottom navigation work, use that skill and avoid rebuilding a custom floating tab bar.
- Current untracked local files are outside this plan unless explicitly added later:
  - `.arts/`
  - `CLAUDE.md`
  - `docs/superpowers/plans/2026-05-24-sdk24-and-rust-api.md`
