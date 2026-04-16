import 'dart:ui';

import 'package:flutter/material.dart';

import 'cloud_drive/cloud_drive_page.dart';
import 'encryption/encryption_page.dart';
import 'error_reporter.dart';
import 'about_page.dart';
import 'home_page.dart';

enum AppTheme { defaultTheme, cyberpunk }

final ValueNotifier<AppTheme> appTheme = ValueNotifier(AppTheme.defaultTheme);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorReporter.instance.initialize();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorReporter.instance.writeFlutterError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReporter.instance.writeError(error, stack);
    return true;
  };

  runApp(const TianyanApp());
}

class TianyanApp extends StatelessWidget {
  const TianyanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appTheme,
      builder: (context, theme, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '天眼·艨艟战舰',
          theme: _buildTheme(theme),
          home: const MainShell(),
        );
      },
    );
  }
}

ThemeData _buildTheme(AppTheme theme) {
  if (theme == AppTheme.cyberpunk) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFCE205),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFFCE205),
      secondary: const Color(0xFF00F0FF),
      tertiary: const Color(0xFFFF003C),
      surface: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF141414),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF000000),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0A0A0A),
        indicatorColor: const Color(0x33FCE205),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? const Color(0xFFFCE205)
                : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? const Color(0xFFFCE205)
                : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3D5AFE),
      brightness: Brightness.light,
    ),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [
      HomePage(),
      CloudDrivePage(),
      EncryptionPage(),
      SettingsPage(),
    ];

    final titles = const ['主页', '云盘', '加密', '设置'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        centerTitle: true,
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_rounded),
            label: '主页',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_rounded),
            label: '云盘',
          ),
          NavigationDestination(
            icon: Icon(Icons.lock_rounded),
            label: '加密',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class _TitlePage extends StatelessWidget {
  const _TitlePage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: appTheme,
      builder: (context, theme, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于'),
              trailing: const Icon(Icons.chevron_right_rounded),
              contentPadding: EdgeInsets.zero,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutPage()),
                );
              },
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              '主题',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<AppTheme>(
              segments: const [
                ButtonSegment(
                  value: AppTheme.defaultTheme,
                  label: Text('默认主题'),
                  icon: Icon(Icons.auto_awesome_rounded),
                ),
                ButtonSegment(
                  value: AppTheme.cyberpunk,
                  label: Text('赛博朋克'),
                  icon: Icon(Icons.bolt_rounded),
                ),
              ],
              selected: {theme},
              onSelectionChanged: (selection) => appTheme.value = selection.first,
              showSelectedIcon: true,
            ),
          ],
        );
      },
    );
  }
}
