# Fix Version, WebDAV, and Encryption Progress Spec

## Why
1. The app version displayed in the built APK is not automatically syncing with the GitHub release version, causing confusion (still showing 1.2.0).
2. The WebDAV connection fails with DNS resolution errors and needs a robust rewrite to ensure reliable connectivity and clear error handling.
3. The encryption progress bar gets stuck at 0.0% during large file operations because the progress state is either not being emitted properly from the isolate or not correctly rebuilding the UI.

## What Changes
- **Version Sync**: Update `pubspec.yaml` to the target version and modify `build.gradle.kts` (or related build scripts) to parse the version correctly from `pubspec.yaml` instead of relying on a static `version.properties` file that gets out of sync.
- **WebDAV Rewrite**: Refactor `WebDavClientService` to use a more robust underlying mechanism (like `webdav_client` package or a properly configured `dio` client) that handles DNS resolution correctly and reports precise network errors.
- **Encryption Progress Fix**: Audit and fix `EncryptionTaskManager` and the Isolate logic in `VaultExplorerPage` so that `bytesProcessed` is correctly emitted via `SendPort` and triggers a state update (`notifyListeners`) in the UI.

## Impact
- Affected specs: App Versioning, Cloud Sync (WebDAV), Vault Explorer (Import/Export).
- Affected code: `pubspec.yaml`, `android/app/build.gradle.kts`, `lib/cloud_drive/webdav_client_service.dart`, `lib/encryption/services/encryption_task_manager.dart`, `lib/encryption/vault_explorer_page.dart`.

## ADDED Requirements
### Requirement: Automated Versioning
The Android build system SHALL read the `versionName` and `versionCode` directly from `pubspec.yaml` to ensure consistency between Flutter and native Android builds.

### Requirement: Robust WebDAV Connection
The WebDAV client SHALL handle network connections reliably, including proper DNS resolution, and provide actionable error messages (e.g., "DNS解析失败" or "连接超时").

### Requirement: Real-time Encryption Progress
The encryption process SHALL report its progress in real-time. 
#### Scenario: Success case
- **WHEN** user imports a large file into the vault
- **THEN** the encryption progress UI updates from 0% to 100% smoothly without freezing the main thread.

## REMOVED Requirements
### Requirement: Old WebDAV Logic
**Reason**: Current `WebDavClientService` logic is failing to resolve DNS and handle network edge cases properly.
**Migration**: Completely rewrite the service methods (`readDir`, `mkdir`, `upload`, etc.) using a more stable HTTP client configuration.