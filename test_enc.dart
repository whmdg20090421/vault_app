import 'dart:io';
import 'dart:typed_data';
import 'package:vault/vfs/local_vfs.dart';
import 'package:vault/vfs/encrypted_vfs.dart';

void main() async {
  final tempVaultDir = await Directory.systemTemp.createTemp('vault_test_');
  final tempSourceDir = await Directory.systemTemp.createTemp('source_test_');
  final mockMasterKey = Uint8List.fromList(List.generate(32, (i) => i));

  final sourceFile = File('${tempSourceDir.path}/test.txt');
  await sourceFile.writeAsString('Hello Plaintext');

  final localVfs = LocalVfs(rootPath: tempVaultDir.path);
  final encryptedVfs = EncryptedVfs(
    baseVfs: localVfs,
    masterKey: mockMasterKey,
    encryptFilename: false,
  );
  await encryptedVfs.initEncryptedDomain('/');

  final size = await sourceFile.length();
  final stream = sourceFile.openRead();

  await encryptedVfs.uploadStream(stream, size, '/test.txt');

  final importedFile = File('${tempVaultDir.path}/test.txt');
  if (await importedFile.exists()) {
    print('Imported file exists, size: ${await importedFile.length()}');
    final contentBytes = await importedFile.readAsBytes();
    print('First 16 bytes: ${contentBytes.sublist(0, 16)}');
  } else {
    print('Imported file NOT FOUND!');
  }

  await tempVaultDir.delete(recursive: true);
  await tempSourceDir.delete(recursive: true);
}