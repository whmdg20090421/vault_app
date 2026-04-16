import 'package:flutter/material.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:intl/intl.dart';
import 'webdav_config.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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
    notifyListeners();
  }

  Future<void> startSync(WebDavConfig config) async {
    if (_isSyncing) return;

    _isSyncing = true;
    addLog('开始同步云端配置: ${config.name}');
    notifyListeners();

    try {
      final client = webdav.newClient(
        config.url,
        user: config.username,
        password: config.password,
      );
      
      // 测试连接
      await client.ping();
      addLog('成功连接到 WebDAV 服务器');

      // 获取云端文件列表 (PROPFIND)
      final remotePath = config.path.isNotEmpty ? config.path : '/';
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

      // 差异比对与简单日志
      addLog('正在进行差异比对...');
      // 简单模拟差异比对逻辑
      int diffCount = 0;
      for (var rFile in remoteFiles) {
        if (!rFile.name!.endsWith('/')) {
          final lFile = localFiles.whereType<File>().firstWhere(
            (f) => f.path.split('/').last == rFile.name,
            orElse: () => File(''),
          );
          if (lFile.path.isEmpty) {
            addLog('发现云端新文件: ${rFile.name}');
            diffCount++;
          }
        }
      }
      
      addLog('比对完成，发现 $diffCount 个差异文件');
      
      _lastSyncTime = DateTime.now();
      addLog('同步完成');
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
