import 'dart:io';

class WebDavLogger {
  static void writeErrorLog(String message) {
    try {
      final file = File('/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt');
      final timestamp = DateTime.now().toIso8601String();
      final logMessage = '[$timestamp] $message\n';
      
      // Ensure the directory exists
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      
      file.writeAsStringSync(logMessage, mode: FileMode.append);
    } catch (e) {
      // Ignore errors when writing log
      print('Failed to write webdav error log: $e');
    }
  }
}
