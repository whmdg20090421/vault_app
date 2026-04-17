# Fix Version, WebDAV, and Encryption Progress Spec

## Why
1. The app version displayed in the built APK is out of sync with the GitHub release version (e.g., showing 1.2.0 instead of 1.2.5).
2. The WebDAV connection fails with DNS resolution errors ("Failed host lookup"), rendering cloud drive syncing useless.
3. The encryption progress bar gets stuck at 0.0% during large file operations, caused by excessive nested isolate spawning and unchecked progress reporting freezing the UI or crashing silently.

## What Changes
- **Version Sync**: Update `android/app/build.gradle.kts` to correctly read `versionName` and `versionCode` from Flutter's generated environment instead of relying on a hardcoded or misconfigured `version.properties` file.
- **WebDAV Rewrite**: Completely refactor `WebDavClientService` using the official `webdav_client` package. This eliminates manual XML parsing and Dio configuration, ensuring robust DNS resolution and standardized error handling.
- **Encryption Progress & Performance Fix**: Refactor `ChunkCrypto` to remove the catastrophic per-chunk `Isolate.run` (which spawned thousands of isolates). Provide synchronous cryptographic methods for `EncryptedVfs` to use, since file operations are already offloaded to a single background isolate. Throttle progress reporting (`sendPort.send`) to prevent flooding the main UI thread.

## Impact
- Affected specs: App Versioning, Cloud Sync (WebDAV), Vault Explorer (Import/Export).
- Affected code: `android/app/build.gradle.kts`, `lib/cloud_drive/webdav_client_service.dart`, `lib/encryption/utils/chunk_crypto.dart`, `lib/encryption/vault_explorer_page.dart`.

## ADDED Requirements
### Requirement: Automated Versioning
The Android build system SHALL read the version dynamically from `pubspec.yaml` via Flutter's default properties.

### Requirement: Robust WebDAV Connection
The WebDAV client SHALL handle network connections reliably using standard libraries and provide actionable error messages (e.g., "网络连接失败" or "认证失败").

### Requirement: Real-time Encryption Progress
The encryption process SHALL report its progress in real-time without blocking the main thread. 
#### Scenario: Success case
- **WHEN** user imports a large file (e.g., 100MB+) into the vault
- **THEN** the encryption occurs efficiently in a single background isolate, and the progress UI updates smoothly from 0% to 100%.

## REMOVED Requirements
### Requirement: Custom Dio WebDAV Implementation
**Reason**: The custom implementation using Dio and manual XML parsing is failing DNS resolution and edge cases.
**Migration**: Replace entirely with the `webdav_client` library.