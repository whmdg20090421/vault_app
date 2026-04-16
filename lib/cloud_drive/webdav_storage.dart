import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'security_level.dart';
import 'webdav_config.dart';

class WebDavFileData {
  const WebDavFileData({
    required this.configs,
    required this.securityLevel,
  });

  final List<WebDavConfig> configs;
  final SecurityLevel? securityLevel;

  Map<String, Object?> toJson() {
    return {
      'securityLevel': securityLevel?.toJson(),
      'configs': configs.map((e) => e.toJson()).toList(),
    };
  }

  static WebDavFileData fromJson(Map<String, Object?> json) {
    final configsJson = json['configs'];
    final configs = (configsJson is List)
        ? configsJson
            .whereType<Map>()
            .map((e) => WebDavConfig.fromJson(e.cast<String, Object?>()))
            .where((e) => e.id.isNotEmpty)
            .toList()
        : <WebDavConfig>[];

    final level = SecurityLevelJson.fromJson(json['securityLevel'] as String?);
    return WebDavFileData(configs: configs, securityLevel: level);
  }
}

abstract class WebDavPasswordStore {
  Future<String?> readPassword(String id);
  Future<void> writePassword(String id, String password);
  Future<void> deletePassword(String id);
}

class FlutterSecurePasswordStore implements WebDavPasswordStore {
  FlutterSecurePasswordStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'webdav_password_';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPassword(String id) {
    return _storage.read(key: '$_prefix$id');
  }

  @override
  Future<void> writePassword(String id, String password) {
    return _storage.write(key: '$_prefix$id', value: password);
  }

  @override
  Future<void> deletePassword(String id) {
    return _storage.delete(key: '$_prefix$id');
  }
}

class WebDavConfigRepository {
  WebDavConfigRepository({
    WebDavPasswordStore? passwordStore,
    Future<Directory> Function()? directoryProvider,
  })  : _passwordStore = passwordStore ?? FlutterSecurePasswordStore(),
        _directoryProvider =
            directoryProvider ?? (() => getApplicationDocumentsDirectory());

  final WebDavPasswordStore _passwordStore;
  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async {
    final dir = await _directoryProvider();
    return File('${dir.path}/webdav_configs.json');
  }

  Future<WebDavFileData> readAll() async {
    final file = await _file();
    if (!await file.exists()) {
      return const WebDavFileData(configs: [], securityLevel: null);
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return const WebDavFileData(configs: [], securityLevel: null);
      }
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return const WebDavFileData(configs: [], securityLevel: null);
      }
      return WebDavFileData.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      return const WebDavFileData(configs: [], securityLevel: null);
    }
  }

  Future<void> _writeAll(WebDavFileData data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data.toJson()), flush: true);
  }

  Future<List<WebDavConfig>> listConfigs() async {
    final data = await readAll();
    return data.configs;
  }

  Future<SecurityLevel?> readSecurityLevel() async {
    final data = await readAll();
    return data.securityLevel;
  }

  Future<void> writeSecurityLevel(SecurityLevel level) async {
    final data = await readAll();
    await _writeAll(
      WebDavFileData(configs: data.configs, securityLevel: level),
    );
  }

  Future<void> upsertConfig(WebDavConfig config, {String? password}) async {
    final data = await readAll();
    final updated = [...data.configs];
    final index = updated.indexWhere((e) => e.id == config.id);
    if (index >= 0) {
      updated[index] = config;
    } else {
      updated.add(config);
    }

    await _writeAll(WebDavFileData(configs: updated, securityLevel: data.securityLevel));

    if (password != null) {
      await _passwordStore.writePassword(config.id, password);
    }
  }

  Future<void> deleteConfig(String id) async {
    final data = await readAll();
    final updated = data.configs.where((e) => e.id != id).toList();
    await _writeAll(WebDavFileData(configs: updated, securityLevel: data.securityLevel));
    await _passwordStore.deletePassword(id);
  }

  Future<String?> readPassword(String id) {
    return _passwordStore.readPassword(id);
  }
}

