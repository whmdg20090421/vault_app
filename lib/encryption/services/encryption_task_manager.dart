import 'package:flutter/foundation.dart';

class EncryptionTask {
  final String id;
  final String name;
  final bool isDirectory;
  int _totalBytes;
  int _processedBytes;
  String _status; // 'pending', 'encrypting', 'completed', 'failed'
  String? error;
  final List<EncryptionTask> children;

  EncryptionTask({
    required this.id,
    required this.name,
    this.isDirectory = false,
    int totalBytes = 0,
    int processedBytes = 0,
    String status = 'pending',
    this.error,
    List<EncryptionTask>? children,
  })  : _totalBytes = totalBytes,
        _processedBytes = processedBytes,
        _status = status,
        children = children ?? [];

  int get totalBytes {
    if (children.isEmpty) return _totalBytes;
    return children.fold(0, (sum, child) => sum + child.totalBytes);
  }

  int get processedBytes {
    if (children.isEmpty) return _processedBytes;
    return children.fold(0, (sum, child) => sum + child.processedBytes);
  }

  set totalBytes(int value) => _totalBytes = value;
  set processedBytes(int value) => _processedBytes = value;

  String get status {
    if (children.isEmpty) return _status;
    bool hasFailed = false;
    bool hasEncrypting = false;
    bool hasPending = false;
    bool allCompleted = true;
    for (var child in children) {
      final s = child.status;
      if (s == 'failed') {
        hasFailed = true;
        allCompleted = false;
      }
      if (s == 'encrypting') {
        hasEncrypting = true;
        allCompleted = false;
      }
      if (s == 'pending') {
        hasPending = true;
        allCompleted = false;
      }
    }
    if (hasFailed) return 'failed';
    if (hasEncrypting) return 'encrypting';
    if (allCompleted && children.isNotEmpty) return 'completed';
    if (hasPending) return 'pending';
    return _status;
  }

  set status(String value) => _status = value;

  double get progress => totalBytes == 0 ? 0 : processedBytes / totalBytes;

  EncryptionTask? findById(String targetId) {
    if (id == targetId) return this;
    for (final child in children) {
      final found = child.findById(targetId);
      if (found != null) return found;
    }
    return null;
  }
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

  EncryptionTask? findTask(String id) {
    for (final task in _tasks) {
      final found = task.findById(id);
      if (found != null) return found;
    }
    return null;
  }

  void addChild(String parentId, EncryptionTask child) {
    final parent = findTask(parentId);
    if (parent != null) {
      parent.children.add(child);
      notifyListeners();
    }
  }

  void updateTaskTree(String id, Map<String, dynamic> treeMap) {
    final task = findTask(id);
    if (task != null) {
      task.children.clear();
      task.children.addAll(_parseTree(treeMap['children'] as List<dynamic>));
      notifyListeners();
    }
  }

  List<EncryptionTask> _parseTree(List<dynamic> childrenList) {
    return childrenList.map((c) {
      final map = c as Map<String, dynamic>;
      return EncryptionTask(
        id: map['id'] as String,
        name: map['name'] as String,
        isDirectory: map['isDirectory'] as bool,
        totalBytes: map['totalBytes'] as int,
        children: map.containsKey('children')
            ? _parseTree(map['children'] as List<dynamic>)
            : null,
      );
    }).toList();
  }

  void updateTaskProgress(String id, int processedBytes) {
    final task = findTask(id);
    if (task != null) {
      task.processedBytes = processedBytes;
      notifyListeners();
    }
  }

  void updateTaskStatus(String id, String status, {String? error}) {
    final task = findTask(id);
    if (task != null) {
      task.status = status;
      if (error != null) {
        task.error = error;
      }
      notifyListeners();
    }
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}
