import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../utils/dfs_format_utils.dart';

class LocalIndexService {
  static final LocalIndexService _instance = LocalIndexService._internal();
  factory LocalIndexService() => _instance;
  LocalIndexService._internal();

  /// 将平铺的文件路径 Map 转换为嵌套的文件树结构
  Map<String, dynamic> _flatToTree(Map<String, dynamic> flat) {
    final tree = <String, dynamic>{};
    // 按字母顺序排序路径，使其能够按深度优先（DFS）的顺序生成和保存
    final sortedKeys = flat.keys.toList()..sort();
    
    for (final path in sortedKeys) {
      final parts = path.split('/').where((p) => p.isNotEmpty).toList();
      Map<String, dynamic> current = tree;
      for (int i = 0; i < parts.length - 1; i++) {
        final part = parts[i];
        if (!current.containsKey(part) || current[part] is! Map) {
          current[part] = <String, dynamic>{};
        }
        current = current[part] as Map<String, dynamic>;
      }
      if (parts.isNotEmpty) {
        current[parts.last] = flat[path];
      }
    }
    return tree;
  }

  /// 将嵌套的文件树结构还原为平铺的文件路径 Map
  Map<String, dynamic> _treeToFlat(Map<String, dynamic> tree) {
    final flat = <String, dynamic>{};
    
    void traverse(Map<String, dynamic> current, String currentPath) {
      for (final entry in current.entries) {
        final key = entry.key;
        final value = entry.value;
        final newPath = '$currentPath/$key';
        
        if (value is Map<String, dynamic>) {
          // 判断是文件信息还是目录，如果有 'cipherSize' 或 'size' 则是文件
          if (value.containsKey('cipherSize') || value.containsKey('size') || value.containsKey('hash')) {
            flat[newPath] = value;
          } else {
            traverse(value, newPath);
          }
        }
      }
    }
    
    traverse(tree, '');
    return flat;
  }

  /// Updates or adds a file entry in local_index.json for the specified vault.
  Future<void> updateFileIndex({
    required String vaultDirectoryPath,
    required String remotePath, // The path inside the vault, e.g., '/folder/file.txt'
    required String cipherHashSha256,
    required int cipherSize,
    required DateTime cipherUpdatedAt,
    required String plainHashSha256,
    required int plainSize,
    required DateTime plainUpdatedAt,
    required Map<String, String> sourceAbsolutePathEnc,
  }) async {
    try {
      final indexData = await getLocalIndex(vaultDirectoryPath);
      final normalizedPath = remotePath.startsWith('/') ? remotePath : '/$remotePath';

      indexData[normalizedPath] = {
        'cipherSize': cipherSize,
        'cipherUpdatedAt': cipherUpdatedAt.toIso8601String(),
        'cipherHashSha256': cipherHashSha256,
        'plainSize': plainSize,
        'plainUpdatedAt': plainUpdatedAt.toIso8601String(),
        'plainHashSha256': plainHashSha256,
        'sourceAbsolutePathEnc': sourceAbsolutePathEnc,
      };

      await saveLocalIndex(vaultDirectoryPath, indexData);
    } catch (e) {
      print('Failed to update local_index.json: $e');
    }
  }

  /// Gets the local index data for a vault.
  Future<Map<String, dynamic>> getLocalIndex(String vaultDirectoryPath) async {
    try {
      final indexFile = File(p.join(vaultDirectoryPath, 'local_index.json'));
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        if (content.isNotEmpty) {
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          
          // 兼容最新的 DFS 目录格式
          if (decoded.containsKey('目录')) {
            final Map<String, dynamic> directory = decoded['目录'];
            // 过滤掉仅仅为了补齐文件夹而创建的 {isDirectory: true} 项，因为平铺格式通常只存文件
            // 不过这里其实也可以不过滤，只过滤出含有文件信息的
            final flat = <String, dynamic>{};
            for (final entry in directory.entries) {
              final value = entry.value;
              if (value is Map && (value.containsKey('cipherSize') || value.containsKey('size') || value.containsKey('hash'))) {
                flat[entry.key] = value;
              }
            }
            return flat;
          } else if (decoded.containsKey('metadata') && decoded.containsKey('files')) {
            // 兼容旧版树状格式
            return _treeToFlat(decoded['files'] as Map<String, dynamic>);
          } else {
            return decoded;
          }
        }
      }
    } catch (e) {
      print('Failed to read local_index.json: $e');
    }
    return {};
  }

  /// Saves the entire local index.
  Future<void> saveLocalIndex(String vaultDirectoryPath, Map<String, dynamic> indexData) async {
    try {
      final indexFile = File(p.join(vaultDirectoryPath, 'local_index.json'));
      
      // 构建其他内容
      final otherContent = {
        'metadata': {
          'version': 3, // 版本号升级
          'updatedAt': DateTime.now().toIso8601String(),
          'description': 'Vault local index cache'
        },
        'footer': {
          'fileCount': indexData.length,
          'endOfIndex': true
        }
      };

      // 使用自定义 DFS 排序算法处理文件目录
      final sortedDirectory = DfsFormatUtils.sortAndFillDFS(indexData);

      // 使用自定义单行编码器生成 JSON 字符串
      final jsonString = DfsFormatUtils.customJsonEncode(otherContent, sortedDirectory);
      
      await indexFile.writeAsString(jsonString);
    } catch (e) {
      print('Failed to save local_index.json: $e');
    }
  }

  Future<Map<String, int>> getFileStatistics(String vaultDirectoryPath) async {
    int localEncryptedCount = 0;
    int cloudEncryptedCount = 0;
    int diffCount = 0;

    final localIndex = await getLocalIndex(vaultDirectoryPath);
    cloudEncryptedCount = localIndex.length;

    final Set<String> localFilePaths = {};
    try {
      final dir = Directory(vaultDirectoryPath);
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final fileName = p.basename(entity.path);
            if (fileName == 'local_index.json' || fileName.endsWith('.marker') || fileName == '.vault_manifest' || fileName == 'vault_config.json') {
              continue;
            }

            localEncryptedCount++;

            final relativePath = '/${p.relative(entity.path, from: vaultDirectoryPath).replaceAll('\\', '/')}';
            localFilePaths.add(relativePath);
            final indexEntry = localIndex[relativePath];

            if (indexEntry == null) {
              diffCount++;
            } else {
              final stat = await entity.stat();
              final indexSize = indexEntry['cipherSize'] ?? indexEntry['size'];
              final indexUpdatedAtStr = indexEntry['cipherUpdatedAt'] ?? indexEntry['updatedAt'];

              bool isDiff = false;
              if (indexSize != null && stat.size != indexSize) {
                isDiff = true;
              } else if (indexUpdatedAtStr != null) {
                final indexUpdatedAt = DateTime.tryParse(indexUpdatedAtStr.toString());
                if (indexUpdatedAt != null && stat.modified.difference(indexUpdatedAt).inSeconds.abs() > 1) {
                  isDiff = true;
                }
              }

              if (isDiff) {
                diffCount++;
              }
            }
          }
        }
      }

      // Calculate deleted files
      for (final key in localIndex.keys) {
        if (!localFilePaths.contains(key)) {
          diffCount++;
        }
      }
    } catch (e) {
      print('Failed to get file statistics: $e');
    }

    return {
      'localEncryptedCount': localEncryptedCount,
      'cloudEncryptedCount': cloudEncryptedCount,
      'diffCount': diffCount,
    };
  }
}
