import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class EncryptionTask {
  final String id;
  final String name;
  final bool isDirectory;
  int _totalBytes;
  int _processedBytes;
  String _status; // 'pending', 'encrypting', 'completed', 'failed', 'paused'
  String? error;
  final List<EncryptionTask> children;
  final Map<String, dynamic>? taskArgs;

  EncryptionTask({
    required this.id,
    required this.name,
    this.isDirectory = false,
    int totalBytes = 0,
    int processedBytes = 0,
    String status = 'pending',
    this.error,
    List<EncryptionTask>? children,
    this.taskArgs,
  })  : _totalBytes = totalBytes,
        _processedBytes = processedBytes,
        _status = status,
        children = children ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isDirectory': isDirectory,
        'totalBytes': _totalBytes,
        'processedBytes': _processedBytes,
        'status': _status,
        'error': error,
        'children': children.map((c) => c.toJson()).toList(),
        'taskArgs': taskArgs,
      };

  factory EncryptionTask.fromJson(Map<String, dynamic> json) {
    return EncryptionTask(
      id: json['id'] as String,
      name: json['name'] as String,
      isDirectory: json['isDirectory'] as bool? ?? false,
      totalBytes: json['totalBytes'] as int? ?? 0,
      processedBytes: json['processedBytes'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      error: json['error'] as String?,
      children: (json['children'] as List<dynamic>?)
          ?.map((c) => EncryptionTask.fromJson(c as Map<String, dynamic>))
          .toList(),
      taskArgs: json['taskArgs'] as Map<String, dynamic>?,
    );
  }

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
    if (children.isEmpty) {
      if (_status == 'pending' && _processedBytes > 0 && _processedBytes < _totalBytes) {
        return 'encrypting';
      }
      if (_status == 'pending' && _processedBytes == _totalBytes && _totalBytes > 0) {
        return 'completed';
      }
      return _status;
    }
    bool hasFailed = false;
    bool hasEncrypting = false;
    bool hasPending = false;
    bool hasPaused = false;
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
      if (s == 'paused') {
        hasPaused = true;
        allCompleted = false;
      }
    }
    if (hasFailed) return 'failed';
    if (hasEncrypting) return 'encrypting';
    if (hasPaused) return 'paused';
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

  EncryptionTaskManager._internal() {
    _loadQueue();
  }

  final List<EncryptionTask> _tasks = [];
  bool _isSaving = false;

  List<EncryptionTask> get tasks => List.unmodifiable(_tasks);

  Future<void> _loadQueue() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/encryption_queue.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isEmpty) return;
        final List<dynamic> jsonList = jsonDecode(content);
        final loadedTasks = jsonList.map((e) => EncryptionTask.fromJson(e as Map<String, dynamic>)).toList();
        
        // Pause all ongoing tasks, fail interrupted files
        for (var task in loadedTasks) {
          _pauseOrFailTaskRecursive(task);
        }
        
        _tasks.addAll(loadedTasks);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load encryption queue: $e');
    }
  }

  void _pauseOrFailTaskRecursive(EncryptionTask task) {
    if (task.children.isEmpty) {
      // If it's a file and it was encrypting or partially done
      if (task.status == 'encrypting' || (task.processedBytes > 0 && task.processedBytes < task.totalBytes)) {
        task.status = 'failed';
        task.processedBytes = 0;
        task.error = 'Encryption interrupted';
      }
    } else {
      // It's a directory
      for (var child in task.children) {
        _pauseOrFailTaskRecursive(child);
      }
      // If the overall task was in progress, mark it as paused so user can manually resume
      if (task.status == 'encrypting' || task.status == 'pending') {
        task.status = 'paused';
      }
    }
  }

  Timer? _saveTimer;

  Future<void> _saveQueue() async {
    if (_isSaving) {
      // If currently saving, schedule another save soon
      _scheduleSave();
      return;
    }
    _isSaving = true;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/encryption_queue.json');
      final jsonString = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      debugPrint('Failed to save encryption queue: $e');
    } finally {
      _isSaving = false;
    }
  }

  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveQueue();
    });
  }

  void addTask(EncryptionTask task) {
    _tasks.add(task);
    _saveQueue();
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
      _saveQueue();
      notifyListeners();
    }
  }

  void updateTaskTree(String id, Map<String, dynamic> treeMap) {
    final task = findTask(id);
    if (task != null) {
      task.children.clear();
      task.children.addAll(_parseTree(treeMap['children'] as List<dynamic>));
      _saveQueue();
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
      _saveQueue();
      notifyListeners();
    }
  }

  void updateTaskStatus(String id, String status, {String? error}) {
    final task = findTask(id);
    if (task != null) {
      _updateStatusRecursive(task, status);
      if (error != null) {
        task.error = error;
      }
      _saveQueue();
      notifyListeners();
    }
  }

  void _updateStatusRecursive(EncryptionTask task, String status) {
    task.status = status;
    for (final child in task.children) {
      _updateStatusRecursive(child, status);
    }
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    _saveQueue();
    notifyListeners();
  }
}
