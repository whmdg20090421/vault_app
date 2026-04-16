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

extension ThemeCyberpunk on ThemeData {
  bool get isCyberpunk => brightness == Brightness.dark && colorScheme.primary.value == 0xFF00E5FF;
}


enum AppTheme { defaultTheme, cyberpunk, pureBlack }

class BackgroundSettings extends ChangeNotifier {
  bool _enabled = false;
  String? _imagePath;
  double _imageOpacity = 1.0;
  double _uiOpacity = 0.8;

  bool get enabled => _enabled;
  String? get imagePath => _imagePath;
  double get imageOpacity => _imageOpacity;
  double get uiOpacity => _uiOpacity;

  BackgroundSettings._();
  static final instance = BackgroundSettings._();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('bg_enabled') ?? false;
    _imagePath = prefs.getString('bg_image_path');
    _imageOpacity = prefs.getDouble('bg_image_opacity') ?? 1.0;
    _uiOpacity = prefs.getDouble('bg_ui_opacity') ?? 0.8;
  }

  Future<void> setEnabled(bool val) async {
    _enabled = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_enabled', val);
  }

  Future<void> setImagePath(String? val) async {
    _imagePath = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (val != null) {
      await prefs.setString('bg_image_path', val);
    } else {
      await prefs.remove('bg_image_path');
    }
  }

  Future<void> setImageOpacity(double val) async {
    _imageOpacity = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bg_image_opacity', val);
  }

  Future<void> setUiOpacity(double val) async {
    _uiOpacity = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bg_ui_opacity', val);
  }
}


final ValueNotifier<AppTheme> appTheme = ValueNotifier(AppTheme.defaultTheme);

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
      listenable: Listenable.merge([appTheme, BackgroundSettings.instance, WebDAVStateManager.instance]),
      builder: (context, _) {
        final theme = appTheme.value;
        final bg = BackgroundSettings.instance;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '天眼·艨艟战舰',
          theme: _buildTheme(theme, bg.enabled, bg.uiOpacity),
          builder: (context, child) {
            return Stack(
              children: [
                if (bg.enabled && bg.imagePath != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: bg.imageOpacity,
                      child: Image.file(
                        File(bg.imagePath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else if (theme == AppTheme.cyberpunk)
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0F1418), Color(0xFF1A242D)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  )
                else if (theme == AppTheme.pureBlack)
                  Positioned.fill(
                    child: Container(color: Colors.black),
                  )
                else
                  Positioned.fill(
                    child: Container(color: Color(0xFFF8F9FA)),
                  ),
                if (child != null) child,
              ],
            );
          },
          home: const MainShell(),
        );
      },
    );
  }
}

