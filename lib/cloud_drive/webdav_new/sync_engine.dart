import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'webdav_service.dart';
import 'webdav_file.dart';
import '../../encryption/services/local_index_service.dart';
import '../../models/sync_task.dart';
import '../cloud_drive_progress_manager.dart';

class _SyncJob {
  final SyncFileItem item;
  final Future<void> Function() execute;

  _SyncJob(this.item, this.execute);
}

/// 同步引擎，负责将 WebDAV 远端文件与本地目录进行双向同步
class SyncEngine {
  final WebDavService service;
  final String localDirPath;
  final int maxUploadConcurrency;
  final int maxDownloadConcurrency;
  final SyncDirection direction;

  SyncEngine({
    required this.service,
    required this.localDirPath,
    this.maxUploadConcurrency = 3,
    this.maxDownloadConcurrency = 3,
    this.direction = SyncDirection.twoWay,
  });

  /// 计算文件 SHA256 哈希
  Future<String> _calculateFileHash(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 扫描本地文件列表
  Future<void> _scanLocalFiles(Directory dir, Map<String, File> files) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        String relativePath = p.relative(entity.path, from: localDirPath).replaceAll(r'\', '/');
        if (!relativePath.startsWith('/')) relativePath = '/' + relativePath;
        files[relativePath] = entity;
      }
    }
  }

  /// 启动同步流程
  Future<void> sync(String remoteDir, {bool forceSync = false, SyncTask? task}) async {
    if (!remoteDir.startsWith('/')) remoteDir = '/' + remoteDir;
    print('Starting sync from remote: $remoteDir to local: $localDirPath with direction: $direction');

    // 1. 读取本地历史状态 (local_index.json)
    final localIndexService = LocalIndexService();
    final localIndex = await localIndexService.getLocalIndex(localDirPath);

    // 2. 扫描当前本地文件
    Map<String, File> currentLocalFiles = {};
    await _scanLocalFiles(Directory(localDirPath), currentLocalFiles);

    Set<String> localAdded = {};
    Set<String> localDeleted = {};
    Set<String> localModified = {};
    Set<String> localUnchanged = {};

    // 比较当前与历史索引
    for (var path in currentLocalFiles.keys) {
      if (!localIndex.containsKey(path)) {
        localAdded.add(path);
      } else {
        final indexInfo = localIndex[path] as Map<String, dynamic>;
        final file = currentLocalFiles[path]!;
        final stat = await file.stat();

        final indexSize = indexInfo['cipherSize'] ?? indexInfo['size'];
        final indexUpdatedAt = indexInfo['cipherUpdatedAt'] ?? indexInfo['updatedAt'];
        final indexHash = indexInfo['cipherHashSha256'] ?? indexInfo['hash'];

        if (stat.size != indexSize || stat.modified.toIso8601String() != indexUpdatedAt) {
          if (stat.size == indexSize) {
            final hash = await _calculateFileHash(file);
            if (hash == indexHash) {
              localUnchanged.add(path);
              continue;
            }
          }
          localModified.add(path);
        } else {
          localUnchanged.add(path);
        }
      }
    }

    for (var path in localIndex.keys) {
      if (!currentLocalFiles.containsKey(path)) {
        localDeleted.add(path);
      }
    }

    // 3. 处理移动与复制 (WebDAV 原生优化)
    Map<String, String> moves = {}; // newPath -> oldPath
    Map<String, String> copies = {}; // newPath -> oldPath

    if (localAdded.isNotEmpty && localDeleted.isNotEmpty) {
      Map<String, List<String>> hashToPaths = {};
      for (var entry in localIndex.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final map = Map<String, dynamic>.from(value as Map);
        final hash = map['cipherHashSha256'] ?? map['hash'];
        if (hash != null) {
          hashToPaths.putIfAbsent(hash, () => []).add(entry.key);
        }
      }

      for (var addedPath in localAdded.toList()) {
        final file = currentLocalFiles[addedPath]!;
        final stat = await file.stat();
        if (stat.size > 20 * 1024 * 1024) continue; // Skip hash for files > 20MB to prevent UI hang
        
        final hash = await _calculateFileHash(file);
        if (hashToPaths.containsKey(hash)) {
          final possibleOldPaths = hashToPaths[hash]!;
          String? chosenOldPath;
          for (var oldPath in possibleOldPaths) {
            if (localDeleted.contains(oldPath)) {
              chosenOldPath = oldPath;
              break;
            }
          }
          if (chosenOldPath != null) {
            moves[addedPath] = chosenOldPath;
            localAdded.remove(addedPath);
            localDeleted.remove(chosenOldPath);
          } else {
            copies[addedPath] = possibleOldPaths.first;
            localAdded.remove(addedPath);
          }
        }
      }
    }

    // 执行 MOVE 和 COPY
    if (direction == SyncDirection.twoWay || direction == SyncDirection.localToCloud) {
      for (var entry in moves.entries) {
        String newRemote = _buildRemotePath(remoteDir, entry.key);
        String oldRemote = _buildRemotePath(remoteDir, entry.value);
        print('Moving remote: $oldRemote -> $newRemote');
        try {
          await service.move(oldRemote, newRemote);
        } catch (e) {
          print('Move failed: $e');
        }
      }
      for (var entry in copies.entries) {
        String newRemote = _buildRemotePath(remoteDir, entry.key);
        String oldRemote = _buildRemotePath(remoteDir, entry.value);
        print('Copying remote: $oldRemote -> $newRemote');
        try {
          await service.copy(oldRemote, newRemote);
        } catch (e) {
          print('Copy failed: $e');
        }
      }
    }

    // 更新任务对象状态为同步中，避免用户以为卡在准备阶段
    if (task != null) {
      task.status = SyncStatus.syncing;
      task.startedAt = DateTime.now();
      CloudDriveProgressManager.instance.updateTask(task);
    }

    // 4. PROPFIND 获取云端状态并进行精准差异比对
    final syncTasks = <_SyncJob>[];
    await _syncRecursiveDir(remoteDir, localDirPath, localAdded, localDeleted, localModified, currentLocalFiles, syncTasks);

    // 更新任务包含的具体子任务
    if (task != null) {
      task.items.clear();
      task.items.addAll(syncTasks.map((j) => j.item));
      CloudDriveProgressManager.instance.updateTask(task);
    }

    // 5. 控制并发执行任务
    final uploadTasks = syncTasks.where((t) => t.item.action == SyncItemAction.upload).toList();
    final downloadTasks = syncTasks.where((t) => t.item.action == SyncItemAction.download).toList();
    final deleteTasks = syncTasks.where((t) => t.item.action == SyncItemAction.delete).toList();

    await Future.wait([
      _executeConcurrently(uploadTasks, maxUploadConcurrency, task),
      _executeConcurrently(downloadTasks, maxDownloadConcurrency, task),
      _executeConcurrently(deleteTasks, 3, task), // Fixed concurrency for deletes
    ]);

    // 6. 更新并保存规范的本地索引
    await _saveLocalIndex(currentLocalFiles, localIndexService, localIndex, syncTasks);

    if (task != null) {
      bool allSuccess = task.items.every((i) => i.status == SyncStatus.completed);
      task.status = allSuccess ? SyncStatus.completed : SyncStatus.failed;
      task.completedAt = DateTime.now();
      CloudDriveProgressManager.instance.updateTask(task);
    }
    
    print('Sync completed.');
  }

  String _buildRemotePath(String baseRemote, String relativePath) {
    if (baseRemote.endsWith('/')) {
      baseRemote = baseRemote.substring(0, baseRemote.length - 1);
    }
    if (!relativePath.startsWith('/')) {
      relativePath = '/' + relativePath;
    }
    return baseRemote + relativePath;
  }

  Future<void> _syncRecursiveDir(
    String remoteDir, 
    String localDir, 
    Set<String> localAdded, 
    Set<String> localDeleted, 
    Set<String> localModified, 
    Map<String, File> currentLocalFiles, 
    List<_SyncJob> syncTasks
  ) async {
    List<WebDavFile> remoteFiles;
    try {
      remoteFiles = await service.readDir(remoteDir);
    } catch (e) {
      print('Failed to read remote dir $remoteDir: $e');
      return;
    }

    final localDirectory = Directory(localDir);
    if (!await localDirectory.exists()) {
      await localDirectory.create(recursive: true);
    }

    final remoteFileMap = {for (var f in remoteFiles) f.name: f};
    final localEntities = await localDirectory.list().toList();
    final localFileMap = {for (var e in localEntities) p.basename(e.path): e};

    final List<Future<void>> subDirFutures = [];

    for (final remoteFile in remoteFiles) {
      if (remoteFile.name.isEmpty) continue;

      final localEntityPath = p.join(localDir, remoteFile.name);
      String relativePath = p.relative(localEntityPath, from: localDirPath).replaceAll(r'\', '/');
      if (!relativePath.startsWith('/')) relativePath = '/' + relativePath;

      if (remoteFile.isDirectory) {
        subDirFutures.add(_syncRecursiveDir(remoteFile.path, localEntityPath, localAdded, localDeleted, localModified, currentLocalFiles, syncTasks));
      } else {
        if (localFileMap.containsKey(remoteFile.name)) {
          // Both exist
          final localEntity = localFileMap[remoteFile.name]!;
          if (localEntity is File) {
            final localStat = await localEntity.stat();
            final localMod = localStat.modified;
            final remoteMod = remoteFile.lastModified;

            bool changedLocally = localModified.contains(relativePath);
            bool changedRemotely = false;
            
            if (!changedLocally) {
              // 依靠文件大小来判断远端是否发生了变化
              // 因为上传操作会更新远端时间，如果用时间戳比对会导致刚上传的文件在下次同步时被重复下载
              if (remoteFile.size != null && localStat.size != remoteFile.size) {
                changedRemotely = true;
              }
            }

            if (changedLocally) {
              if (direction == SyncDirection.localToCloud || direction == SyncDirection.twoWay) {
                syncTasks.add(_SyncJob(
                  SyncFileItem(path: localEntityPath, name: remoteFile.name, size: localStat.size, action: SyncItemAction.upload),
                  () async {
                    print('Uploading updated file: ${remoteFile.name}');
                    await service.upload(localEntityPath, remoteFile.path);
                  }
                ));
              }
              localModified.remove(relativePath);
            } else if (changedRemotely) {
              if (direction == SyncDirection.cloudToLocal || direction == SyncDirection.twoWay) {
                syncTasks.add(_SyncJob(
                  SyncFileItem(path: localEntityPath, name: remoteFile.name, size: remoteFile.size ?? 0, action: SyncItemAction.download),
                  () async {
                    print('Downloading updated file: ${remoteFile.name}');
                    await service.download(remoteFile.path, localEntityPath);
                  }
                ));
              }
            }
          }
        } else {
          // On remote, not locally
          if (localDeleted.contains(relativePath)) {
            if (direction == SyncDirection.localToCloud || direction == SyncDirection.twoWay) {
              syncTasks.add(_SyncJob(
                SyncFileItem(path: remoteFile.path, name: remoteFile.name, size: remoteFile.size ?? 0, action: SyncItemAction.delete),
                () async {
                  print('Deleting remote file: ${remoteFile.name}');
                  await service.remove(remoteFile.path);
                }
              ));
            }
            localDeleted.remove(relativePath);
          } else {
            if (direction == SyncDirection.cloudToLocal || direction == SyncDirection.twoWay) {
              syncTasks.add(_SyncJob(
                SyncFileItem(path: localEntityPath, name: remoteFile.name, size: remoteFile.size ?? 0, action: SyncItemAction.download),
                () async {
                  print('Downloading new file: ${remoteFile.name}');
                  await service.download(remoteFile.path, localEntityPath);
                }
              ));
            }
          }
        }
      }
    }

    await Future.wait(subDirFutures);
    subDirFutures.clear();

    // Process remaining local files (Local Added)
    if (direction == SyncDirection.localToCloud || direction == SyncDirection.twoWay) {
      for (final localEntity in localEntities) {
        final name = p.basename(localEntity.path);
        if (!remoteFileMap.containsKey(name)) {
          final localEntityPath = localEntity.path;
          String relativePath = p.relative(localEntityPath, from: localDirPath).replaceAll(r'\', '/');
          if (!relativePath.startsWith('/')) relativePath = '/' + relativePath;

          if (localEntity is File && localAdded.contains(relativePath)) {
            final stat = await localEntity.stat();
            syncTasks.add(_SyncJob(
              SyncFileItem(path: localEntityPath, name: name, size: stat.size, action: SyncItemAction.upload),
              () async {
                print('Uploading new file: $name');
                String remotePath = _buildRemotePath(remoteDir, name);
                await service.upload(localEntityPath, remotePath);
              }
            ));
            localAdded.remove(relativePath);
          } else if (localEntity is Directory) {
            String remotePath = _buildRemotePath(remoteDir, name);
            try {
              await service.mkdir(remotePath);
            } catch (e) {
              // Ignore if exists
            }
            subDirFutures.add(_syncRecursiveDir(remotePath, localEntityPath, localAdded, localDeleted, localModified, currentLocalFiles, syncTasks));
          }
        }
      }
      await Future.wait(subDirFutures);
    }
  }

  Future<void> _saveLocalIndex(Map<String, File> currentLocalFiles, LocalIndexService localIndexService, Map<String, dynamic> oldIndex, List<_SyncJob> tasks) async {
    Map<String, dynamic> newIndexData = Map<String, dynamic>.from(oldIndex);

    // 首先，保留那些没有发生变更的本地文件
    // 如果一个文件在 currentLocalFiles 中且没有对应的 upload/delete/download task，说明它在本次同步中是 unchanged
    final taskPaths = tasks.map((t) => t.item.path).toSet();
    for (var entry in currentLocalFiles.entries) {
      final relativePath = entry.key;
      final file = entry.value;
      if (!taskPaths.contains(file.path) && oldIndex.containsKey(relativePath)) {
        // unchanged file, already in newIndexData from oldIndex, but we can verify it exists
        // (Actually, since we copied oldIndex, we just need to ensure deleted files are removed)
      }
    }

    // 移除在本地已经不存在且没有在本次任务中处理（或已经被处理）的文件
    final localPaths = currentLocalFiles.keys.toSet();
    newIndexData.removeWhere((key, value) => !localPaths.contains(key) && !taskPaths.any((p) => p.replaceAll(r'\', '/').endsWith(key)));

    // 针对本次成功执行的任务，更新索引
    for (final job in tasks) {
      if (job.item.status == SyncStatus.completed) {
        final path = job.item.path;
        String relativePath = p.relative(path, from: localDirPath).replaceAll(r'\', '/');
        if (!relativePath.startsWith('/')) relativePath = '/' + relativePath;

        if (job.item.action == SyncItemAction.delete) {
          newIndexData.remove(relativePath);
        } else {
          // upload or download success
          final file = File(path);
          if (await file.exists()) {
            final stat = await file.stat();
            final hash = await _calculateFileHash(file);
            newIndexData[relativePath] = {
              'size': stat.size,
              'updatedAt': stat.modified.toIso8601String(),
              'hash': hash,
            };
          }
        }
      }
    }

    await localIndexService.saveLocalIndex(localDirPath, newIndexData);
  }

  Future<void> _executeConcurrently(List<_SyncJob> tasks, int concurrency, SyncTask? parentTask) async {
    if (tasks.isEmpty) return;
    int index = 0;
    Future<void> worker() async {
      while (index < tasks.length) {
        if (parentTask != null && parentTask.status == SyncStatus.failed && parentTask.errorMessage == '用户已取消/删除该任务') {
          return; // Abort if cancelled
        }

        final taskIndex = index++;
        final job = tasks[taskIndex];
        
        while (parentTask != null) {
          if (parentTask.status == SyncStatus.failed && parentTask.errorMessage == '用户已取消/删除该任务') {
            return;
          }
          if ((job.item.action == SyncItemAction.upload && parentTask.isUploadPaused) ||
              (job.item.action == SyncItemAction.download && parentTask.isDownloadPaused)) {
            await Future.delayed(const Duration(milliseconds: 500));
          } else {
            break;
          }
        }

        job.item.status = SyncStatus.syncing;
        if (parentTask != null) {
          CloudDriveProgressManager.instance.updateTask(parentTask);
        }

        try {
          await job.execute();
          job.item.status = SyncStatus.completed;
        } catch (e) {
          print('Task failed: $e');
          job.item.status = SyncStatus.failed;
          job.item.errorMessage = e.toString();
        }

        if (parentTask != null) {
          CloudDriveProgressManager.instance.updateTask(parentTask);
        }
      }
    }
    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);
  }
}
