import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../../vfs/encrypted_vfs.dart';
import '../../vfs/local_vfs.dart';

class VaultKeyRotationService {
  Future<void> rotateInPlace({
    required String vaultDirectoryPath,
    required Uint8List oldMasterKey,
    required Uint8List newMasterKey,
    required bool encryptFilename,
  }) async {
    final tmpPath = p.join(vaultDirectoryPath, '.rotate_tmp');
    final backupPath = p.join(vaultDirectoryPath, '.rotate_backup');

    final tmpDir = Directory(tmpPath);
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
    await tmpDir.create(recursive: true);

    final oldLocalVfs = LocalVfs(rootPath: vaultDirectoryPath);
    final oldEncryptedVfs = EncryptedVfs(
      baseVfs: oldLocalVfs,
      masterKey: oldMasterKey,
      encryptFilename: encryptFilename,
    );
    await oldEncryptedVfs.initEncryptedDomain('/');

    final newLocalVfs = LocalVfs(rootPath: tmpPath);
    final newEncryptedVfs = EncryptedVfs(
      baseVfs: newLocalVfs,
      masterKey: newMasterKey,
      encryptFilename: encryptFilename,
    );
    await newEncryptedVfs.initEncryptedDomain('/');

    Future<void> copyNode(String dirPath) async {
      final children = await oldEncryptedVfs.list(dirPath);
      for (final child in children) {
        if (child.isDirectory) {
          await newEncryptedVfs.mkdir(child.path);
          await copyNode(child.path);
        } else {
          final stream = await oldEncryptedVfs.open(child.path);
          await newEncryptedVfs.uploadStream(stream, child.size, child.path);
        }
      }
    }

    await copyNode('/');

    final backupDir = Directory(backupPath);
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }
    await backupDir.create(recursive: true);

    final rootDir = Directory(vaultDirectoryPath);
    final rootEntries = rootDir.listSync();
    for (final entry in rootEntries) {
      final name = p.basename(entry.path);
      if (name == '.rotate_tmp' || name == '.rotate_backup' || name == 'vault_config.json') {
        continue;
      }
      entry.renameSync(p.join(backupPath, name));
    }

    final movedTmpEntries = Directory(tmpPath).listSync();
    for (final entry in movedTmpEntries) {
      final name = p.basename(entry.path);
      entry.renameSync(p.join(vaultDirectoryPath, name));
    }

    await tmpDir.delete(recursive: true);
    await backupDir.delete(recursive: true);
  }
}

