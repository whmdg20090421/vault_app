import 'dart:io';
import 'package:path/path.dart' as p;
import 'webdav_service.dart';
import 'webdav_file.dart';

/// 同步引擎，负责将 WebDAV 远端文件与本地目录进行双向同步
class SyncEngine {
  final WebDavService service;
  final String localDirPath;
  final int maxConcurrency;

  SyncEngine({
    required this.service,
    required this.localDirPath,
    this.maxConcurrency = 3,
  });

  /// 启动同步流程
  /// [remoteDir] 远端需要同步的基础目录
  Future<void> sync(String remoteDir) async {
    print('Starting sync from remote: $remoteDir to local: $localDirPath');
    await _syncRecursive(remoteDir, localDirPath);
    print('Sync completed.');
  }

  /// 递归同步目录内容
  Future<void> _syncRecursive(String remoteDir, String localDir) async {
    // 1. 获取远端目录下的所有文件/文件夹
    List<WebDavFile> remoteFiles;
    try {
      remoteFiles = await service.readDir(remoteDir);
    } catch (e) {
      print('Failed to read remote dir $remoteDir: $e');
      return;
    }

    // 2. 确保本地目录存在
    final localDirectory = Directory(localDir);
    if (!await localDirectory.exists()) {
      await localDirectory.create(recursive: true);
    }

    // 将远端文件存入 Map，方便与本地比对
    final remoteFileMap = {for (var f in remoteFiles) f.name: f};

    // 3. 获取本地目录下的所有文件/文件夹 (仅当前层级)
    final localEntities = await localDirectory.list().toList();
    final localFileMap = {for (var e in localEntities) p.basename(e.path): e};

    // 我们将所有的同步任务（上传、下载）收集起来，后续统一执行
    final syncTasks = <Future<void> Function()>[];

    // 4. 遍历远端文件，判断是下载还是跳过
    for (final remoteFile in remoteFiles) {
      if (remoteFile.name.isEmpty) continue;

      final localEntityPath = p.join(localDir, remoteFile.name);
      final localEntity = localFileMap[remoteFile.name];

      if (remoteFile.isDirectory) {
        // 如果是文件夹，则递归同步
        await _syncRecursive(remoteFile.path, localEntityPath);
      } else {
        // 如果是文件，进行状态比对
        if (localEntity != null) {
          if (localEntity is File) {
            // 本地存在同名文件，比较 ETag 和 Last-Modified
            final localStat = await localEntity.stat();
            final localModified = localStat.modified;
            
            // 基本同步算法：
            // - 比较文件大小是否不同
            // - 比较最后修改时间
            // - 如果服务器支持 ETag，通常可以结合本地缓存的 ETag 判断是否变更，
            //   此处我们以 Last-Modified 为主：若远端文件较新，则下载覆盖。
            final remoteModified = remoteFile.lastModified;
            
            bool shouldDownload = false;
            if (remoteModified != null && remoteModified.isAfter(localModified)) {
              shouldDownload = true;
            } else if (localStat.size != remoteFile.size) {
              shouldDownload = true;
            }
            
            if (shouldDownload) {
              syncTasks.add(() async {
                print('Downloading updated file: ${remoteFile.name}');
                await service.download(remoteFile.path, localEntityPath);
              });
            } else {
              // 本地文件可能较新，需要上传（简单双向同步逻辑）
              if (remoteModified != null && localModified.isAfter(remoteModified)) {
                syncTasks.add(() async {
                  print('Uploading updated file: ${remoteFile.name}');
                  await service.upload(localEntityPath, remoteFile.path);
                });
              }
            }
          } else {
            // 本地同名实体是文件夹，远端是文件，这属于冲突情况，简单跳过或记录日志
            print('Conflict: local is directory but remote is file: ${remoteFile.name}');
          }
        } else {
          // 本地不存在该文件，执行下载
          syncTasks.add(() async {
            print('Downloading new file: ${remoteFile.name}');
            await service.download(remoteFile.path, localEntityPath);
          });
        }
      }
    }

    // 5. 遍历本地文件，查找仅在本地存在的文件，执行上传
    for (final localEntity in localEntities) {
      final name = p.basename(localEntity.path);
      if (!remoteFileMap.containsKey(name)) {
        if (localEntity is File) {
          syncTasks.add(() async {
            print('Uploading new file: $name');
            // 构建远端路径
            String remotePath = remoteDir;
            if (!remotePath.endsWith('/')) remotePath += '/';
            remotePath += name;
            
            await service.upload(localEntity.path, remotePath);
          });
        } else if (localEntity is Directory) {
          // 如果本地有新文件夹，则在远端创建并递归上传
          String remotePath = remoteDir;
          if (!remotePath.endsWith('/')) remotePath += '/';
          remotePath += name;
          
          try {
            await service.mkdir(remotePath);
          } catch (e) {
            print('Mkdir failed or already exists: $e');
          }
          await _syncRecursive(remotePath, localEntity.path);
        }
      }
    }

    // 6. 控制并发执行任务
    await _executeConcurrently(syncTasks, maxConcurrency);
  }

  /// 使用指定的并发数执行一组异步任务
  Future<void> _executeConcurrently(List<Future<void> Function()> tasks, int concurrency) async {
    if (tasks.isEmpty) return;
    
    int index = 0;
    
    // 工作线程：不断从任务列表中获取下一个任务并执行
    Future<void> worker() async {
      while (index < tasks.length) {
        final taskIndex = index++;
        try {
          await tasks[taskIndex]();
        } catch (e) {
          print('Task failed: $e');
          // 可根据需求决定是否继续执行其他任务或中断
        }
      }
    }

    // 启动指定数量的 worker
    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);
  }
}
