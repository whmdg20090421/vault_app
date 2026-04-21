import 'package:flutter/foundation.dart';

class ReencryptionTaskState {
  final String vaultPath;
  final String vaultName;
  final int processedBytes;
  final int totalBytes;
  final bool isFinished;
  final String? error;

  ReencryptionTaskState({
    required this.vaultPath,
    required this.vaultName,
    this.processedBytes = 0,
    this.totalBytes = 0,
    this.isFinished = false,
    this.error,
  });

  ReencryptionTaskState copyWith({
    int? processedBytes,
    int? totalBytes,
    bool? isFinished,
    String? error,
  }) {
    return ReencryptionTaskState(
      vaultPath: vaultPath,
      vaultName: vaultName,
      processedBytes: processedBytes ?? this.processedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      isFinished: isFinished ?? this.isFinished,
      error: error ?? this.error,
    );
  }
}

final globalReencryptionTask = ValueNotifier<ReencryptionTaskState?>(null);
