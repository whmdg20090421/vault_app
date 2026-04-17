# WebDAV Path Concatenation Bug Fix Plan

## 1. Summary
The user encountered a 404 error when attempting to navigate into the root directory of a WebDAV connection. The URL was incorrectly concatenated as `https://webdav.123pan.cn/webdav/webdav/`. This plan details the root cause and the necessary code modifications to strip the `baseUrl` path component from the server's XML response, ensuring accurate directory mapping and path construction.

## 2. Current State Analysis
- **`WebDavParser.parseMultiStatus`**: Currently compares the absolute `href` returned by the server (e.g., `/webdav/`) with the relative `requestedPath` (e.g., `/`). Because they don't match, it fails to filter out the root directory and treats it as a child folder named `webdav`.
- **UI Behavior**: The user sees this phantom `webdav` folder. Clicking it changes the current path to `/webdav/`.
- **`WebDavClient` / `Dio`**: When the UI requests `/webdav/`, Dio concatenates it with the `baseUrl` (`https://webdav.123pan.cn/webdav`), resulting in the duplicated `webdav/webdav/` path and a 404 error.

## 3. Proposed Changes

### 3.1. `lib/cloud_drive/webdav_new/webdav_parser.dart`
- **What**: Update the signature of `parseMultiStatus` to accept a third parameter: `String baseUrlPath`.
- **Why**: To provide the parser with the context needed to convert absolute server paths back into relative paths.
- **How**: 
  - Add `String baseUrlPath` to the method signature.
  - Inside the loop, extract the path from the `href`.
  - Strip the `baseUrlPath` prefix from the `href` to produce a `relativePath` (e.g., converting `/webdav/folder1/` to `/folder1/`).
  - Use `relativePath` for the `_isSamePath` check and as the `path` property for the returned `WebDavFile`.
  - Use `relativePath` instead of `href` to extract the `name`.

### 3.2. `lib/cloud_drive/webdav_new/webdav_service.dart`
- **What**: Pass the `baseUrlPath` to `WebDavParser.parseMultiStatus`.
- **Why**: To supply the necessary base path context for correct XML parsing.
- **How**: In `readDir(String path)`, extract the base path using `Uri.parse(client.dio.options.baseUrl).path` and pass it as the third argument to `parseMultiStatus`.

### 3.3. `lib/vfs/standard_vfs.dart`
- **What**: Pass the `baseUrlPath` to `WebDavParser.parseMultiStatus`.
- **Why**: To supply the necessary base path context for correct XML parsing during `stat` operations.
- **How**: In `stat(String path)`, extract the base path using `Uri.parse(service.client.dio.options.baseUrl).path` and pass it as the third argument to `parseMultiStatus`.

## 4. Assumptions & Decisions
- The `baseUrl` is guaranteed to be a valid URI from which the path can be extracted using `Uri.parse`.
- WebDAV servers return the `href` as an absolute path on the host (or a fully qualified URL). Stripping the `baseUrlPath` will reliably yield the relative path from the perspective of the WebDAV client.

## 5. Verification Steps
- Re-run the application and connect to the WebDAV server.
- Verify that the phantom "webdav" folder no longer appears in the root directory list.
- Navigate through folders to ensure no 404 errors occur and paths are correctly resolved without duplication.