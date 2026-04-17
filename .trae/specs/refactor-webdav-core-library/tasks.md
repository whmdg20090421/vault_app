# Tasks

- [ ] Task 1: Initialize the core networking library based on `dom111/webdav-js` architecture.
  - [ ] SubTask 1.1: Create `WebDavFile` model (`lib/cloud_drive/webdav_new/webdav_file.dart`) to store `href`, `getcontentlength`, `getetag`, `resourcetype`, etc.
  - [ ] SubTask 1.2: Create `WebDavClient` (`lib/cloud_drive/webdav_new/webdav_client.dart`) encapsulating `Dio`, adding a Basic Auth interceptor, and a global error handler for `DioException`.
  - [ ] SubTask 1.3: Create `WebDavParser` (`lib/cloud_drive/webdav_new/webdav_parser.dart`) utilizing the `xml` package to parse `207 Multi-Status` responses, extracting properties, and handling `Uri.decodeFull`.

- [ ] Task 2: Implement the high-level WebDAV operations layer.
  - [ ] SubTask 2.1: Create `WebDavService` (`lib/cloud_drive/webdav_new/webdav_service.dart`) with methods for `readDir`, `upload` (PUT), `download` (GET), `mkdir` (MKCOL), `remove` (DELETE), and `move` (MOVE with `Destination` header).

- [ ] Task 3: Draft the Sync Engine skeleton.
  - [ ] SubTask 3.1: Create `SyncEngine` (`lib/cloud_drive/webdav_new/sync_engine.dart`) containing a suggested algorithm for incremental sync based on ETag/Last-Modified comparisons and utilizing `Future.wait` for concurrent operations.

- [ ] Task 4: Re-integrate with the UI and Virtual File System.
  - [ ] SubTask 4.1: Update `lib/vfs/standard_vfs.dart` to rely on the newly created `WebDavService`.
  - [ ] SubTask 4.2: Restore the network test and connection logic in `lib/cloud_drive/webdav_edit_page.dart` using the new `WebDavService`.
  - [ ] SubTask 4.3: Ensure `lib/cloud_drive/webdav_browser_page.dart` and `lib/cloud_drive/sync_config_page.dart` pass the proper client to `StandardVfs`.

# Task Dependencies
- [Task 2] depends on [Task 1]
- [Task 3] depends on [Task 2]
- [Task 4] depends on [Task 2]
