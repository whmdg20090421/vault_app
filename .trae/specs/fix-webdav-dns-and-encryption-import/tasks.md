# Tasks
- [x] Task 1: Modify `EncryptedVfs` to support conditional filename encryption
  - [x] Add `encryptFilename` boolean parameter to `EncryptedVfs` constructor (default true).
  - [x] Update `_getRealPath`, `list`, `rename`, etc. to only encrypt/decrypt names if both `isEncrypted` and `encryptFilename` are true.
  - [x] Ensure content encryption/decryption (e.g., `uploadStream`, `open`) still runs as long as `isEncrypted` is true.
  - [x] Update instantiations of `EncryptedVfs` in `vault_explorer_page.dart` and `sync_config_page.dart` to pass `encryptFilename`.

- [x] Task 2: Fix isolates in `vault_explorer_page.dart`
  - [x] Update `doImportFolderIsolate` and `doImportFileIsolate` to ALWAYS instantiate `EncryptedVfs` (passing the `encryptFilename` parameter) instead of falling back to `LocalVfs`.
  - [x] Ensure `doExportFileIsolate` also uses `EncryptedVfs` properly.

- [x] Task 3: Add Task Progress Button to `VaultExplorerPage`
  - [x] Copy the `Icons.sync` IconButton from `EncryptionPage`'s AppBar to `VaultExplorerPage`'s AppBar.
  - [x] Ensure it opens the `EncryptionProgressPanel` bottom sheet exactly like it does in `EncryptionPage`.

- [x] Task 4: Enforce WebDAV Connection Testing
  - [x] In `webdav_edit_page.dart`, remove the default "Save" action or change it to "Test & Save".
  - [x] Add a "Connect" button in the AppBar actions.
  - [x] Implement a connection test function that trims URL/username/password, creates a temporary `WebDavService`, and calls `readDir('/')`.
  - [x] If the test fails, show a SnackBar or Dialog with the exact error. If it succeeds, save the config and pop the page.

- [x] Task 5: Simplify `WebDavBrowserPage`
  - [x] In `webdav_browser_page.dart`, hide or remove advanced feature buttons (like upload, delete, rename, etc.) and only keep the directory listing and navigation.

# Task Dependencies
- [Task 2] depends on [Task 1]
- [Task 3] can be done in parallel
- [Task 4] can be done in parallel
- [Task 5] can be done in parallel
