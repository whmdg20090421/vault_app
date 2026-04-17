# Fix WebDAV DNS and Encryption Import Spec

## Why
Users are experiencing issues with WebDAV connections failing due to DNS resolution errors (`Failed host lookup`) and the lack of a proactive connection test before saving. Additionally, when importing folders into an encrypted vault with `encryptFilename` disabled, the system bypasses the encryption layer entirely, resulting in unencrypted files, instant completion (no CPU usage), and stuck progress indicators. Finally, users need easier access to the sync/encryption progress panel from within the Vault Explorer.

## What Changes
- Add a "Test/Connect" button in the WebDAV configuration page. It will trim inputs and perform a test request (PROPFIND) before allowing the user to save the configuration.
- Temporarily disable other advanced WebDAV features in the browser page, leaving only the directory listing functionality.
- Fix the encryption logic in `EncryptedVfs` to accept an `encryptFilename` parameter. This ensures file contents are ALWAYS encrypted even if filename encryption is disabled.
- Update `vault_explorer_page.dart` to always use `EncryptedVfs` in isolates (passing the `encryptFilename` flag), ensuring `import folder` and `import file` correctly encrypt contents.
- Copy the `Icons.sync` (Task Progress) button from `encryption_page.dart` to `vault_explorer_page.dart`'s AppBar.

## Impact
- Affected specs: WebDAV connection management, Vault Encryption Isolate.
- Affected code: `webdav_edit_page.dart`, `webdav_browser_page.dart`, `encrypted_vfs.dart`, `vault_explorer_page.dart`.

## ADDED Requirements
### Requirement: WebDAV Connection Testing
The system SHALL require the user to successfully test the WebDAV connection before saving the configuration.

#### Scenario: Success case
- **WHEN** user clicks "Connect" on the WebDAV edit page
- **THEN** the system trims inputs, tests the connection via a PROPFIND request, and if successful, saves the config.

### Requirement: Global Progress Access
The system SHALL provide access to the Encryption/Task Progress panel directly from the Vault Explorer page.

## MODIFIED Requirements
### Requirement: Vault Import Encryption
The system SHALL always encrypt file contents when importing files or folders into a vault, regardless of whether filename encryption is enabled or disabled.
