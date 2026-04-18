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
    required String hash,
    required int size,
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
        'filename': p.basename(normalizedPath),
        'structure': p.dirname(normalizedPath),
        'hash': hash,
        'size': size,
        'updatedAt': DateTime.now().toIso8601String(),
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

  /// Calculates file statistics by comparing local and remote index files.
  Future<Map<String, int>> getFileStatistics(String vaultDirectoryPath) async {
    int localEncryptedCount = 0;
    int cloudEncryptedCount = 0;
    int diffCount = 0;

    final localIndex = await getLocalIndex(vaultDirectoryPath);
    localEncryptedCount = localIndex.length;

    Map<String, dynamic> remoteIndex = {};
    try {
      final remoteCacheFile = File(p.join(vaultDirectoryPath, 'remote_index_cache.json'));
      if (await remoteCacheFile.exists()) {
        final content = await remoteCacheFile.readAsString();
        if (content.isNotEmpty) {
          remoteIndex = jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      print('Failed to read remote_index_cache.json: $e');
    }

    cloudEncryptedCount = remoteIndex.length;

    // Calculate diff
    Set<String> allKeys = {...localIndex.keys, ...remoteIndex.keys};
    for (String key in allKeys) {
      final localFile = localIndex[key];
      final remoteFile = remoteIndex[key];
      
      if (localFile == null || remoteFile == null) {
        diffCount++;
      } else {
        // Compare hash and structure
        if (localFile['hash'] != remoteFile['hash'] || 
            localFile['structure'] != remoteFile['structure']) {
          diffCount++;
        }
      }
    }

    return {
      'localEncryptedCount': localEncryptedCount,
      'cloudEncryptedCount': cloudEncryptedCount,
      'diffCount': diffCount,
    };
  }
}
