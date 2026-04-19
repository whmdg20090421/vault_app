import re
import os

code = """import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'webdav_service.dart';
import 'webdav_file.dart';
import '../../encryption/services/local_index_service.dart';
import '../../models/sync_task.dart';

/// 同步引擎，负责将 WebDAV 远端文件与本地目录进行双向同步
class SyncEngine {
  final WebDavService service;
  final String localDirPath;
  final int maxConcurrency;
  final SyncDirection direction;

  SyncEngine({
    required this.service,
    required this.localDirPath,
    this.maxConcurrency = 3,
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
        String relativePath = p.relative(entity.path, from: localDirPath).replaceAll(r'\\', '/');
        if (!relativePath.startsWith('/')) relativePath = '/' + relativePath;
        files[relativePath] = entity;
      }
    }
  }

  /// 启动同步流程
  Future<void> sync(String remoteDir, {bool forceSync = false}) async {
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
        final indexInfo = localIndex[path]!;
        final file = currentLocalFiles[path]!;
        final stat = await file.stat();
        
        if (stat.size != indexInfo['size'] || stat.modified.toIso8601String() != indexInfo['updatedAt']) {
          if (stat.size == indexInfo['size']) {
            final hash = await _calculateFileHash(file);
            if (hash == indexInfo['hash']) {
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
        final hash = entry.value['hash'];
        if (hash != null) {
          hashToPaths.putIfAbsent(hash, () => []).add(entry.key);
        }
      }

      for (var addedPath in localAdded.toList()) {
        final hash = await _calculateFileHash(currentLocalFiles[addedPath]!);
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

    // 4. PROPFIND 获取云端状态并进行精准差异比对
    final syncTasks = <Future<void> Function()>[];
    await _syncRecursiveDir(remoteDir, localDirPath, localAdded, localDeleted, localModified, currentLocalFiles, syncTasks);

    // 5. 控制并发执行任务
    await _executeConcurrently(syncTasks, maxConcurrency);

    // 6. 更新并保存规范的本地索引
    await _saveLocalIndex(currentLocalFiles, localIndexService);
    
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
    List<Future<void> Function()> syncTasks
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

    for (final remoteFile in remoteFiles) {
      if (remoteFile.name.isEmpty) continue;

      final localEntityPath = p.join(localDir, remoteFile.name);
      String relativePath = p.relative(localEntityPath, from: localDirPath).replaceAll(r'\\', '/');
      if (!relativePath.startsWith('/')) relativePath = '/' + relativePath;

      if (remoteFile.isDirectory) {
        await _syncRecursiveDir(remoteFile.path, localEntityPath, localAdded, localDeleted, localModified, currentLocalFiles, syncTasks);
      } else {
        if (localFileMap.containsKey(remoteFile.name)) {
          // Both exist
          final localEntity = localFileMap[remoteFile.name]!;
          if (localEntity is File) {
            final localStat = await localEntity.stat();
            final localMod = localStat.modified;
            final remoteMod = remoteFile.lastModified;

            bool isDifferent = false;
            if (localStat.size != remoteFile.size) {
              isDifferent = true;
            } else if (remoteMod != null && localMod.toIso8601String() != remoteMod.toIso8601String()) {
              final hash = await _calculateFileHash(localEntity);
              // In a real scenario we might not have remote hash, so we assume different if time differs
              isDifferent = true; 
            }

            if (isDifferent) {
              if (direction == SyncDirection.cloudToLocal || 
                 (direction == SyncDirection.twoWay && remoteMod != null && remoteMod.isAfter(localMod))) {
                syncTasks.add(() async {
                  print('Downloading updated file: ${remoteFile.name}');
                  await service.download(remoteFile.path, localEntityPath);
                });
              } else if (direction == SyncDirection.localToCloud || direction == SyncDirection.twoWay) {
                syncTasks.add(() async {
                  print('Uploading updated file: ${remoteFile.name}');
                  await service.upload(localEntityPath, remoteFile.path);
                });
              }
            }
            localModified.remove(relativePath);
          }
        } else {
          // On remote, not locally
          if (localDeleted.contains(relativePath)) {
            if (direction == SyncDirection.localToCloud || direction == SyncDirection.twoWay) {
              syncTasks.add(() async {
                print('Deleting remote file: ${remoteFile.name}');
                await service.remove(remoteFile.path);
              });
            }
            localDeleted.remove(relativePath);
          } else {
            if (direction == SyncDirection.cloudToLocal || direction == SyncDirection.twoWay) {
              syncTasks.add(() async {
                print('Downloading new file: ${remoteFile.name}');
                await service.download(remoteFile.path, localEntityPath);
              });
            }
          }
        }
      }
    }

    // Process remaining local files (Local Added)
    if (direction == SyncDirection.localToCloud || direction == SyncDirection.twoWay) {
      for (final localEntity in localEntities) {
        final name = p.basename(localEntity.path);
        if (!remoteFileMap.containsKey(name)) {
          final localEntityPath = localEntity.path;
          String relativePath = p.relative(localEntityPath, from: localDirPath).replaceAll(r'\\', '/');
          if (!relativePath.startsWith('/')) relativePath = '/' + relativePath;

          if (localEntity is File && localAdded.contains(relativePath)) {
            syncTasks.add(() async {
              print('Uploading new file: $name');
              String remotePath = _buildRemotePath(remoteDir, name);
              await service.upload(localEntityPath, remotePath);
            });
            localAdded.remove(relativePath);
          } else if (localEntity is Directory) {
            String remotePath = _buildRemotePath(remoteDir, name);
            try {
              await service.mkdir(remotePath);
            } catch (e) {
              // Ignore if exists
            }
            await _syncRecursiveDir(remotePath, localEntity.path, localAdded, localDeleted, localModified, currentLocalFiles, syncTasks);
          }
        }
      }
    }
  }

  Future<void> _saveLocalIndex(Map<String, File> currentLocalFiles, LocalIndexService localIndexService) async {
    // Need to re-scan to get the actual sizes and modified times after sync (downloads might have changed them)
    Map<String, File> finalFiles = {};
    await _scanLocalFiles(Directory(localDirPath), finalFiles);
    
    for (var entry in finalFiles.entries) {
      final path = entry.key;
      final file = entry.value;
      final stat = await file.stat();
      final hash = await _calculateFileHash(file);
      
      await localIndexService.updateFileIndex(
        vaultDirectoryPath: localDirPath,
        remotePath: path,
        hash: hash,
        size: stat.size,
        updatedAt: stat.modified,
      );
    }
  }

  Future<void> _executeConcurrently(List<Future<void> Function()> tasks, int concurrency) async {
    if (tasks.isEmpty) return;
    int index = 0;
    Future<void> worker() async {
      while (index < tasks.length) {
        final taskIndex = index++;
        try {
          await tasks[taskIndex]();
        } catch (e) {
          print('Task failed: $e');
        }
      }
    }
    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);
  }
}
"""

with open('/workspace/lib/cloud_drive/webdav_new/sync_engine.dart', 'w') as f:
    f.write(code)
