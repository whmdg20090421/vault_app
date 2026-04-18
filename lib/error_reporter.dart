import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ErrorReporter {
  ErrorReporter._();

  static final ErrorReporter instance = ErrorReporter._();

  File? _logFile;

  Future<void> initialize() async {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final debugDir = Directory('${dir.path}/运行日志');
        await debugDir.create(recursive: true);
        _logFile = File('${debugDir.path}/错误日志.txt');
      } catch (_) {}
    }

  Future<void> writeFlutterError(FlutterErrorDetails details) async {
    await writeError(details.exception, details.stack ?? StackTrace.current);
  }

  Future<void> writeError(Object error, StackTrace stack) async {
    final file = _logFile;
    if (file == null) {
      return;
    }

    try {
      final now = DateTime.now().toIso8601String();
      final message = '$now\n$error\n$stack\n\n';
      await file.writeAsString(message, mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}

