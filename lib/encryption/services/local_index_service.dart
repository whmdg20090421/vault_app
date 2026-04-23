import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class LocalIndexService {
  static final LocalIndexService _instance = LocalIndexService._internal();
  factory LocalIndexService() => _instance;
  LocalIndexService._internal();

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
      final indexFile = File(p.join(vaultDirectoryPath, 'local_index.json'));
      Map<String, dynamic> indexData = {};
      
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        if (content.isNotEmpty) {
          indexData = jsonDecode(content) as Map<String, dynamic>;
        }
      }

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

      await indexFile.writeAsString(jsonEncode(indexData));
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
          return jsonDecode(content) as Map<String, dynamic>;
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
      await indexFile.writeAsString(jsonEncode(indexData));
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
