import 'dart:io';

class WebDavLogger {
  static const String logFilePath = '/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt';

  static void writeErrorLog(String message) {
    try {
      final file = File(logFilePath);
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
      final timestamp = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
    } catch (e) {
      print('Failed to write WebDAV error log: $e');
    }
  }
}
