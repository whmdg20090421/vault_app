# Checklist

- [x] Sync Task Data Models (`SyncTask`, `SyncFileItem`) are implemented and support status, retry counts, and direction/strategy tracking.
- [x] User can successfully select a local vault, enter the password, and select a local folder to sync.
- [x] "Auto-Match" button correctly finds the corresponding WebDAV folder or gracefully falls back to manual selection.
- [x] User can select Sync Direction (Cloud->Local, Local->Cloud) and Sync Strategy (Overwrite, Merge, Skip).
- [x] Sync engine transfers files using Dart Isolates without blocking the UI.
- [x] Interrupted file transfers are correctly caught, partial data is discarded, and the file is queued for a full retry.
- [x] A file that fails 3 consecutive times is permanently paused and requires manual resumption.
- [x] A sync task is automatically paused if 10 consecutive files fail.
- [x] "Cloud Drive" (云盘) navigation bar shows a progress icon when tasks are active.
- [x] Progress panel displays the hierarchical folder structure, exact file counts, and percentage.
- [x] "Pause All" and "Start All" buttons in the progress panel correctly pause and resume the sync engine.
