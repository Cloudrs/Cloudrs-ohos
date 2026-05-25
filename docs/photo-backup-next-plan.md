# Photo Backup Refactor Plan

Date: 2026-05-26

## Completed

- Rebuilt the Pictures tab into a photo backup dashboard with scan, waiting, uploading, failed, and completed sections.
- Added backup settings for enable switch, remote backup path, Wi-Fi only mode, any-network mode, and auto backup.
- Replaced the settings sheet with an inline settings panel because sheet interaction was unreliable on the emulator.
- Added runtime photo permission request for `READ_IMAGEVIDEO`.
- Added media scan through `photoAccessHelper` and a system photo picker fallback for selected-photo permission cases.
- Added persisted backup settings, done IDs, and photo records.
- Added local media backup upload by copying the selected media URI to cache and uploading through native Cloudreve API.
- Added native upload support with remote directory creation and upload policy resolution.
- Added path-scoped backup completion state so changing the remote path lets the same local photos sync again.
- Added emulator-friendly network handling so Wi-Fi-only backup can be switched to any network.

## Known Behavior

- If the system photo permission is limited to selected photos, automatic scan can only see authorized photos. Use "选择图片加入备份" to add more photos through the system picker.
- Legacy completed IDs without a path are treated as completed only for the default path `/Photos/Camera`.
- New completed IDs are stored as `<remotePath>|<photoId>`, so each backup path has independent sync state.

## Next Tasks

- Add a permission-state hint in the UI when scan count is lower than expected, guiding users to grant full access or use the picker.
- Add a "sync all waiting" flow instead of the current small batch behavior, with cancel/pause controls.
- Add duplicate remote filename handling, such as overwrite, skip, or auto-rename.
- Add progress from the native upload layer if the native API can expose upload bytes.
- Add background/automatic backup scheduling after app startup and network changes.
- Add a remote verification step that checks whether a file already exists in the selected path before upload.
- Add a backup history view grouped by remote path.
- Add cleanup/migration for old `photoBackupDoneIds` after path-scoped records are stable.
- Polish UI states for partial permission, no network, empty remote path, and upload failure.
- Add focused tests or manual verification notes for scan, picker, path switch, and retry flows.

## Verification Checklist For Next Session

- Fresh install: enable backup, grant full photo permission, scan local photos.
- Limited permission: grant only one photo, confirm picker can add additional photos.
- Backup to `/Photos/Camera`, confirm completed count increases.
- Switch to another remote path, confirm completed photos become waiting.
- Backup to the new path, confirm the new path has its own completed state.
- Switch back to `/Photos/Camera`, confirm old completed state is restored.
- Toggle Wi-Fi only on emulator and confirm any-network mode resumes backup.
