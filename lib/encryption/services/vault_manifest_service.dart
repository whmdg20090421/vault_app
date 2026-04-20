import 'dart:convert';
import 'dart:typed_data';
import '../../vfs/encrypted_vfs.dart';
import '../../vfs/local_vfs.dart';

class VaultManifestService {
  static const String manifestPath = '/.vault_manifest';

  Future<Map<String, dynamic>> load({
    required String vaultDirectoryPath,
    required Uint8List masterKey,
    required bool encryptFilename,
  }) async {
    final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
    final encryptedVfs = EncryptedVfs(
      baseVfs: localVfs,
      masterKey: masterKey,
      encryptFilename: encryptFilename,
    );
    await encryptedVfs.initEncryptedDomain('/');

    try {
      final stream = await encryptedVfs.open(manifestPath);
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      if (chunks.isEmpty) {
        return _emptyManifest();
      }
      final jsonMap = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
      return _normalizeManifest(jsonMap);
    } catch (_) {
      return _emptyManifest();
    }
  }

  Future<void> save({
    required String vaultDirectoryPath,
    required Uint8List masterKey,
    required bool encryptFilename,
    required Map<String, dynamic> manifest,
  }) async {
    final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
    final encryptedVfs = EncryptedVfs(
      baseVfs: localVfs,
      masterKey: masterKey,
      encryptFilename: encryptFilename,
    );
    await encryptedVfs.initEncryptedDomain('/');

    final normalized = _normalizeManifest(manifest);
    final bytes = utf8.encode(jsonEncode(normalized));
    await encryptedVfs.uploadStream(Stream.value(bytes), bytes.length, manifestPath);
  }

  Map<String, dynamic> _emptyManifest() {
    return {
      'version': 1,
      'entries': <String, dynamic>{},
    };
  }

  Map<String, dynamic> _normalizeManifest(Map<String, dynamic> manifest) {
    final version = manifest['version'] is int ? manifest['version'] as int : 1;
    final entriesRaw = manifest['entries'];
    final entries = entriesRaw is Map ? Map<String, dynamic>.from(entriesRaw as Map) : <String, dynamic>{};
    return {
      'version': version,
      'entries': entries,
    };
  }
}

