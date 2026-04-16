# Tasks

- [x] Task 1: Create Sync Task Data Models
  - [x] SubTask 1.1: Define `SyncTask` and `SyncFileItem` models to track sync direction, strategy, retry counts (max 3), and status (pending, syncing, failed, paused, completed).
  - [x] SubTask 1.2: Implement local storage caching (e.g., SharedPreferences or SQLite) for saving and recovering sync task states.

- [x] Task 2: Implement Sync Configuration UI
  - [x] SubTask 2.1: Build the vault selection and password decryption modal for the sync flow.
  - [x] SubTask 2.2: Build the local folder selection UI inside the decrypted vault.
  - [x] SubTask 2.3: Build the "Auto-Match" logic and UI to find the corresponding WebDAV folder, with fallback to manual WebDAV folder selection.
  - [x] SubTask 2.4: Build the options UI for Sync Direction (Cloud->Local, Local->Cloud) and Sync Strategy (Overwrite, Merge, Skip).

- [x] Task 3: Develop the Sync Engine
  - [x] SubTask 3.1: Implement Isolate-based background processing for file transfers using the native `HttpClient`.
  - [x] SubTask 3.2: Implement file-level error handling: on interruption, discard partial data and reset retry count. Pause file if consecutive failures >= 3.
  - [x] SubTask 3.3: Implement task-level error handling: pause the entire task if consecutive file failures >= 10.

- [x] Task 4: Build Cloud Drive Progress UI
  - [x] SubTask 4.1: Add a dynamic progress icon to the "Cloud Drive" (云盘) navigation bar, mirroring the "Encryption" (加密) tab's progress bar rules.
  - [x] SubTask 4.2: Build the detailed progress panel showing folder tree, file counts, and percentage progress.
  - [x] SubTask 4.3: Add "Pause All" and "Start All" (一键全部开启) global control buttons in the progress panel.
  - [x] SubTask 4.4: Add manual start/resume buttons for individual failed files.

# Task Dependencies
- [Task 2] depends on [Task 1]
- [Task 3] depends on [Task 1]
- [Task 4] depends on [Task 3]
