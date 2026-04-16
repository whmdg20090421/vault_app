# Add File Picker For Encryption Spec

## Why
The user needs a system file picker in the "加密" (Encryption) navigation bar to select folders or files. This is a prerequisite for a future encryption feature. It requires requesting "All files access" (MANAGE_EXTERNAL_STORAGE) and storage permissions dynamically only when needed, not on app startup.

## What Changes
- Add `file_picker` and `permission_handler` dependencies.
- Update `AndroidManifest.xml` to include `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, and `MANAGE_EXTERNAL_STORAGE` permissions.
- Replace the placeholder `_TitlePage(title: '加密')` in `lib/main.dart` with a new `EncryptionPage`.
- Implement a beautiful UI in `EncryptionPage` that matches both the default and cyberpunk themes.
- Implement permission request logic that triggers only when the user attempts to pick a file or folder.
- Implement system file/folder picking logic and display the selected path in the UI.

## Impact
- Affected specs: None
- Affected code:
  - `pubspec.yaml`
  - `android/app/src/main/AndroidManifest.xml`
  - `lib/main.dart`
  - `lib/encryption/encryption_page.dart` (New file)

## ADDED Requirements
### Requirement: Dynamic Permission Request
The system SHALL request storage permissions (`MANAGE_EXTERNAL_STORAGE` for Android 11+ and `READ/WRITE_EXTERNAL_STORAGE` for older versions) only when the user clicks the file or folder selection button, not when the app starts.

#### Scenario: Success case
- **WHEN** user clicks "Select File" or "Select Folder" button for the first time
- **THEN** the system prompts for storage permission/all files access
- **WHEN** permission is granted
- **THEN** the system opens the file picker

### Requirement: File and Folder Selection
The system SHALL allow the user to select either a single file or a folder using the system file picker, and display the selected path on the screen to prepare for future encryption features.

#### Scenario: Success case
- **WHEN** user selects a file or folder
- **THEN** the UI updates to display the selected path beautifully.
