# Cloudrs HarmonyOS 6.1 UI Refactor Plan

Date: 2026-05-26

## Status

This document tracks the full modern cloud-drive UI refactor. The implementation is intentionally staged so each step stays buildable and keeps current CloudApi, HMRouter, login, download, and file operations compatible.

## Completed

- Photo backup center:
  - Rebuilt `TabPictures` from a placeholder into a local album backup center.
  - Added backup settings, local photo scan, system photo picker fallback, upload flow, persisted state, and path-scoped completed state.
  - Added native local-file upload support with remote directory creation and upload policy resolution.
  - Added a permission/scan-count hint with manual picker fallback when system album scanning appears incomplete.
- Runtime permissions:
  - Added `READ_IMAGEVIDEO`, `WRITE_IMAGEVIDEO`, and `GET_NETWORK_INFO` configuration.
  - Added runtime photo permission request before scanning.
- Navigation foundation:
  - Upgraded project SDK target and compatible SDK to HarmonyOS `6.1.1(24)` after confirming local DevEco SDK API 24 support.
  - Added modern cloud design tokens in `CloudThemeToken`.
  - Added resource colors for cloud surfaces, text, line, primary, danger, and success states.
  - Added app-level light/dark appearance preference with persisted Harmony color mode and dark resource overrides.
  - Updated `HomePage` bottom Tabs to a floating translucent tab bar with selected capsule state.
- Shared UI components:
  - Added `CloudScaffold` for page background, top safe-area padding, scroll behavior, and bottom tab avoidance.
  - Added `CloudTopBar` for page title, subtitle, and icon actions.
  - Added `SectionHeader` for section titles and counters.
  - Added `EmptyState` for consistent empty-state layout and actions.
  - Added `GlassSurface` for translucent/outlined modern surfaces.
  - Added `CloudActionButton` for reusable icon and primary action buttons.
- Page token migration:
  - Migrated photo backup page surfaces, section headers, empty state, badges, and settings panel to the shared tokens/components.
  - Migrated photo backup page and Mine page to `CloudScaffold`.
  - Migrated Photo Backup scan/cache context access away from deprecated `getContext` usage.
  - Migrated File page upload/download and upload source picker context access away from deprecated component `getContext` usage.
  - Migrated Mine page background, card radius, core text colors, storage card, and list rows to the shared tokens.
  - Reworked Mine page account header, metrics, storage panel, settings rows, feedback row, and logout row into quieter tokenized surfaces.
  - Added Mine page appearance preference sheet and moved upload concurrency into the More Settings sheet.
  - Migrated File page to `CloudScaffold` while preserving its lazy grid layout.
  - Migrated File page header/title surfaces to the shared tokens.
  - Promoted File page upload, new-folder, view-toggle, and more actions into the visible top toolbar.
  - Removed the duplicate upload picker sheet from `TabFilesTitle`; uploads now route through the parent File page flow.
  - Migrated ObjectItem file/folder cards, thumbnail area, menu background, and text colors to shared tokens.
  - Added unified EmptyState for empty File directories.
  - Added File page loading and fetch-failure states with retry action.
  - Removed remaining `Function.bind` usage in File page callbacks.
  - Migrated Offline Download page to `CloudScaffold` and shared theme tokens.
  - Migrated Offline Download downloading, finished, failed, and queue cards to tokenized surfaces.
  - Migrated Offline Download empty states to the shared `EmptyState`.
  - Migrated Offline Download create-task and finished-detail sheets to shared theme tokens.
  - Added shared soft success/danger theme tokens and migrated Offline Download detail status surfaces to them.
  - Migrated shared `PathSelectSheet` background, header, selected directory state, and folder rows to shared theme tokens.
  - Migrated file detail, upload source, download task, and upload task sheets/panels to shared theme tokens.
  - Migrated File page context menu dividers and destructive action color to shared theme tokens.
  - Migrated Login page background, input containers, OTP boxes, action buttons, and text colors to shared theme tokens.
  - Migrated Login page window setup context access to component UI context.
  - Fixed Login page post-login route target type by falling back to `HOME_PAGE` when `nextPage` is null.
  - Removed app-side deprecated `getStringSync` usage from Mine page version display.
  - Migrated app-side `px2vp` usage in EntryAbility safe-area storage and Login page keyboard avoidance to `UIContext.px2vp`.
  - Added defensive error handling around persisted theme color-mode application.
  - Hardened local user database reads/writes with exception handling, result-set cleanup, and corrupt cached user JSON fallback.
  - Hardened background upload/download task queues with guarded search/show/pause/resume/create paths.
  - Migrated app toast helper from deprecated `promptAction.showToast` to `promptAction.openToast`.
  - Removed the third-party custom toast dependency from the app toast helper; warning/error tips now use the system toast path.
  - Migrated `ExitLifecycle` double-back exit context access away from deprecated `getContext(this)` usage.
  - Migrated file delete, upload conflict, offline task delete, and logout confirmation dialogs from third-party DialogHelper to `UIContext.showAlertDialog`.
  - Replaced File page rename/new-object text input dialogs with a tokenized in-page Sheet and removed app-side direct `@pura/harmony-dialog` usage.
  - Removed the unused direct `@pura/harmony-dialog` package dependency after migrating app dialogs to system APIs and tokenized sheets.
  - Replaced app-side `DateUtil` usage from `@pura/harmony-utils` with a small local `DateFormatUtil`.
  - Removed two background transfer utility imports from `@pura/harmony-utils` by adding local file-name extraction and dropping an unused upload import.
  - Added local `FileSystemUtil` and migrated upload queue plus photo backup cache copy/cleanup away from app-side `FileUtil`.
  - Removed the Home page preview decorator while narrowing the remaining HMRouter decorator warning under API 24 checks.
  - Migrated `CommonTitle` to shared theme tokens.
  - Migrated About page to shared theme tokens.
  - Migrated Image preview top bar to shared theme tokens while preserving black preview content.
  - Removed Image preview `ArrayBuffer | null` save/share warning by guarding empty image data.
  - Migrated Image preview save/share context access away from deprecated `getContext` usage.
  - Applied `CloudActionButton` to the Offline Download create-task action.
  - Added chunked cache-copy progress before upload so large selected files show a `准备上传` stage instead of blocking silently.
  - Added streaming progress callbacks for V4 remote `upload_urls` direct uploads, not only local storage uploads.
  - Migrated Image preview share temp-file write/cleanup and File page download completion move from third-party `FileUtil` to local `FileSystemUtil`.
  - Replaced photo backup Wi-Fi detection from third-party `NetworkUtil` with local `NetworkStateUtil` backed by Harmony `connection` APIs.
  - Migrated Photo Backup settings action and path row arrow to shared theme tokens.
  - Removed the direct `@pura/harmony-utils` package dependency after app-side imports were eliminated.

