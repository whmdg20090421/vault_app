import 'package:flutter/foundation.dart';
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
      addLog('同步功能正在重构中...');
      await Future.delayed(const Duration(seconds: 1));
      addLog('同步完成（占位）');
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
