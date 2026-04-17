import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/cloud_drive/cloud_drive_page.dart';
import 'package:vault/cloud_drive/security_detector.dart';
import 'package:vault/cloud_drive/security_level.dart';
import 'package:vault/cloud_drive/webdav_config.dart';
import 'package:vault/cloud_drive/webdav_storage.dart';
import 'package:vault/theme/app_theme.dart';

class MockWebDavPasswordStore implements WebDavPasswordStore {
  final Map<String, String> _store = {};

  @override
  Future<String?> readPassword(String id) async => _store[id];

  @override
  Future<void> writePassword(String id, String password) async {
    _store[id] = password;
  }

  @override
  Future<void> deletePassword(String id) async {
    _store.remove(id);
  }

  @override
  Future<bool> hasPassword(String id) async => _store.containsKey(id);
}

class MockSecurityDetector implements SecurityDetector {
  SecurityLevel level = SecurityLevel.level1;

  @override
  Future<SecurityLevel> detect() async => level;
}

void main() {
  group('WebDAV Storage Layer', () {
    late Directory tempDir;
    late WebDavConfigRepository repo;
    late MockWebDavPasswordStore passwordStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('webdav_test');
      passwordStore = MockWebDavPasswordStore();
      repo = WebDavConfigRepository(
        passwordStore: passwordStore,
        directoryProvider: () async => tempDir,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should save and list configs', () async {
      final config = WebDavConfig(
        id: 'test-id-1',
        name: 'My NAS',
        url: 'https://nas.local/webdav',
        username: 'admin',
      );
      
      await repo.upsertConfig(config, password: 'secret_password');

      final configs = await repo.listConfigs();
      expect(configs.length, 1);
      expect(configs.first.id, 'test-id-1');
      expect(configs.first.name, 'My NAS');

      final pwd = await repo.readPassword('test-id-1');
      expect(pwd, 'secret_password');
    });

    test('should delete config and password', () async {
      final config = WebDavConfig(
        id: 'test-id-2',
        name: 'My NAS 2',
        url: 'https://nas.local/webdav',
        username: 'admin',
      );
      
      await repo.upsertConfig(config, password: 'secret_password');
      await repo.deleteConfig('test-id-2');

      final configs = await repo.listConfigs();
      expect(configs.isEmpty, true);

      final hasPwd = await repo.hasPassword('test-id-2');
      expect(hasPwd, false);
    });
  });

  group('CloudDrivePage Widget Test', () {
    late Directory tempDir;
    late WebDavConfigRepository repo;
    late MockSecurityDetector securityDetector;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('webdav_test_widget');
      repo = WebDavConfigRepository(
        passwordStore: MockWebDavPasswordStore(),
        directoryProvider: () async => tempDir,
      );
      securityDetector = MockSecurityDetector();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Widget createWidgetUnderTest() {
      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CloudDrivePage(
            repository: repo,
            securityDetector: securityDetector,
          ),
        ),
      );
    }

    testWidgets('should show empty state initially', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('暂无 WebDAV 配置'), findsOneWidget);
      expect(find.text('新增 WebDAV'), findsOneWidget);
    });

    testWidgets('should add a new WebDAV config and show in list', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap add button
      await tester.tap(find.text('新增 WebDAV'));
      await tester.pumpAndSettle();

      // Find form fields
      expect(find.text('命名'), findsOneWidget);
      expect(find.text('连接网站（URL）'), findsOneWidget);
      
      // Enter values
      await tester.enterText(find.widgetWithText(TextFormField, '命名'), 'Home NAS');
      await tester.enterText(find.widgetWithText(TextFormField, '连接网站（URL）'), 'https://home.local/dav');
      await tester.enterText(find.widgetWithText(TextFormField, '账户名'), 'testuser');
      await tester.enterText(find.widgetWithText(TextFormField, '授权密码'), 'testpass');
      
      // Save
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // Since securityLevel was null initially, it will show a security dialog
      expect(find.text('安全存储提示'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();

      // Should be back to list and see the new config
      expect(find.text('Home NAS'), findsOneWidget);
      expect(find.text('testuser · https://home.local/dav'), findsOneWidget);
    });

    testWidgets('should show Level 2 warning banner if detected as level2', (tester) async {
      securityDetector.level = SecurityLevel.level2;
      await repo.writeSecurityLevel(SecurityLevel.level2); // Pre-set level to 2
      
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('当前设备仅支持软件级安全存储，已保存但安全等级较低。'), findsOneWidget);
      expect(find.byIcon(Icons.warning_rounded), findsWidgets);
    });
  });
}
