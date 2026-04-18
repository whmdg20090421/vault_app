import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import '../../encryption/vault_explorer_page.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/stats_service.dart';
import '../models/encryption_node.dart';
import 'local_index_service.dart';

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
  int completedAt;

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
    this.completedAt = 0,
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
      'completedAt': completedAt,
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
      completedAt: json['completedAt'] as int? ?? 0,
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

Future<void> doEncryptFileIsolate(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final localPath = args['localPath'] as String;
  final remotePath = args['remotePath'] as String;
  final taskId = args['taskId'] as String;
  final absolutePath = args['absolutePath'] as String;

  try {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('File not found: $localPath');
    }
    
    final size = await file.length();
    
    // Simulate encryption
    await Future.delayed(const Duration(milliseconds: 500));
    sendPort.send({'type': 'progress', 'taskId': taskId, 'absolutePath': absolutePath, 'bytes': size});
    
    // Calculate dummy hash for now, or actual hash if we read the file
    // For task 9.1: Calculate hash
    final bytes = await file.readAsBytes();
    final hash = md5.convert(bytes).toString();

    sendPort.send({
      'type': 'done',
      'taskId': taskId,
      'absolutePath': absolutePath,
      'hash': hash,
      'size': size,
      'remotePath': remotePath,
      'vaultDirectoryPath': args['vaultDirectoryPath']
    });
  } catch (e) {
    sendPort.send({'type': 'error', 'taskId': taskId, 'absolutePath': absolutePath, 'error': e.toString()});
  }
}

class EncryptionTaskManager extends ChangeNotifier {
  static final EncryptionTaskManager _instance = EncryptionTaskManager._internal();

  EncryptionTaskManager._internal() {
    _loadHistory();
    _loadQueue();
    _globalReceivePort.listen(_handleMessage);
    _loadSettings();
  }

  factory EncryptionTaskManager() => _instance;

  
  int _activeWorkers = 0;
  int _maxWorkers = 2;
  final ReceivePort _globalReceivePort = ReceivePort();

  int _activeUIListeners = 0;
  bool get isForeground => _activeUIListeners > 0;
  Timer? _refreshTimer;

  void enterForeground() {
    _activeUIListeners++;
    if (_activeUIListeners == 1) {
      _startRefreshLoop();
      _doRefresh();
    }
  }

  void exitForeground() {
    if (_activeUIListeners > 0) {
      _activeUIListeners--;
    }
    if (_activeUIListeners == 0) {
      _startRefreshLoop();
    }
  }

  void _startRefreshLoop() {
    _refreshTimer?.cancel();
    
    if (!hasActiveTasks && !hasActiveTasksV4) {
      return;
    }

    int minMs = isForeground ? 500 : 5000;
    int maxMs = isForeground ? 1000 : 10000;
    int delay = minMs + (DateTime.now().millisecondsSinceEpoch % (maxMs - minMs + 1));

    _refreshTimer = Timer(Duration(milliseconds: delay), () {
      _doRefresh();
      _startRefreshLoop(); // Schedule next refresh
    });
  }

  void _doRefresh() {
    persistGlobalTasks();
    // _saveQueue() can be called here if needed, but currently it's a mock
    
    if (isForeground) {
      notifyListeners();
    }

    if (!hasActiveTasks && !hasActiveTasksV4) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  bool get hasActiveTasksV4 {
    for (final node in _globalTasks) {
      if (_hasActiveNodeV4(node)) return true;
    }
    return false;
  }

  bool _hasActiveNodeV4(EncryptionNode node) {
    if (node.type == EncryptionNodeType.file) {
      return node.status == EncryptionStatus.encrypting || node.status == EncryptionStatus.pendingWaiting;
    }
    if (node.children != null) {
      for (final child in node.children!) {
        if (_hasActiveNodeV4(child)) return true;
      }
    }
    return false;
  }



  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _maxWorkers = prefs.getInt('encryption_cores') ?? (Platform.numberOfProcessors ~/ 2).clamp(1, 999);
  }

  void _handleMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      final type = message['type'];
      final tid = message['taskId'] as String;
      final absolutePath = message['absolutePath'] as String?;
      