ThemeData _buildTheme(AppTheme theme, bool bgEnabled, double uiOpacity) {
  Color applyUiOpacity(Color color) {
    if (!bgEnabled) return color;
    return color.withValues(alpha: uiOpacity);
  }

  if (theme == AppTheme.pureBlack) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.grey,
      brightness: Brightness.dark,
    ).copyWith(
      primary: Colors.white,
      secondary: Colors.grey,
      surface: Colors.black,
      surfaceContainer: const Color(0xFF111111),
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      cardTheme: CardThemeData(
        color: applyUiOpacity(scheme.surfaceContainer),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: applyUiOpacity(scheme.primary),
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: const BorderSide(color: Colors.grey, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: applyUiOpacity(scheme.surfaceContainer),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        labelStyle: const TextStyle(color: Colors.grey),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.white,
        linearTrackColor: Color(0xFF111111),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: applyUiOpacity(scheme.primary),
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          side: WidgetStateProperty.all(const BorderSide(color: Colors.grey, width: 1)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return applyUiOpacity(scheme.primary);
            return applyUiOpacity(scheme.surfaceContainer);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.onPrimary;
            return scheme.primary;
          }),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: applyUiOpacity(const Color(0xFF111111)),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: applyUiOpacity(scheme.surfaceContainer),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
        contentTextStyle: const TextStyle(color: Colors.grey, fontSize: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: applyUiOpacity(scheme.surfaceContainer),
        indicatorColor: applyUiOpacity(scheme.primary),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontWeight: FontWeight.bold,
            color: states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: applyUiOpacity(Colors.black),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 20,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
    );
  }

  if (theme == AppTheme.cyberpunk) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00E5FF),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF00E5FF),
      secondary: const Color(0xFFFCE205),
      tertiary: const Color(0xFFFF003C),
      surface: const Color(0xFF121A21),
      surfaceContainer: const Color(0xFF1A242D),
      onPrimary: const Color(0xFF0F1418),
      onSecondary: const Color(0xFF0F1418),
      onSurface: const Color(0xFFE0E0E0),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 2.0),
        displayMedium: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 2.0),
        displaySmall: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 2.0),
        headlineLarge: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        headlineMedium: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        headlineSmall: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        titleLarge: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.2),
        titleMedium: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.2),
        titleSmall: TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.2),
        bodyLarge: TextStyle(fontFamily: 'monospace'),
        bodyMedium: TextStyle(fontFamily: 'monospace'),
        bodySmall: TextStyle(fontFamily: 'monospace'),
        labelLarge: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
        labelMedium: TextStyle(fontFamily: 'monospace'),
        labelSmall: TextStyle(fontFamily: 'monospace'),
      ),
      cardTheme: CardThemeData(
        color: applyUiOpacity(scheme.surfaceContainer),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1),
        ),
        elevation: 8,
        shadowColor: const Color(0xFF00E5FF).withValues(alpha: 0.5),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: applyUiOpacity(scheme.primary),
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 10,
          shadowColor: scheme.primary,
          textStyle: const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: const BorderSide(color: Color(0xFF00E5FF), width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: applyUiOpacity(scheme.surfaceContainer),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
        ),
        labelStyle: const TextStyle(fontFamily: 'monospace', color: Color(0xFF00E5FF)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFF00E5FF),
        linearTrackColor: Color(0xFF1A242D),
        linearMinHeight: 2,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: applyUiOpacity(scheme.primary),
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          side: WidgetStateProperty.all(const BorderSide(color: Color(0xFF00E5FF), width: 1)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return applyUiOpacity(scheme.primary);
            }
            return applyUiOpacity(scheme.surfaceContainer);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onPrimary;
            }
            return scheme.primary;
          }),
          textStyle: WidgetStateProperty.all(const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: applyUiOpacity(const Color(0xFF1A242D)),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: applyUiOpacity(scheme.surfaceContainer),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1),
        ),
        titleTextStyle: const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Color(0xFF00E5FF), fontSize: 20),
        contentTextStyle: const TextStyle(fontFamily: 'monospace', color: Color(0xFFE0E0E0), fontSize: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: applyUiOpacity(scheme.surfaceContainer),
        indicatorColor: applyUiOpacity(scheme.primary),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'sans-serif',
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: applyUiOpacity(const Color(0xFF0F1418)),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontFamily: 'sans-serif',
          fontWeight: FontWeight.bold,
          fontSize: 20,
          letterSpacing: 2.0,
          color: Color(0xFF00E5FF),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
        shape: const Border(bottom: BorderSide(color: Color(0xFF00E5FF), width: 1)),
      ),
    );
  }

  final lightScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3D5AFE),
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: lightScheme,
    scaffoldBackgroundColor: Colors.transparent,
    cardTheme: CardThemeData(
      color: applyUiOpacity(lightScheme.surfaceContainer),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: applyUiOpacity(lightScheme.surface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: applyUiOpacity(lightScheme.surfaceContainer),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: applyUiOpacity(lightScheme.surfaceContainer),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: applyUiOpacity(lightScheme.surfaceContainer),
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
              '主题'.toUpperCase(),
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
                ButtonSegment(
                  value: AppTheme.pureBlack,
                  label: Text('极简黑'),
                  icon: Icon(Icons.dark_mode_rounded),
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
