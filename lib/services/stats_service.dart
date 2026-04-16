import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class StatsService {
  static final StatsService _instance = StatsService._internal();

  factory StatsService() {
    return _instance;
  }

  StatsService._internal();

  int _encryptedBytes = 0;
  int _unencryptedBytes = 0;

  int get encryptedBytes => _encryptedBytes;
  int get unencryptedBytes => _unencryptedBytes;
  int get totalBytes => _encryptedBytes + _unencryptedBytes;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _encryptedBytes = prefs.getInt('encrypted_bytes') ?? 0;
    _unencryptedBytes = prefs.getInt('unencrypted_bytes') ?? 0;
  }

  Future<void> recalculate() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 获取加密和未加密文件夹路径
    final vaultPaths = prefs.getStringList('vault_paths') ?? [];
    final unencryptedPaths = prefs.getStringList('unencrypted_paths') ?? [];

    int encBytes = 0;
    for (String path in vaultPaths) {
      encBytes += await _getFolderSize(Directory(path));
    }

    int unencBytes = 0;
    for (String path in unencryptedPaths) {
      unencBytes += await _getFolderSize(Directory(path));
    }

    _encryptedBytes = encBytes;
    _unencryptedBytes = unencBytes;

    await prefs.setInt('encrypted_bytes', _encryptedBytes);
    await prefs.setInt('unencrypted_bytes', _unencryptedBytes);
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
