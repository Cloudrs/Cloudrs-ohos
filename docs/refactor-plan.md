# Cloudrs HarmonyOS 6.1 UI Refactor Plan

Date: 2026-05-26

## Status

This document tracks the full modern cloud-drive UI refactor. The implementation is intentionally staged so each step stays buildable and keeps current CloudApi, HMRouter, login, download, and file operations compatible.

## Completed

- Photo backup center:
  - Rebuilt `TabPictures` from a placeholder into a local album backup center.
  - Added backup settings, local photo scan, system photo picker fallback, upload flow, persisted state, and path-scoped completed state.
  - Added native local-file upload support with remote directory creation and upload policy resolution.
- Runtime permissions:
  - Added `READ_IMAGEVIDEO`, `WRITE_IMAGEVIDEO`, and `GET_NETWORK_INFO` configuration.
  - Added runtime photo permission request before scanning.
- Navigation foundation:
  - Upgraded project SDK target and compatible SDK to HarmonyOS `6.1.1(24)` after confirming local DevEco SDK API 24 support.
  - Added modern cloud design tokens in `CloudThemeToken`.
  - Added resource colors for cloud surfaces, text, line, primary, danger, and success states.
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
  - Migrated Mine page background, card radius, core text colors, storage card, and list rows to the shared tokens.
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
  - Migrated shared `PathSelectSheet` background, header, selected directory state, and folder rows to shared theme tokens.
  - Migrated file detail, upload source, download task, and upload task sheets/panels to shared theme tokens.
  - Migrated Login page background, input containers, OTP boxes, action buttons, and text colors to shared theme tokens.
  - Fixed Login page post-login route target type by falling back to `HOME_PAGE` when `nextPage` is null.
  - Migrated `CommonTitle` to shared theme tokens.
  - Migrated About page to shared theme tokens.
  - Migrated Image preview top bar to shared theme tokens while preserving black preview content.
  - Removed Image preview `ArrayBuffer | null` save/share warning by guarding empty image data.
  - Applied `CloudActionButton` to the Offline Download create-task action.

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

## Home And Navigation Todo

- Validate floating tab bar on:
  - Phone portrait.
  - Tablet landscape.
  - 2-in-1 wide viewport.
- Add motion only where it improves clarity, such as selected tab transition.

## File Page Todo

- Preserve current operations:
  - Directory navigation, refresh, sorting, grid/list toggle, thumbnails, details, rename, copy, move, delete, and download.
- Completed so far:
  - File page is now wrapped by `CloudScaffold`.
  - Header/search/transport/title/menu surfaces use shared theme tokens.
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

## Photo Backup Todo

- Add a permission-state hint when scan count looks lower than expected.
- Add sync-all waiting flow instead of fixed small batches.
  - First pass completed: manual backup now processes the full current waiting/failed queue instead of a fixed 5-item slice, and shows current batch progress in the header/subtitle.
- Add pause/cancel controls for backup.
  - First pass completed: backing-up state now has a pause action. It finishes the current image, stops before the next queued image, and can resume from remaining waiting items.
- Add duplicate remote filename behavior: skip, overwrite, or auto-rename.
- Add remote existence verification before upload.
- Add backup history grouped by remote path.
- Add cleanup/migration for legacy `photoBackupDoneIds` once path-scoped records are stable.
- Add better UI for partial permission, no network, empty path, and upload failure.

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
  - Use a quieter account header.
  - Use tokenized cards and list rows.
  - Improve storage panel spacing and typography.

## Login Page Todo

- Preserve current flow:
  - Site binding.
  - Account login.
  - 2FA.
  - Failure prompts.
- Modernize UI:
  - Simplify brand area: first pass completed.
  - Normalize site URL, protocol, username, password, and 2FA input containers: first pass completed.
  - Keep keyboard avoidance behavior.

## About And Preview Todo

- Completed so far:
  - About page uses shared background, surface, line, radius, and text tokens.
  - Image preview keeps the black viewing area and uses tokenized top-bar actions.
  - Image preview save/share now guards empty image data before writing.
- Remaining:
  - Consider migrating image preview deprecated `getContext` calls to newer context access patterns.

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
