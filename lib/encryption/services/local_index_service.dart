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
    required DateTime updatedAt,
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
        'size': size,
        'updatedAt': updatedAt.toIso8601String(),
        'hash': hash,
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
    localEncryptedCount = localIndex.length;

    return {
      'localEncryptedCount': localEncryptedCount,
      'cloudEncryptedCount': cloudEncryptedCount,
      'diffCount': diffCount,
    };
  }
}
