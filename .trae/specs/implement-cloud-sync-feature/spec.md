# Implement WebDAV Cloud Sync Feature Spec

## Why
Users need a robust synchronization mechanism to seamlessly transfer encrypted vaults between the local device and remote WebDAV cloud storage. Because WebDAV connections can be unstable and do not support resumable transfers, the sync engine must have strict retry limits, task-level pause/resume controls, and a dedicated progress UI to provide visibility into the synchronization status.

## What Changes
- **Local & Cloud Selection UI**: Add a sync configuration flow allowing the user to select an encrypted vault, enter the password to decrypt, select a specific local folder, and then auto-match or manually select the corresponding cloud folder.
- **Sync Options**: Add configuration options for Sync Direction (Cloud -> Local, Local -> Cloud) and Sync Strategy (Overwrite, Merge, Skip).
- **Sync Engine**: Implement an Isolate-based multi-threaded sync engine.
- **Error Handling & Retry Logic**: Implement a strict retry policy where an interrupted file transfer is marked as failed, queued for retry, and permanently paused after 3 consecutive failures. If 10 consecutive files fail, the entire task is paused.
- **Progress UI**: Add a progress taskbar on the "Cloud Drive" (云盘) navigation bar, identical in behavior to the encryption progress bar.
- **Global Task Controls**: Add "Pause All" and "Start All" buttons in the transfer interface to manage sync tasks.

## Impact
- Affected specs: Cloud Drive Management, Encryption Vault Management.
- Affected code:
  - `lib/cloud_drive/` (WebDAV sync engine, UI, and API integration)
  - `lib/encryption/` (Integration for vault decryption and folder selection)
  - `lib/models/` (Task and file queue models)
  - `lib/main_navigation.dart` (Progress bar overlay on Cloud Drive tab)

## ADDED Requirements

### Requirement: Sync Configuration Flow
The system SHALL provide a UI for users to configure a sync task.
#### Scenario: Success case
- **WHEN** user initiates a sync action.
- **THEN** the system prompts the user to select a local encrypted vault, enter the password to decrypt, and select a specific local folder.
- **THEN** the system provides an "Auto-Match" button to find the corresponding WebDAV folder.
- **THEN** if auto-match fails, the system allows manual selection of the cloud folder.
- **THEN** the system prompts for Sync Direction and Sync Strategy.

### Requirement: Sync Engine with Strict Retry Logic
The system SHALL transfer files using a multi-threaded engine without relying on resumable uploads/downloads.
#### Scenario: Transfer Interruption
- **WHEN** a file transfer is interrupted due to network issues.
- **THEN** the file is marked as failed, discarded, and placed in the waiting queue for a full re-transfer.
- **WHEN** a file fails 3 times consecutively.
- **THEN** the file is permanently paused and requires manual user intervention to resume.
- **WHEN** 10 consecutive files fail in a single task.
- **THEN** the entire sync task is paused automatically.

### Requirement: Cloud Drive Progress UI and Global Controls
The system SHALL display real-time sync progress in the Cloud Drive tab.
#### Scenario: Managing Sync Tasks
- **WHEN** a sync task is active.
- **THEN** a progress icon appears on the top right of the Cloud Drive navigation bar.
- **WHEN** the user opens the progress panel.
- **THEN** they see the folder-level progress tree and can use "Pause All" and "Start All" global buttons to control the tasks.
