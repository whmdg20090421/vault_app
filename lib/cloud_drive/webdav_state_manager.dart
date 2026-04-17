import 'package:flutter/foundation.dart';
import 'webdav_service.dart';
import 'package:intl/intl.dart';
import 'webdav_config.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'webdav_storage.dart';

class SyncLog {
  final DateTime time;
  final String message;
  final bool isError;

  SyncLog({required this.time, required this.message, this.isError = false});
}

class WebDAVStateManager extends ChangeNotifier {
  static final WebDAVStateManager instance = WebDAVStateManager._internal();
  WebDAVStateManager._internal();

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  final List<SyncLog> _syncLogs = [];
  List<SyncLog> get syncLogs => List.unmodifiable(_syncLogs);

  void addLog(String message, {bool isError = false}) {
    _syncLogs.add(SyncLog(time: DateTime.now(), message: message, isError: isError));
    if (_syncLogs.length > 500) {
      _syncLogs.removeRange(0, _syncLogs.length - 500);
    }
    notifyListeners();
  }

  Future<void> startSync(WebDavConfig config) async {
    if (_isSyncing) return;

    _isSyncing = true;
    addLog('开始同步云端配置: ${config.name}');
    notifyListeners();

    try {
      final repository = WebDavConfigRepository();
      final password = await repository.readPassword(config.id) ?? '';

      final client = WebDavService(
        url: config.url,
        username: config.username,
        password: password,
      );

      // 获取云端文件列表 (PROPFIND)
      final remotePath = '/';
      addLog('读取云端目录: $remotePath');
      final remoteFiles = await client.readDir(remotePath);
      addLog('云端目录读取成功，共 ${remoteFiles.length} 个文件/文件夹');

      // 获取本地保险箱目录
      final appDir = await getApplicationDocumentsDirectory();
      final localVaultDir = Directory('${appDir.path}/vaults');
      if (!await localVaultDir.exists()) {
        await localVaultDir.create(recursive: true);
      }
      addLog('读取本地目录: ${localVaultDir.path}');
      final localFiles = await localVaultDir.list().toList();
      addLog('本地目录读取成功，共 ${localFiles.length} 个文件/文件夹');

      addLog('正在进行差异比对与双向同步...');

      final remoteFileMap = {for (var f in remoteFiles) if (!f.isDirectory) f.name: f};
      final localFileMap = {
        for (var f in localFiles) 
          if (f is File) f.path.split('/').last: f
      };

      int uploadCount = 0;
      int downloadCount = 0;

      // 1. Check local files to upload
      for (var localName in localFileMap.keys) {
        final localFile = localFileMap[localName]! as File;
        final localStat = await localFile.stat();
        final remoteFile = remoteFileMap[localName];

        if (remoteFile == null) {
          // Upload
          addLog('发现本地新文件，正在上传: $localName');
          await client.upload(localFile.path, '/$localName');
          uploadCount++;
        } else {
          final remoteTime = remoteFile.lastModified;
          final localTime = localStat.modified;
          
          if (remoteTime != null && localTime.isAfter(remoteTime.add(const Duration(seconds: 5)))) {
            addLog('本地文件较新，正在覆盖上传: $localName');
            await client.upload(localFile.path, '/$localName');
            uploadCount++;
          }
        }
      }

      // 2. Check remote files to download
      for (var remoteName in remoteFileMap.keys) {
        final remoteFile = remoteFileMap[remoteName]!;
        final localFile = localFileMap[remoteName];

        if (localFile == null) {
          // Download
          addLog('发现云端新文件，正在下载: $remoteName');
          await client.download('/$remoteName', '${localVaultDir.path}/$remoteName');
          downloadCount++;
        } else {
          final localStat = await (localFile as File).stat();
          final remoteTime = remoteFile.lastModified;
          final localTime = localStat.modified;

          if (remoteTime != null && remoteTime.isAfter(localTime.add(const Duration(seconds: 5)))) {
            addLog('云端文件较新，正在覆盖下载: $remoteName');
            await client.download('/$remoteName', '${localVaultDir.path}/$remoteName');
            downloadCount++;
          }
        }
      }

      addLog('同步完成，上传 $uploadCount 个文件，下载 $downloadCount 个文件');
      _lastSyncTime = DateTime.now();
    } catch (e) {
      addLog('同步失败: $e', isError: true);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  void clearLogs() {
    _syncLogs.clear();
    notifyListeners();
  }
}
