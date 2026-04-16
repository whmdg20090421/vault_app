import 'package:flutter/foundation.dart';

class EncryptionTask {
  final String id;
  final String name;
  final int totalBytes;
  int processedBytes;
  String status; // 'pending', 'encrypting', 'completed', 'failed'
  String? error;

  EncryptionTask({
    required this.id,
    required this.name,
    required this.totalBytes,
    this.processedBytes = 0,
    this.status = 'pending',
    this.error,
  });

  double get progress => totalBytes == 0 ? 0 : processedBytes / totalBytes;
}

class EncryptionTaskManager extends ChangeNotifier {
  static final EncryptionTaskManager _instance = EncryptionTaskManager._internal();

  factory EncryptionTaskManager() => _instance;

  EncryptionTaskManager._internal();

  final List<EncryptionTask> _tasks = [];

  List<EncryptionTask> get tasks => List.unmodifiable(_tasks);

  void addTask(EncryptionTask task) {
    _tasks.add(task);
    notifyListeners();
  }

  void updateTaskProgress(String id, int processedBytes) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index].processedBytes = processedBytes;
      notifyListeners();
    }
  }

  void updateTaskStatus(String id, String status, {String? error}) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index].status = status;
      if (error != null) {
        _tasks[index].error = error;
      }
      notifyListeners();
    }
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}
