import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


import 'services/stats_service.dart';
import 'cloud_drive/cloud_drive_page.dart';
import 'encryption/encryption_page.dart';
import 'cloud_drive/cloud_drive_progress_manager.dart';
import 'cloud_drive/cloud_drive_progress_panel.dart';
import 'cloud_drive/webdav_state_manager.dart';
import 'error_reporter.dart';
import 'about_page.dart';
import 'home_page.dart';

import 'theme/app_theme.dart';
import 'theme/background_settings.dart';
import 'settings/theme_settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSettings.instance.init();
  await ErrorReporter.instance.initialize();
  await StatsService().init();

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
    return ListenableBuilder(
      listenable: Listenable.merge([appTheme, BackgroundSettings.instance]),
      builder: (context, _) {
        final theme = appTheme.value;
        final bg = BackgroundSettings.instance;
        return MaterialApp(
        return _BackgroundShell(
          theme: theme,
          enabled: bg.enabled,
          imagePath: bg.imagePath,
          imageOpacity: bg.imageOpacity,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: '天眼·艨艟战舰',
            theme: buildTheme(theme, bg.enabled, bg.uiOpacity),
            builder: (context, child) => child ?? const SizedBox.shrink(),
            home: const MainShell(),
          ),
        );
    );
  }
}

class MainShell extends StatefulWidget {
class _BackgroundShell extends StatefulWidget {
  const _BackgroundShell({
    required this.theme,
    required this.enabled,
    required this.imagePath,
    required this.imageOpacity,
    required this.child,
  });

  final AppTheme theme;
  final bool enabled;
  final String? imagePath;
  final double imageOpacity;
  final Widget child;

  @override
  State<_BackgroundShell> createState() => _BackgroundShellState();
}

class _BackgroundShellState extends State<_BackgroundShell> {
  ImageProvider? _imageProvider;

  @override
  void initState() {
    super.initState();
    _syncImageProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheIfNeeded());
  }

  @override
  void didUpdateWidget(covariant _BackgroundShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled || oldWidget.imagePath != widget.imagePath) {
      _syncImageProvider();
      WidgetsBinding.instance.addPostFrameCallback((_) => _precacheIfNeeded());
    }
  }

  void _syncImageProvider() {
    if (!widget.enabled || widget.imagePath == null) {
      _imageProvider = null;
      return;
    }

    final file = File(widget.imagePath!);
    if (!file.existsSync()) {
      _imageProvider = null;
      return;
    }

    _imageProvider = FileImage(file);
  }

  Future<void> _precacheIfNeeded() async {
    if (!mounted) return;
    final provider = _imageProvider;
    if (provider == null) return;
    try {
      await precacheImage(provider, context);
      assert(() {
        debugPrint('Background precache ok');
        return true;
      }());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.enabled && _imageProvider != null)
          Positioned.fill(
            child: Opacity(
              opacity: widget.imageOpacity,
              child: Image(
                key: const ValueKey('app_background_layer'),
                image: _imageProvider!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              ),
            ),
          )
        else if (widget.theme == AppTheme.cyberpunk)
          Positioned.fill(
            child: Container(
              key: const ValueKey('app_background_layer'),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F1418), Color(0xFF1A242D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          )
        else if (widget.theme == AppTheme.pureBlack)
          const Positioned.fill(
            child: ColoredBox(
              key: ValueKey('app_background_layer'),
              color: Colors.black,
            ),
          )
        else
          const Positioned.fill(
            child: ColoredBox(
              key: ValueKey('app_background_layer'),
              color: Color(0xFFF8F9FA),
            ),
          ),
        widget.child,
      ],
    );
  }
}

  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}
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
        title: Text(titles[_index].toUpperCase()),
        centerTitle: true,
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          if (value == 1 && _index == 1) {
            showCloudDriveProgressPanel(context);
          } else {
            setState(() => _index = value);
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_rounded),
            label: '主页',
          ),
          NavigationDestination(
            icon: ListenableBuilder(
              listenable: CloudDriveProgressManager.instance,
              builder: (context, _) {
                final manager = CloudDriveProgressManager.instance;
                if (manager.hasActiveTasks) {
                  return const Badge(
                    label: Icon(
                      Icons.sync_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    child: Icon(Icons.cloud_sync_rounded),
                  );
                }
                return const Icon(Icons.cloud_rounded);
              },
            ),
            label: '云盘',
          ),
          const NavigationDestination(
            icon: Icon(Icons.lock_rounded),
            label: '加密',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}


class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('主题与背景设置'),
          trailing: const Icon(Icons.chevron_right_rounded),
          contentPadding: EdgeInsets.zero,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ThemeSettingsPage()),
            );
          },
        ),
        const Divider(),
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
      ],
    );
  }
}