      if (absolutePath != null) {
        // V4 message handling
        if (type == 'progress') {
          // Just update bytes if needed, but in V4 we track size/rawSize
          // Refresh loop will handle UI updates
        } else if (type == 'done') {
          _updateNodeStatusV4(absolutePath, EncryptionStatus.completed);
          _recordLocalIndex(
            message['vaultDirectoryPath'] as String,
            '${tid}_${message['remotePath']}',
            message['hash'] as String,
            message['size'] as int,
          );
          _activeWorkers--;
          _checkTaskCompletionV4(tid);
          pumpQueueV4();
        } else if (type == 'error') {
          _updateNodeStatusV4(absolutePath, EncryptionStatus.error);
          _activeWorkers--;
          _checkTaskCompletionV4(tid);
          pumpQueueV4();
        }
      } else {
        // Old message handling
        if (type == 'progress') {
          updateTaskProgress(tid, message['bytes'] as int);
        } else if (type == 'file_imported') {
          _recordLocalIndex(
            message['vaultDirectoryPath'] as String,
            message['remotePath'] as String,
            message['hash'] as String,
            message['size'] as int,
          );
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
  }

  EncryptionNode? _findNodeByPath(List<EncryptionNode> nodes, String path) {
    for (final node in nodes) {
      if (node.absolutePath == path) return node;
      if (node.children != null) {
        final found = _findNodeByPath(node.children!, path);
        if (found != null) return found;
      }
    }
    return null;
  }

  void _updateNodeStatusV4(String path, EncryptionStatus status) {
    final node = _findNodeByPath(_globalTasks, path);
    if (node != null) {
      node.status = status;
      persistGlobalTasks();
      notifyListeners();
    }
  }

  void _checkTaskCompletionV4(String taskId) {
    final rootNode = _globalTasks.firstWhere((n) => n.taskId == taskId, orElse: () => EncryptionNode(name: '', type: EncryptionNodeType.file, absolutePath: ''));
    if (rootNode.taskId == null) return; // not found

    bool allCompleted = _checkAllFilesCompleted(rootNode);
    if (allCompleted) {
      // Check file existence
      bool allExist = _checkAllFilesExist(rootNode);
      if (allExist) {
        // move to history
        _globalTasks.remove(rootNode);
        // Note: history tracking for V4 will be added later
      } else {
        // Mark missing as error
        _markMissingFilesAsError(rootNode);
      }
      persistGlobalTasks();
      notifyListeners();
    }
  }

  bool _checkAllFilesCompleted(EncryptionNode node) {
    if (node.type == EncryptionNodeType.file) {
      return node.status == EncryptionStatus.completed;
    }
    if (node.children != null) {
      for (final child in node.children!) {
        if (!_checkAllFilesCompleted(child)) return false;
      }
    }
    return true;
  }

  bool _checkAllFilesExist(EncryptionNode node) {
    if (node.type == EncryptionNodeType.file) {
      return File(node.absolutePath).existsSync();
    }
    if (node.children != null) {
      for (final child in node.children!) {
        if (!_checkAllFilesExist(child)) return false;
      }
    }
    return true;
  }

  void _markMissingFilesAsError(EncryptionNode node) {
    if (node.type == EncryptionNodeType.file) {
      if (!File(node.absolutePath).existsSync()) {
        node.status = EncryptionStatus.error;
      }
    } else if (node.children != null) {
      for (final child in node.children!) {
        _markMissingFilesAsError(child);
      }
    }
  }

  void _recordLocalIndex(String vaultPath, String remotePath, String hash, int size) {
    LocalIndexService().updateFileIndex(
      vaultDirectoryPath: vaultPath,
      remotePath: remotePath,
      hash: hash,
      size: size,
    );
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
        await Future.microtask(() {});
        continue;
      }

      final localPath = task.taskArgs?['path'] as String? ?? _findLocalPathOf(root, task.id);
      final remotePath = task.taskArgs?['remotePath'] as String? ?? _findRemotePathOf(root, task.id);

      if (localPath == null || remotePath == null) {
        task.status = 'failed';
        task.error = 'Path not found';
        await Future.microtask(() {});
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
  List<EncryptionTask> get tasks => _tasks;
  final List<EncryptionTask> _historyTasks = [];
  List<EncryptionTask> get historyTasks => _historyTasks;
  final Map<String, Isolate> _isolates = {};
  bool _isSaving = false;

  // 新增：V4 重构全局任务列表
  final List<EncryptionNode> _globalTasks = [];
  List<EncryptionNode> get globalTasks => List.unmodifiable(_globalTasks);

  void pauseNodeV4(EncryptionNode node) {
    _setNodePausedState(node, true);
    _killIsolatesForNodeV4(node);
    persistGlobalTasks();
    notifyListeners();
  }

  void resumeNodeV4(EncryptionNode node) {
    _setNodePausedState(node, false);
    persistGlobalTasks();
    notifyListeners();
    pumpQueueV4();
  }

  void _setNodePausedState(EncryptionNode node, bool paused) {
    node.isPaused = paused;
    if (node.type == EncryptionNodeType.file) {
      if (paused) {
        if (node.status == EncryptionStatus.encrypting || node.status == EncryptionStatus.pendingWaiting) {
          node.status = EncryptionStatus.pendingPaused;
        }
      } else {
        if (node.status == EncryptionStatus.pendingPaused) {
          node.status = EncryptionStatus.pendingWaiting;
        }
      }
    } else if (node.children != null) {
      for (final child in node.children!) {
        _setNodePausedState(child, paused);
      }
    }
  }

  void _killIsolatesForNodeV4(EncryptionNode node) {
    if (node.type == EncryptionNodeType.file) {
      final taskId = node.absolutePath;
      if (_isolates.containsKey(taskId)) {
        _isolates[taskId]?.kill(priority: Isolate.immediate);
        _isolates.remove(taskId);
        _activeWorkers--;
      }
    } else if (node.children != null) {
      for (final child in node.children!) {
        _killIsolatesForNodeV4(child);
      }
    }
  }

  void deleteNodeV4(EncryptionNode node) {
    _killIsolatesForNodeV4(node);
    // Find parent and remove it
    bool removed = _removeNodeFromGlobalTasks(node);
    if (removed) {
      persistGlobalTasks();
      notifyListeners();
    }
  }

  bool _removeNodeFromGlobalTasks(EncryptionNode target) {
    for (int i = 0; i < _globalTasks.length; i++) {
      if (_globalTasks[i].absolutePath == target.absolutePath) {
        _globalTasks.removeAt(i);
        return true;
      }
      if (_globalTasks[i].children != null) {
        if (_removeChildNodeV4(_globalTasks[i].children!, target)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _removeChildNodeV4(List<EncryptionNode> children, EncryptionNode target) {
    for (int i = 0; i < children.length; i++) {
      if (children[i].absolutePath == target.absolutePath) {
        children.removeAt(i);
        return true;
      }
      if (children[i].children != null) {
        if (_removeChildNodeV4(children[i].children!, target)) {
          return true;
        }
      }
    }
    return false;
  }

  void markNodeAsFixedV4(EncryptionNode node) {
    _markNodeAsFixedRecursive(node);
    persistGlobalTasks();
    notifyListeners();
    pumpQueueV4();
  }

  void _markNodeAsFixedRecursive(EncryptionNode node) {
    if (node.type == EncryptionNodeType.file) {
      if (node.status == EncryptionStatus.error) {
        node.status = EncryptionStatus.pendingWaiting;
      }
    } else if (node.children != null) {
      for (final child in node.children!) {
        _markNodeAsFixedRecursive(child);
      }
    }
  }

  EncryptionNode? _findNextPendingV4(List<EncryptionNode> nodes) {
    for (final node in nodes) {
      if (node.isPaused) continue;
      
      if (node.type == EncryptionNodeType.folder) {
        if (node.children != null) {
          final found = _findNextPendingV4(node.children!);
          if (found != null) return found;
        }
      } else {
        if (node.status == EncryptionStatus.pendingWaiting) {
          return node;
        }
      }
    }
    return null;
  }

  void pumpQueueV4() async {
    await _loadSettings();
    while (_activeWorkers < _maxWorkers) {
      final fileNode = _findNextPendingV4(_globalTasks);
      if (fileNode == null) break;

      // Find root node to get taskArgs
      final rootNode = _globalTasks.firstWhere((n) => _containsNode(n, fileNode));
      final rootArgs = rootNode.taskArgs;
      if (rootArgs == null || rootArgs['masterKey'] == null) {
        fileNode.status = EncryptionStatus.error;
        await Future.microtask(() {});
        continue;
      }

      // Remote path was stored in the fileNode's taskArgs
      final remotePath = fileNode.taskArgs?['remotePath'] as String?;
      if (remotePath == null) {
        fileNode.status = EncryptionStatus.error;
        await Future.microtask(() {});
        continue;
      }

      fileNode.status = EncryptionStatus.encrypting;
      _activeWorkers++;
      notifyListeners();

      final args = {
        'sendPort': _globalReceivePort.sendPort,
        'localPath': fileNode.absolutePath,
        'remotePath': remotePath,
        'absolutePath': fileNode.absolutePath,
        'vaultDirectoryPath': rootArgs['vaultDirectoryPath'],
        'masterKey': rootArgs['masterKey'],
        'encryptFilename': rootArgs['encryptFilename'],
        'taskId': rootNode.taskId!,
      };

      Isolate.spawn(doEncryptFileIsolate, args).then((isolate) {
        registerIsolate(fileNode.absolutePath, isolate);
      });
    }
  }

  bool _containsNode(EncryptionNode root, EncryptionNode target) {
    if (root.absolutePath == target.absolutePath) return true;
    if (root.children != null) {
      for (final child in root.children!) {
        if (_containsNode(child, target)) return true;
      }
    }
    return false;
  }
  Future<void> createTasksFromPaths({
    required List<String> paths,
    required String vaultDirectoryPath,
    required Uint8List masterKey,
    required bool encryptFilename,
    required String currentRemotePath,
  }) async {
    for (final path in paths) {
      final isDir = await FileSystemEntity.isDirectory(path);
      final taskId = DateTime.now().millisecondsSinceEpoch.toString() + '_' + p.basename(path);
      final remotePath = p.join(currentRemotePath, p.basename(path)).replaceAll(r'\', '/');
      final taskArgs = {
        'vaultDirectoryPath': vaultDirectoryPath,
        'masterKey': masterKey,
        'encryptFilename': encryptFilename,
        'remotePath': remotePath,
      };
      
      if (isDir) {
        final rootNode = _buildTreeRecursive(Directory(path), taskId, remotePath);
        // Ensure rootNode gets taskArgs
        final finalRoot = EncryptionNode(
          taskId: rootNode.taskId,
          name: rootNode.name,
          type: rootNode.type,
          isPaused: rootNode.isPaused,
          children: rootNode.children,
          size: rootNode.size,
          rawSize: rootNode.rawSize,
          status: rootNode.status,
          absolutePath: rootNode.absolutePath,
          taskArgs: taskArgs,
        );
        _globalTasks.add(finalRoot);
      } else {
        final file = File(path);
        if (file.existsSync()) {
          final size = file.lengthSync();
          final node = EncryptionNode(
            taskId: taskId,
            name: p.basename(path),
            type: EncryptionNodeType.file,
            isPaused: false,
            status: EncryptionStatus.pendingWaiting,
            rawSize: size,
            size: EncryptionNode.formatSize(size),
            absolutePath: path,
            taskArgs: taskArgs,
          );
          _globalTasks.add(node);
        }
      }
    }
    
    await persistGlobalTasks();
    if (isForeground) {
      notifyListeners();
    }
    _startRefreshLoop();
    pumpQueueV4();
  }

  EncryptionNode _buildTreeRecursive(Directory dir, String rootTaskId, String currentRemotePath) {
    final children = <EncryptionNode>[];
    try {
      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        final childName = p.basename(entity.path);
        final childRemotePath = p.join(currentRemotePath, childName).replaceAll(r'\', '/');
        
        if (entity is Directory) {
          children.add(_buildTreeRecursive(entity, rootTaskId, childRemotePath));
        } else if (entity is File) {
          int size = 0;
          try {
            size = entity.lengthSync();
          } catch (_) {}
          children.add(EncryptionNode(
            name: childName,
            type: EncryptionNodeType.file,
            isPaused: false,
            status: EncryptionStatus.pendingWaiting,
            rawSize: size,
            size: EncryptionNode.formatSize(size),
            absolutePath: entity.path,
            taskArgs: {'remotePath': childRemotePath},
          ));
        }
      }
    } catch (_) {}

    return EncryptionNode(
      taskId: rootTaskId,
      name: p.basename(dir.path),
      type: EncryptionNodeType.folder,
      isPaused: false,
      children: children,
      absolutePath: dir.path,
    );
  }

  Future<void> persistGlobalTasks() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'encryption_tasks_v4.json'));
      final jsonList = _globalTasks.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Failed to persist tasks: $e');
    }
  }

  List<EncryptionTask> get historyTasks => List.unmodifiable(_historyTasks);
  final List<EncryptionNode> _historyTasksV4 = [];
  List<EncryptionNode> get historyTasksV4 => List.unmodifiable(_historyTasksV4);

  Map<String, int> getV4Stats() {
    int completed = 0;
    int encrypting = 0;
    int pending = 0;
    int pausedError = 0;

    void traverse(EncryptionNode node) {
      if (node.type == EncryptionNodeType.file) {
        final size = node.rawSize ?? 0;
        if (node.isPaused) {
          pausedError += size;
        } else {
          switch (node.status) {
            case EncryptionStatus.completed:
              completed += size;
              break;
            case EncryptionStatus.encrypting:
              encrypting += size;
              break;
            case EncryptionStatus.pendingWaiting:
              pending += size;
              break;
            case EncryptionStatus.pendingPaused:
            case EncryptionStatus.error:
            case null:
              pausedError += size;
              break;
          }
        }
      } else {
        if (node.children != null) {
          for (final child in node.children!) {
            // Inherit paused state logically for stats if needed, 
            // but V4 specifies parent pause covers child, so we should check node.isPaused
            if (node.isPaused) {
               _addPausedSize(child, (s) => pausedError += s);
            } else {
               traverse(child);
            }
          }
        }
      }
    }

    for (final task in _globalTasks) {
      traverse(task);
    }

    return {
      'completed': completed,
      'encrypting': encrypting,
      'pending': pending,
      'pausedError': pausedError,
      'total': completed + encrypting + pending + pausedError,
    };
  }

  void _addPausedSize(EncryptionNode node, Function(int) add) {
    if (node.type == EncryptionNodeType.file) {
      add(node.rawSize ?? 0);
    } else if (node.children != null) {
      for (final child in node.children!) {
        _addPausedSize(child, add);
      }
    }
  }

  Future<void> _loadQueue() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'encryption_tasks_v4.json'));
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _globalTasks.clear();
        for (final item in jsonList) {
          final node = EncryptionNode.fromJson(item as Map<String, dynamic>);
          _restoreNodeState(node);
          _globalTasks.add(node);
        }
        notifyListeners();
        pumpQueueV4();
      }
    } catch (e) {
      debugPrint('Failed to load queue: $e');
    }
  }

  void _restoreNodeState(EncryptionNode node) {
    if (node.type == EncryptionNodeType.file) {
      if (node.status == EncryptionStatus.encrypting) {
        node.status = EncryptionStatus.pendingWaiting;
      }
      if (!File(node.absolutePath).existsSync()) {
        node.status = EncryptionStatus.error;
      }
    } else if (node.children != null) {
      for (final child in node.children!) {
        _restoreNodeState(child);
      }
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
    debugPrint('Mock _saveQueue: Queue saving skipped.');
  }

  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveQueue();
    });
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _historyTasks.map((t) => t.toJson()).toList();
      await prefs.setString('encryption_history_v4.json', jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Failed to save history: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('encryption_history_v4.json');
      if (jsonStr != null) {
        final jsonList = jsonDecode(jsonStr) as List<dynamic>;
        _historyTasks.clear();
        for (final item in jsonList) {
          _historyTasks.add(EncryptionTask.fromJson(item as Map<String, dynamic>));
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load history: $e');
    }
  }

  Future<void> deleteHistoryTask(String taskId) async {
    _historyTasks.removeWhere((t) => t.id == taskId);
    await _saveHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _historyTasks.clear();
    await _saveHistory();
    notifyListeners();
  }

  void addTask(EncryptionTask task) {
    _tasks.add(task);
    _saveQueue();
    if (isForeground) {
      notifyListeners();
    }
    _startRefreshLoop();
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
      final Map<String, dynamic> args = {};
      if (map.containsKey('path')) args['path'] = map['path'];
      if (map.containsKey('remotePath')) args['remotePath'] = map['remotePath'];
      
      return EncryptionTask(
        id: map['id'] as String,
        name: map['name'] as String,
        isDirectory: map['isDirectory'] as bool,
        totalBytes: map['totalBytes'] as int,
        taskArgs: args.isNotEmpty ? args : null,
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
      // Refresh loop will handle saving and notify
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
      
      if (status == 'completed' || status == 'failed') {
        final root = _findRootOf(task.id);
        if (root != null) {
          _checkRootCompletion(root);
        }
      }
    }
  }

  void _checkRootCompletion(EncryptionTask root) {
    if (root.status == 'completed') {
      if (_tasks.contains(root)) {
        _tasks.remove(root);
        root.completedAt = DateTime.now().millisecondsSinceEpoch;
        _historyTasks.add(root);
        _saveQueue();
        _saveHistory();
        StatsService().recalculate();
        notifyListeners();
      }
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
