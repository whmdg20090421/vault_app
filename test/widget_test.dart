import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vault/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Background stays during route and overlays', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TianyanApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('app_background_layer')), findsOneWidget);

    final rootContext = tester.element(find.byType(MainShell));

    showDialog<void>(
      context: rootContext,
      builder: (context) {
        return AlertDialog(
          title: const Text('Dialog'),
          content: const Text('Content'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app_background_layer')), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app_background_layer')), findsOneWidget);

    showModalBottomSheet<void>(
      context: rootContext,
      builder: (context) => const SizedBox(height: 80, child: Center(child: Text('Sheet'))),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app_background_layer')), findsOneWidget);

    Navigator.of(rootContext).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app_background_layer')), findsOneWidget);
  });

  testWidgets('Cloud drive WebDAV CRUD (basic)', (WidgetTester tester) async {
    final tempDir = await Directory.systemTemp.createTemp('vault_test_');

    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final storage = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final key = (call.arguments as Map?)?['key'] as String?;
      if (key == null) {
        return null;
      }
      return switch (call.method) {
        'write' => storage[key] = (call.arguments as Map?)?['value'] as String?,
        'read' => storage[key],
        'delete' => storage.remove(key),
        _ => null,
      };
    });

    const securityChannel = MethodChannel('vault/security');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(securityChannel, (call) async {
      if (call.method == 'detectSecurityLevel') {
        return 'level2';
      }
      return null;
    });

    await tester.pumpWidget(const TianyanApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('云盘').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('暂无 WebDAV 配置'), findsOneWidget);

    await tester.tap(find.text('新增 WebDAV'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '我的网盘');
    await tester.enterText(find.byType(TextFormField).at(1), 'https://dav.example.com/remote.php/dav/files/u/');
    await tester.enterText(find.byType(TextFormField).at(2), 'user');
    await tester.enterText(find.byType(TextFormField).at(3), 'pass');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('我的网盘'), findsOneWidget);
    expect(find.text('当前设备仅支持软件级安全存储，已保存但安全等级较低。'), findsOneWidget);

    await tempDir.delete(recursive: true);
  });
}
