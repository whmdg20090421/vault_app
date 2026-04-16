import 'dart:ui';

import 'package:flutter/material.dart';

import 'services/stats_service.dart';
import 'cloud_drive/cloud_drive_page.dart';
import 'encryption/encryption_page.dart';
import 'cloud_drive/cloud_drive_progress_manager.dart';
import 'cloud_drive/cloud_drive_progress_panel.dart';
import 'error_reporter.dart';
import 'about_page.dart';
import 'home_page.dart';

extension ThemeCyberpunk on ThemeData {
  bool get isCyberpunk => brightness == Brightness.dark && colorScheme.primary.value == 0xFF00E5FF;
}

enum AppTheme { defaultTheme, cyberpunk }

class CyberpunkBorder extends ShapeBorder {
  final Color color;
  final double borderWidth;
  final double thickBorderWidth;
  final double cornerLength;

  const CyberpunkBorder({
    this.color = const Color(0xFF00E5FF),
    this.borderWidth = 1.0,
    this.thickBorderWidth = 4.0,
    this.cornerLength = 10.0,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.fromLTRB(thickBorderWidth, borderWidth, borderWidth, borderWidth);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return getOuterPath(rect.deflate(borderWidth), textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path();
    path.addRect(rect);
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    // Draw main border
    canvas.drawRect(rect, paint);

    // Draw left thick border
    final thickPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.top, rect.left + thickBorderWidth, rect.bottom),
      thickPaint,
    );

    // Draw corner crosshairs / angled lines
    final crosshairPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(cornerLength, 0), crosshairPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, cornerLength), crosshairPaint);

    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-cornerLength, 0), crosshairPaint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, cornerLength), crosshairPaint);

    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(cornerLength, 0), crosshairPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -cornerLength), crosshairPaint);

    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-cornerLength, 0), crosshairPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -cornerLength), crosshairPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return CyberpunkBorder(
      color: color,
      borderWidth: borderWidth * t,
      thickBorderWidth: thickBorderWidth * t,
      cornerLength: cornerLength * t,
    );
  }
}

final ValueNotifier<AppTheme> appTheme = ValueNotifier(AppTheme.defaultTheme);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      scaffoldBackgroundColor: const Color(0xFF0F1418),
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
      cardTheme: CardTheme(
        color: scheme.surfaceContainer,
        shape: const CyberpunkBorder(),
        elevation: 8,
        shadowColor: const Color(0xFF00E5FF).withValues(alpha: 0.5),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: const CyberpunkBorder(thickBorderWidth: 2.0),
          elevation: 10,
          shadowColor: scheme.primary,
          textStyle: const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide.none, // We use CyberpunkBorder to draw it
          shape: const CyberpunkBorder(thickBorderWidth: 2.0),
          textStyle: const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: const CyberpunkBorder(thickBorderWidth: 0.0),
          textStyle: const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFF00E5FF), width: 1),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFF00E5FF), width: 1),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFF00E5FF), width: 2),
        ),
        labelStyle: const TextStyle(fontFamily: 'monospace', color: Color(0xFF00E5FF)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFF00E5FF),
        linearTrackColor: Color(0xFF1A242D),
        linearMinHeight: 2,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const CyberpunkBorder(thickBorderWidth: 4.0),
        elevation: 8,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(const CyberpunkBorder(thickBorderWidth: 2.0)),
          side: WidgetStateProperty.all(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return scheme.surfaceContainer;
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
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1A242D),
        shape: CyberpunkBorder(thickBorderWidth: 4.0),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surfaceContainer,
        shape: const CyberpunkBorder(thickBorderWidth: 4.0),
        titleTextStyle: const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Color(0xFF00E5FF), fontSize: 20),
        contentTextStyle: const TextStyle(fontFamily: 'monospace', color: Color(0xFFE0E0E0), fontSize: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primary,
        indicatorShape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
        backgroundColor: const Color(0xFF0F1418),
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
        shape: const Border(bottom: BorderSide(color: Color(0xFF00E5FF), width: 2)),
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