## In Progress

- Global design system:
  - `CloudThemeToken`, `CloudScaffold`, `CloudTopBar`, `SectionHeader`, `EmptyState`, `GlassSurface`, and `CloudActionButton` exist.
  - A few deeper legacy surfaces still need token migration.
- Full refactor plan alignment:
  - The original plan is now split into completed work and remaining work.
  - Feature pages still need visual migration after the base navigation and tokens are stable.

## Global Refactor Todo

- Upgrade SDK target:
  - Completed: local DevEco SDK reports HarmonyOS 6.1.1 / API 24.
  - Completed: `targetSdkVersion` and `compatibleSdkVersion` are now `6.1.1(24)`.
  - Completed: `hvigor assembleApp --no-daemon` passes on the upgraded SDK target.
- Add reusable UI components:
  - `GlassSurface` for translucent surfaces: completed.
  - `CloudActionButton` for icon and primary actions: completed.
- Migrate existing pages to tokens:
  - Replace scattered hardcoded colors.
  - Normalize card radius, section spacing, and text colors.
  - Keep existing interaction behavior unchanged while migrating visuals.
- Migrate Harmony 6.1 context access:
  - Completed: component pages now use component UI context for photo backup, image preview, file upload/download, upload source picker, and login window setup.
  - Completed: app-side deprecated `getStringSync` usage has been removed.
  - Completed: app-side deprecated `px2vp` usage has been migrated to `UIContext.px2vp`.
  - Completed: `UserDatabase` synchronous store operations are guarded and query result sets are closed safely.
  - Completed: background transfer queue operations are guarded against request-agent exceptions.
  - Completed: `ExitLifecycle` now uses HMRouter `HMLifecycleContext.uiContext` to access the host AbilityContext and guards exit failures.
- Reduce third-party utility dependency surface:
  - Completed: app-side `DialogHelper`, `FileUtil`, `DateUtil`, `NetworkUtil`, toast helper, and transfer helper imports from Pura utilities have been removed or replaced by local wrappers/system APIs.

## Home And Navigation Todo

- Validate floating tab bar on:
  - Phone portrait.
  - Tablet landscape.
  - 2-in-1 wide viewport.
- Add motion only where it improves clarity, such as selected tab transition: first pass completed for floating tab selection.

## File Page Todo

- Preserve current operations:
  - Directory navigation, refresh, sorting, grid/list toggle, thumbnails, details, rename, copy, move, delete, and download.
- Completed so far:
  - File page is now wrapped by `CloudScaffold`.
  - Header/search/transport/title/menu surfaces use shared theme tokens.
  - Upload/download picker and background transfer startup now use caller-provided UIAbilityContext.
  - File/folder item cards use shared theme tokens.
  - Empty directories show the shared empty-state component.
  - Loading and fetch-failure states are now represented in-page.
  - Back callback and more-menu callback no longer rely on `Function.bind`.
