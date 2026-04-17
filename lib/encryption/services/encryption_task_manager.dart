import '../../encryption/vault_explorer_page.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EncryptionTask {
  final String id;
  final String name;
  final bool isDirectory;
  int _totalBytes;
  int _processedBytes;
  String _status; // 'pending', 'encrypting', 'completed', 'failed', 'paused'
  String? error;
  final List<EncryptionTask> children;
  Map<String, dynamic>? taskArgs;

  int _lastReportTime = 0;
  int _lastProcessedBytes = 0;
  double _currentSpeed = 0;
  int _etaSeconds = 0;

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

  Map<String, dynamic> toJson() {
    final safeArgs = taskArgs == null ? null : Map<String, dynamic>.from(taskArgs!);
    if (safeArgs != null) {
      safeArgs.remove('masterKey');
      safeArgs.remove('sendPort');
    }
    return {
      'id': id,
      'name': name,
      'isDirectory': isDirectory,
      'totalBytes': _totalBytes,
      'processedBytes': _processedBytes,
      'status': _status,
      'error': error,
      'children': children.map((c) => c.toJson()).toList(),
      'taskArgs': safeArgs,
    };
  }

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
  set processedBytes(int value) {
    if (children.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastReportTime > 0 && now > _lastReportTime) {
        final diffTime = (now - _lastReportTime) / 1000.0;
        final diffBytes = value - _lastProcessedBytes;
        if (diffTime > 0) {
          final speed = diffBytes / diffTime;
          if (_currentSpeed == 0) {
            _currentSpeed = speed;
          } else {
            _currentSpeed = _currentSpeed * 0.7 + speed * 0.3;
          }
          final remainingBytes = _totalBytes - value;
          if (_currentSpeed > 0) {
            _etaSeconds = (remainingBytes / _currentSpeed).round();
          }
        }
      } else {
        _lastReportTime = DateTime.now().millisecondsSinceEpoch;
      }
      _lastReportTime = now;
      _lastProcessedBytes = value;
    }
    _processedBytes = value;
  }

  double get currentSpeed {
    if (children.isEmpty) {
      return (_status == 'encrypting' || _status == 'pending') ? _currentSpeed : 0;
    }
    return children.fold(0.0, (sum, child) => sum + child.currentSpeed);
  }

  int get etaSeconds {
    if (children.isEmpty) {
      return (_status == 'encrypting' || _status == 'pending') ? _etaSeconds : 0;
    }
    final speed = currentSpeed;
    if (speed <= 0) return 0;
    final remainingBytes = totalBytes - processedBytes;
    return (remainingBytes / speed).round();
  }

  void resetSpeed() {
    _lastReportTime = 0;
    _lastProcessedBytes = 0;
    _currentSpeed = 0;
    _etaSeconds = 0;
    for (var child in children) {
      child.resetSpeed();
    }
  }

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

  set status(String value) {
    _status = value;
    if (value != 'encrypting' && value != 'pending') {
      resetSpeed();
    }
  }

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

  
  int _activeWorkers = 0;
  int _maxWorkers = 2;
  final ReceivePort _globalReceivePort = ReceivePort();

  EncryptionTaskManager._internal() {
    _loadQueue();
    _globalReceivePort.listen(_handleMessage);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _maxWorkers = prefs.getInt('encryption_cores') ?? (Platform.numberOfProcessors ~/ 2).clamp(1, 999);
  }

  void _handleMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      final type = message['type'];
      final tid = message['taskId'] as String;
      if (type == 'progress') {
        updateTaskProgress(tid, message['bytes'] as int);
      } else if (type == 'done') {
        updateTaskStatus(tid, 'completed');
        _activeWorkers--;
        pumpQueue();
      } else if (type == 'error') {
        updateTaskStatus(tid, 'failed', error: message['error'] as String?);
        _activeWorkers--;
        pumpQueue();
      }
    }
  }

  EncryptionTask? _findRootOf(String targetId) {
    for (final task in _tasks) {
      if (task.findById(targetId) != null) return task;
    }
    return null;
  }

  String? _findRemotePathOf(EncryptionTask root, String targetId) {
    // We need to reconstruct the remote path.
    // The tree structure matches the remote path relative to currentPath + baseName
    if (root.taskArgs == null) return null;
    final currentPath = root.taskArgs!['currentPath'] as String;
    final result = root.taskArgs!['result'] as String;
    // Actually, vault_explorer_page constructs remotePath by traversing.
    // To simplify, we can store remotePath in taskArgs or compute it here.
    return _computeRemotePath(root, targetId, currentPath + '/' + root.name);
  }

  String? _computeRemotePath(EncryptionTask current, String targetId, String currentRemotePath) {
    if (current.id == targetId) return currentRemotePath;
    for (final child in current.children) {
      final path = currentRemotePath + '/' + child.name;
      final found = _computeRemotePath(child, targetId, path);
      if (found != null) return found;
    }
    return null;
  }

  String? _findLocalPathOf(EncryptionTask root, String targetId) {
    if (root.id == targetId && root.taskArgs != null) return root.taskArgs!['result'] as String;
    for (final child in root.children) {
      final found = _findLocalPathOf(child, targetId);
      if (found != null) return found;
    }
    return null;
  }

  EncryptionTask? _findNextPendingFile(List<EncryptionTask> list) {
    for (final task in list) {
      if (task.isDirectory) {
        if (task.status == 'paused') continue;
        final found = _findNextPendingFile(task.children);
        if (found != null) return found;
      } else {
        if (task.status == 'pending') return task;
      }
    }
    return null;
  }

  void pumpQueue() async {
    await _loadSettings();
    while (_activeWorkers < _maxWorkers) {
      final task = _findNextPendingFile(_tasks);
      if (task == null) break;

      final root = _findRootOf(task.id);
      if (root == null || root.taskArgs == null || root.taskArgs!['masterKey'] == null) {
        task.status = 'failed';
        task.error = 'Missing credentials or root task';
        continue;
      }

      final localPath = task.taskArgs?['path'] as String? ?? _findLocalPathOf(root, task.id);
      final remotePath = task.taskArgs?['remotePath'] as String? ?? _findRemotePathOf(root, task.id);

      if (localPath == null || remotePath == null) {
        task.status = 'failed';
        task.error = 'Path not found';
        continue;
      }

      task.status = 'encrypting';
      _activeWorkers++;
      notifyListeners();

      final args = {
        'sendPort': _globalReceivePort.sendPort,
        'files': [{'localPath': localPath, 'remotePath': remotePath}],
        'vaultDirectoryPath': root.taskArgs!['vaultDirectoryPath'],
        'masterKey': root.taskArgs!['masterKey'],
        'encryptFilename': root.taskArgs!['encryptFilename'],
        'taskId': task.id,
      };

      Isolate.spawn(doImportFileIsolate, args).then((isolate) {
        registerIsolate(task.id, isolate);
      });
    }
  }

  final List<EncryptionTask> _tasks = [];
  final Map<String, Isolate> _isolates = {};
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
      if (task.status == 'encrypting' || (task.processedBytes > 0 && task.processedBytes < task.totalBytes)) {
        task.status = 'failed';
        task.processedBytes = 0;
        task.error = 'Encryption interrupted';
      }
    } else {
      for (var child in task.children) {
        _pauseOrFailTaskRecursive(child);
      }
      if (task.status == 'encrypting' || task.status == 'pending') {
        task.status = 'paused';
      }
    }
  }

  Timer? _saveTimer;

  Future<void> _saveQueue() async {
    if (_isSaving) {
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
      pumpQueue();
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
      _scheduleSave();
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
    if (task.children.isEmpty) {
      if (task.status == 'completed') return;
      if (status == 'paused' && task.status == 'failed') return;
    }
    
    task.status = status;
    for (final child in task.children) {
      _updateStatusRecursive(child, status);
    }
  }

  void removeTask(String id) {
    final task = findTask(id);
    if (task != null) {
      cancelTask(id);
      if (_tasks.contains(task)) {
        _tasks.remove(task);
      } else {
        _removeChildRecursive(_tasks, id);
      }
      _saveQueue();
      notifyListeners();
    }
  }

  bool _removeChildRecursive(List<EncryptionTask> tasks, String id) {
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].id == id) {
        tasks.removeAt(i);
        return true;
      }
      if (_removeChildRecursive(tasks[i].children, id)) {
        return true;
      }
    }
    return false;
  }

  void registerIsolate(String taskId, Isolate isolate) {
    _isolates[taskId] = isolate;
  }

  void cancelTask(String taskId) {
    final task = findTask(taskId);
    if (task != null) {
      _killIsolatesRecursive(task);
      _updateStatusRecursive(task, 'failed');
      _saveQueue();
      notifyListeners();
    }
  }

  void pauseTask(String taskId) {
    final task = findTask(taskId);
    if (task != null) {
      _killIsolatesRecursive(task);
      _updateStatusRecursive(task, 'paused');
      _saveQueue();
      notifyListeners();
    }
  }

  void _killIsolatesRecursive(EncryptionTask task) {
    if (_isolates.containsKey(task.id)) {
      _isolates[task.id]?.kill(priority: Isolate.immediate);
      _isolates.remove(task.id);
    }
    for (final child in task.children) {
      _killIsolatesRecursive(child);
    }
  }

  bool get hasActiveTasks {
    bool hasActive = false;
    for (final task in _tasks) {
      if (task.status == 'encrypting' || task.status == 'pending') {
        hasActive = true;
        break;
      }
    }
    return hasActive;
  }

  void pauseAll() {
    for (final task in _tasks) {
      if (task.status == 'encrypting' || task.status == 'pending') {
        pauseTask(task.id);
      }
    }
  }

  void resumeAll() {
    for (final task in _tasks) {
      if (task.status == 'paused') {
        updateTaskStatus(task.id, 'pending');
      }
    }
  }
}
