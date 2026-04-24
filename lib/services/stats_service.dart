import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../encryption/services/local_index_service.dart';
import '../models/sync_task.dart';
import 'sync_storage_service.dart';
import '../cloud_drive/webdav_storage.dart';
import '../cloud_drive/webdav_new/webdav_client.dart';
import '../cloud_drive/webdav_new/webdav_service.dart';
import 'package:collection/collection.dart';

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

    final syncStorage = SyncStorageService();
    final allTasks = await syncStorage.loadTasks();

    for (String path in vaultPaths) {
      encBytes += await _getFolderSize(Directory(path));
      
      final stats = await LocalIndexService().getFileStatistics(path);
      int currentLocEncCount = stats['localEncryptedCount'] as int;
      int currentCldEncCount = stats['cloudEncryptedCount'] as int;
      int currentDfCount = stats['diffCount'] as int;

      // Check if there is a sync task for this vault path
      final task = allTasks.firstWhereOrNull(
        (t) => t.localVaultPath == path
      );

      if (task != null && task.cloudWebDavId.isNotEmpty) {
        try {
          final webDavStats = await _getWebDavStats(path, task);
          if (webDavStats != null) {
            currentCldEncCount = webDavStats['cloudEncryptedCount'] as int;
            currentDfCount = webDavStats['diffCount'] as int;
          }
        } catch (e) {
          // Fallback to local index stats if WebDAV fails
          print('Failed to get WebDAV stats for $path: $e');
        }
      }

      locEncCount += currentLocEncCount;
      cldEncCount += currentCldEncCount;
      dfCount += currentDfCount;
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

  Future<Map<String, dynamic>?> _getWebDavStats(String localVaultPath, SyncTask task) async {
    final repository = WebDavConfigRepository();
    final configs = await repository.listConfigs();
    final config = configs.firstWhereOrNull((c) => c.id == task.cloudWebDavId);
    if (config == null) return null;

    final password = await repository.readPassword(config.id) ?? '';
    final client = WebDavClient(
      baseUrl: config.url,
      username: config.username,
      password: password,
    );
    final service = WebDavService(client);

    final localIndex = await LocalIndexService().getLocalIndex(localVaultPath);
    
    int cloudEncryptedCount = 0;
    int diffCount = 0;

    final Set<String> remoteFilePaths = {};
    
    Future<void> scanDir(String remoteDir) async {
      try {
        final files = await service.readDir(remoteDir);
        for (final file in files) {
          if (file.name.isEmpty) continue;
          if (file.isDirectory) {
            await scanDir(file.path);
          } else {
            cloudEncryptedCount++;
            
            String relativePath = file.path;
            if (relativePath.startsWith(task.cloudFolderPath)) {
               relativePath = relativePath.substring(task.cloudFolderPath.length);
            }
            if (!relativePath.startsWith('/')) relativePath = '/' + relativePath;
            
            remoteFilePaths.add(relativePath);
            
            final indexEntry = localIndex[relativePath];
            if (indexEntry == null) {
              diffCount++;
            } else {
              bool isDiff = false;
              final indexSize = indexEntry['cipherSize'] ?? indexEntry['size'];
              final indexETag = indexEntry['eTag'];
              final indexRemoteMod = indexEntry['remoteMod'];
              
              if (indexSize != null && file.size != indexSize) {
                isDiff = true;
              } else if (file.eTag != null && indexETag != null) {
                 if (file.eTag != indexETag) isDiff = true;
              } else if (file.lastModified != null && indexRemoteMod != null) {
                 if (file.lastModified!.toIso8601String() != indexRemoteMod) isDiff = true;
              }
              
              if (isDiff) {
                diffCount++;
              }
            }
          }
        }
      } catch (e) {
        print('Error scanning remote dir $remoteDir: $e');
      }
    }

    await scanDir(task.cloudFolderPath);
    
    for (final key in localIndex.keys) {
      if (!remoteFilePaths.contains(key)) {
        diffCount++;
      }
    }

    return {
      'cloudEncryptedCount': cloudEncryptedCount,
      'diffCount': diffCount,
    };
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
