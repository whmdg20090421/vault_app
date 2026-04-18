import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'webdav_config.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'webdav_storage.dart';
import 'webdav_new/webdav_client.dart';
import 'webdav_new/webdav_service.dart';
import 'webdav_new/sync_engine.dart';

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

  Future<void> startSync(
    BuildContext context,
    WebDavConfig config,
    String localDirPath,
    String remoteDir, {
    bool forceSync = false,
  }) async {
    if (_isSyncing) return;

    _isSyncing = true;
    addLog('开始同步云端配置: ${config.name}');
    notifyListeners();

    bool shouldRetry = false;

    try {
      final repository = WebDavConfigRepository();
      final password = await repository.readPassword(config.id) ?? '';

      final client = WebDavClient(
        baseUrl: config.url,
        username: config.username,
        password: password,
      );
      final service = WebDavService(client);
      final syncEngine = SyncEngine(
        service: service,
        localDirPath: localDirPath,
      );

      addLog('正在同步...');
      await syncEngine.sync(remoteDir, forceSync: forceSync);
      addLog('同步完成');
      _lastSyncTime = DateTime.now();
    } catch (e) {
      addLog('同步失败: $e', isError: true);
      
      // 检查是否是一致性校验失败的异常
      if (e.toString().contains('Sync Conflict: Remote index changed.')) {
        // 弹出一致性校验冲突对话框
        if (context.mounted) {
          final bool? shouldForceSync = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('同步冲突'),
                content: const Text('检测到本地缓存的云端索引与云端实际索引存在差异，是否将本地缓存同步至云端？'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    child: const Text('不同步'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: const Text('同步'),
                  ),
                ],
              );
            },
          );

          if (shouldForceSync == true) {
            shouldRetry = true;
          }
        }
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }

    if (shouldRetry) {
      // 重新触发同步，并绕过一致性检查
      await startSync(context, config, localDirPath, remoteDir, forceSync: true);
    }
  }

  void clearLogs() {
    _syncLogs.clear();
    notifyListeners();
  }
}