- Modernize top toolbar:
  - Current path / storage policy: title/subtitle retained; redundant policy chip removed.
  - Search: current-directory client-side filtering completed, including empty result state.
  - Upload: handled by the existing bottom-right global upload action.
  - New folder: promoted to visible icon action.
  - View toggle: promoted to visible icon action.
  - Transfer status: existing top transport badge retained.
  - More menu: retained for secondary actions and sorting.
- Rework object presentation:
  - Folder card: first tokenized pass completed.
  - Image thumbnail card: first tokenized pass completed.
  - Generic file card: first tokenized pass completed.
  - Compact list item: first pass completed with stable row height and tighter metadata.
- Improve states:
  - Loading: first pass completed.
  - Empty directory: first pass completed.
  - Fetch failure: first pass completed.
  - Refreshing: first pass completed with soft same-directory refresh that keeps existing content visible.
  - Long filename handling: first pass completed with middle truncation that preserves file extensions.
  - Upload preparation: first pass completed with chunked URI-to-cache copy progress and UI yielding for large files.
  - Remote direct upload progress: first pass completed with native streaming progress for `upload_urls` chunks.
  - Download completion file move: migrated to local `FileSystemUtil`.
  - Responsive grid columns: first pass completed for phone, tablet, and 2-in-1 widths.

## Photo Backup Todo

- Add a permission-state hint when scan count looks lower than expected: completed.
- Add sync-all waiting flow instead of fixed small batches.
  - First pass completed: manual backup now processes the full current waiting/failed queue instead of a fixed 5-item slice, and shows current batch progress in the header/subtitle.
- Add pause/cancel controls for backup.
  - First pass completed: backing-up state now has a pause action. It finishes the current image, stops before the next queued image, and can resume from remaining waiting items.
- Add duplicate remote filename behavior: first pass completed with skip-existing behavior.
- Add remote existence verification before upload: first pass completed for photo backup target directory.
- Add backup history grouped by remote path.
- Add cleanup/migration for legacy `photoBackupDoneIds` once path-scoped records are stable: first pass completed for known local photo records.
- Add better UI for partial permission, no network, empty path, and upload failure.
- Wi-Fi-only network check: migrated to local `NetworkStateUtil` using Harmony `connection` APIs.
- Responsive thumbnail grid: first pass completed for phone, tablet, and 2-in-1 widths.

## Offline Download Todo

- Preserve current operations:
  - Create offline download.
  - Poll downloading tasks.
  - Load completed tasks by page.
  - Load queue tasks.
  - Show detail.
  - Delete task.
- Completed so far:
  - Offline Download page is now wrapped by `CloudScaffold`.
  - Segmented control, top create action, task cards, empty states, create sheet, and finished-detail sheet use shared theme tokens.
  - Existing create, polling, pagination, queue, detail, and delete behavior is unchanged.
- Remaining UI work:
  - Show speed, file count, and save path more clearly in a denser task card layout: first pass completed.
  - Move create task to a top action or floating action button: completed with the existing top action.

## Mine Page Todo

- Preserve current operations:
  - User info.
  - Capacity info.
  - About page entry.
  - Logout.
  - Upload concurrency setting.
- Modernize UI:
  - Use a quieter account header: completed.
  - Use tokenized cards and list rows: completed.
  - Improve storage panel spacing and typography: completed.

## Login Page Todo

- Preserve current flow:
  - Site binding.
  - Account login.
  - 2FA.
  - Failure prompts.
- Modernize UI:
  - Simplify brand area: first pass completed.
  - Normalize site URL, protocol, username, password, and 2FA input containers: first pass completed.
  - Window/keyboard setup context access migrated to component UI context.
  - Keep keyboard avoidance behavior.

## About And Preview Todo

- Completed so far:
  - About page uses shared background, surface, line, radius, and text tokens.
  - Image preview keeps the black viewing area and uses tokenized top-bar actions.
  - Image preview save/share now guards empty image data before writing.
- Remaining:
  - Completed: migrated image preview deprecated `getContext` calls to component UI context access.

## Sheet Todo

- Modernize these sheets without changing behavior:
  - File detail sheet.
  - Path select sheet: first tokenized pass completed.
  - Upload source sheet: first tokenized pass completed.
  - Transfer progress sheet: upload/download panels first tokenized pass completed.
  - Photo backup settings surface.
- Keep sheet title and background treatment consistent.

## Verification Checklist

- Build with `hvigor assembleApp --no-daemon`.
- File page:
  - Directory enter/back, refresh, sort, grid/list, detail, rename, copy, move, delete, download.
- Photo backup:
  - Unauthorized, authorized, partial authorization, scan, picker add, enable/disable, path switch, Wi-Fi-only, any-network, backup retry.
- Offline download:
  - Create, refresh, pagination, details, delete.
- Mine:
  - User info, storage, about, logout, upload concurrency setting.
- Login:
  - Site binding, account login, 2FA, failure prompt.
- Layout:
  - Phone portrait, tablet landscape, 2-in-1 wide.
  - Safe area, floating tab bar, sheets, long text, grid columns.
