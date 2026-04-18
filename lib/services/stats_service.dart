import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../encryption/services/local_index_service.dart';

class StatsService extends ChangeNotifier {
  static final StatsService _instance = StatsService._internal();

  factory StatsService() {
    return _instance;
  }

  StatsService._internal();

  int _encryptedBytes = 0;
  int _unencryptedBytes = 0;
  
  int _localEncryptedCount = 0;
  int _cloudEncryptedCount = 0;
  int _diffCount = 0;

  int get encryptedBytes => _encryptedBytes;
  int get unencryptedBytes => _unencryptedBytes;
  int get totalBytes => _encryptedBytes + _unencryptedBytes;

  int get localEncryptedCount => _localEncryptedCount;
  int get cloudEncryptedCount => _cloudEncryptedCount;
  int get diffCount => _diffCount;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _encryptedBytes = prefs.getInt('encrypted_bytes') ?? 0;
    _unencryptedBytes = prefs.getInt('unencrypted_bytes') ?? 0;
    _localEncryptedCount = prefs.getInt('local_encrypted_count') ?? 0;
    _cloudEncryptedCount = prefs.getInt('cloud_encrypted_count') ?? 0;
    _diffCount = prefs.getInt('diff_count') ?? 0;
  }

  Future<void> recalculate() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 获取加密和未加密文件夹路径
    final vaultPaths = prefs.getStringList('vault_paths') ?? [];
    final unencryptedPaths = prefs.getStringList('unencrypted_paths') ?? [];

    int encBytes = 0;
    int locEncCount = 0;
    int cldEncCount = 0;
    int dfCount = 0;

    for (String path in vaultPaths) {
      encBytes += await _getFolderSize(Directory(path));
      
      final stats = await LocalIndexService().getFileStatistics(path);
      locEncCount += stats['localEncryptedCount'] as int;
      cldEncCount += stats['cloudEncryptedCount'] as int;
      dfCount += stats['diffCount'] as int;
    }

    int unencBytes = 0;
    for (String path in unencryptedPaths) {
      unencBytes += await _getFolderSize(Directory(path));
    }

    _encryptedBytes = encBytes;
    _unencryptedBytes = unencBytes;
    _localEncryptedCount = locEncCount;
    _cloudEncryptedCount = cldEncCount;
    _diffCount = dfCount;

    await prefs.setInt('encrypted_bytes', _encryptedBytes);
    await prefs.setInt('unencrypted_bytes', _unencryptedBytes);
    await prefs.setInt('local_encrypted_count', _localEncryptedCount);
    await prefs.setInt('cloud_encrypted_count', _cloudEncryptedCount);
    await prefs.setInt('diff_count', _diffCount);

    notifyListeners();
  }

  Future<int> _getFolderSize(Directory dir) async {
    int size = 0;
    try {
      if (await dir.exists()) {
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            size += await entity.length();
          }
        }
      }
    } catch (e) {
      // 忽略读取错误，如权限问题等
    }
    return size;
  }


}
