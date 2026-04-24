import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SettingsManager extends ChangeNotifier {
  static final SettingsManager _instance = SettingsManager._internal();
  static SettingsManager get instance => _instance;

  SettingsManager._internal();

  Map<String, dynamic> _settings = {};
  File? _settingsFile;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    
    final directory = await getApplicationDocumentsDirectory();
    _settingsFile = File('${directory.path}/app_settings.json');
    
    if (await _settingsFile!.exists()) {
      try {
        final contents = await _settingsFile!.readAsString();
        _settings = jsonDecode(contents) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error loading settings: $e');
        _settings = {};
      }
    }
    
    _initialized = true;
  }

  Future<void> _saveSettings() async {
    if (_settingsFile == null) return;
    try {
      await _settingsFile!.writeAsString(jsonEncode(_settings));
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  // Generic getters and setters
  T? getValue<T>(String key) {
    return _settings[key] as T?;
  }

  Future<void> setValue<T>(String key, T value) async {
    _settings[key] = value;
    await _saveSettings();
  }

  Future<void> removeValue(String key) async {
    _settings.remove(key);
    await _saveSettings();
  }

  // --- Specific Getters and Setters ---

  // Theme
  int get themeIndex => _settings['theme'] as int? ?? 0;
  Future<void> setThemeIndex(int index) => setValue('theme', index);

  // Background
  bool get bgEnabled => _settings['bg_enabled'] as bool? ?? false;
  Future<void> setBgEnabled(bool value) => setValue('bg_enabled', value);

  String? get bgImagePath => _settings['bg_image_path'] as String?;
  Future<void> setBgImagePath(String? path) {
    if (path == null) {
      return removeValue('bg_image_path');
    }
    return setValue('bg_image_path', path);
  }

  double get bgImageOpacity => (_settings['bg_image_opacity'] as num?)?.toDouble() ?? 1.0;
  Future<void> setBgImageOpacity(double value) => setValue('bg_image_opacity', value);

  double get bgUiOpacity => (_settings['bg_ui_opacity'] as num?)?.toDouble() ?? 0.8;
  Future<void> setBgUiOpacity(double value) => setValue('bg_ui_opacity', value);

  // Encryption Properties
  int? get encryptionCores => _settings['encryption_cores'] as int?;
  Future<void> setEncryptionCores(int cores) => setValue('encryption_cores', cores);

  String get encryptionAllocationStrategy => _settings['encryption_allocation_strategy'] as String? ?? 'smart';
  Future<void> setEncryptionAllocationStrategy(String strategy) => setValue('encryption_allocation_strategy', strategy);

  bool get autoRefreshOnStartup => _settings['auto_refresh_on_startup'] as bool? ?? false;
  Future<void> setAutoRefreshOnStartup(bool value) => setValue('auto_refresh_on_startup', value);

  // Security Settings
  int get securityPermissionMode => _settings['security_permission_mode'] as int? ?? 0;
  Future<void> setSecurityPermissionMode(int mode) => setValue('security_permission_mode', mode);

  int get securityRootBehavior => _settings['security_root_behavior'] as int? ?? 0;
  Future<void> setSecurityRootBehavior(int behavior) => setValue('security_root_behavior', behavior);
}
