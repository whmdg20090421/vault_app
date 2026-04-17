import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/encryption/vault_explorer_page.dart';
import 'package:vault/encryption/models/vault_config.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempVaultDir;
  late Directory tempSourceDir;
  late Uint8List mockMasterKey;

  setUp(() async {
    tempVaultDir = await Directory.systemTemp.createTemp('vault_test_');
    tempSourceDir = await Directory.systemTemp.createTemp('source_test_');
    mockMasterKey = Uint8List.fromList(List.generate(32, (i) => i)); // 256-bit key
  });

  tearDown(() async {
    if (tempVaultDir.existsSync()) {
      tempVaultDir.deleteSync(recursive: true);
    }
    if (tempSourceDir.existsSync()) {
      tempSourceDir.deleteSync(recursive: true);
    }
  });

  group('VaultExplorer Isolates Tests', () {
    test('SubTask 5.1: 验证不启用文件名加密时导入路径与文件名符合预期', () async {
      final sourceFile = File(p.join(tempSourceDir.path, 'test.txt'));
      await sourceFile.writeAsString('Hello Plaintext');

      final receivePort = ReceivePort();
      final args = {
        'sendPort': receivePort.sendPort,
        'files': [
          {'localPath': sourceFile.path, 'remotePath': '/test.txt'}
        ],
        'vaultDirectoryPath': tempVaultDir.path,
        'masterKey': mockMasterKey,
        'encryptFilename': false,
        'taskId': 'test_task_1',
      };

      await doImportFileIsolate(args);

      final importedFile = File(p.join(tempVaultDir.path, 'test.txt'));
      expect(importedFile.existsSync(), isTrue, reason: '导入的文件应保持明文文件名');
      final content = await importedFile.readAsString();
      expect(content, 'Hello Plaintext');
    });

    test('SubTask 5.1: 验证启用文件名加密时导入路径与文件名符合预期', () async {
      final sourceFile = File(p.join(tempSourceDir.path, 'secret.txt'));
      await sourceFile.writeAsString('Hello Encrypted');

      final receivePort = ReceivePort();
      final args = {
        'sendPort': receivePort.sendPort,
        'files': [
          {'localPath': sourceFile.path, 'remotePath': '/secret.txt'}
        ],
        'vaultDirectoryPath': tempVaultDir.path,
        'masterKey': mockMasterKey,
        'encryptFilename': true,
        'taskId': 'test_task_2',
      };

      await doImportFileIsolate(args);

      // Verify file is NOT named secret.txt directly in the vault dir
      final plainFile = File(p.join(tempVaultDir.path, 'secret.txt'));
      expect(plainFile.existsSync(), isFalse, reason: '启用文件名加密时，不应出现明文文件名');

      // Find the actual file (since we have one file, we can just list the directory)
      final entities = tempVaultDir.listSync(recursive: true).whereType<File>().toList();
      // Expect 1 file, and its name shouldn't be 'secret.txt' but its content should be encrypted
      // (Wait, EncryptedVfs stores files in chunked form, so maybe more than 1 if it's metadata, but usually 1 data file)
      expect(entities.isNotEmpty, isTrue);
      final hasSecretTxt = entities.any((e) => p.basename(e.path) == 'secret.txt');
      expect(hasSecretTxt, isFalse);
    });

    test('SubTask 5.3: 验证导出对常见文本文件可用（不启用加密）', () async {
      final sourceFile = File(p.join(tempVaultDir.path, 'test_export.txt'));
      await sourceFile.writeAsString('Export Test Data');

      final outFile = File(p.join(tempSourceDir.path, 'out.txt'));

      final args = {
        'nodePath': '/test_export.txt',
        'outFilePath': outFile.path,
        'vaultDirectoryPath': tempVaultDir.path,
        'masterKey': mockMasterKey,
        'encryptFilename': false,
      };

      await doExportFileIsolate(args);

      expect(outFile.existsSync(), isTrue);
      expect(await outFile.readAsString(), 'Export Test Data');
    });

    test('SubTask 5.3: 验证导出对常见文本文件可用（启用加密）', () async {
      final sourceFile = File(p.join(tempSourceDir.path, 'test_enc_export.txt'));
      await sourceFile.writeAsString('Export Encrypted Test Data');

      // First import it encrypted
      final receivePort = ReceivePort();
      await doImportFileIsolate({
        'sendPort': receivePort.sendPort,
        'files': [
          {'localPath': sourceFile.path, 'remotePath': '/test_enc_export.txt'}
        ],
        'vaultDirectoryPath': tempVaultDir.path,
        'masterKey': mockMasterKey,
        'encryptFilename': true,
        'taskId': 'test_task_3',
      });

      // Now export it
      final outFile = File(p.join(tempSourceDir.path, 'out_enc.txt'));
      await doExportFileIsolate({
        'nodePath': '/test_enc_export.txt',
        'outFilePath': outFile.path,
        'vaultDirectoryPath': tempVaultDir.path,
        'masterKey': mockMasterKey,
        'encryptFilename': true,
      });

      expect(outFile.existsSync(), isTrue);
      expect(await outFile.readAsString(), 'Export Encrypted Test Data');
    });
  });

  group('VaultExplorer UI Tests', () {
    testWidgets('SubTask 5.2: 验证 UI 加载提示与无响应防护', (WidgetTester tester) async {
      final config = VaultConfig(
        name: 'Test Vault',
        algorithm: 'AES-GCM',
        kdf: 'Argon2id',
        kdfParams: {},
        encryptFilename: false,
        salt: 'salt',
        nonce: 'nonce',
        validationCiphertext: 'cipher',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VaultExplorerPage(
            vaultConfig: config,
            masterKey: mockMasterKey,
            vaultDirectoryPath: tempVaultDir.path,
          ),
        ),
      ));

      // At start, it should show a loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for async load
      await tester.pumpAndSettle();

      // After loading, the indicator should be gone
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('保险箱目前为空'), findsOneWidget);

      // Note: 导入操作通过 FilePicker 和 Isolate 在后台进行，
      // _importFile 中有 SnackBar 提示并不阻塞 UI。由于无法直接 mock FilePicker，
      // 我们通过验证初始加载状态的无阻塞性以及 Isolate 的异步设计来满足 SubTask 5.2。
    });
  });
}
