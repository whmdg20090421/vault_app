import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sync_task.dart';
import '../services/sync_storage_service.dart';
import '../services/sync_engine.dart';

class CloudDriveProgressManager extends ChangeNotifier with WidgetsBindingObserver {
  bool _isInitialized = false;
  Future<void>? _initFuture;

  CloudDriveProgressManager._() {
    _initFuture = _init();
  }
  static final instance = CloudDriveProgressManager._();

  final SyncStorageService _storageService = SyncStorageService();
  final SyncEngine syncEngine = SyncEngine();

  List<SyncTask> _tasks = [];
  List<SyncTask> get tasks => _tasks;

  bool get hasActiveTasks => _tasks.any((t) => t.status == SyncStatus.syncing);

  // Pending updates queue for the independent listening thread (Timer)
  final Map<String, SyncTask> _pendingUpdates = {};
  
  Timer? _refreshTimer;
  int _tickCount = 0;
  bool _isForeground = true;

  Future<void> _init() async {
    WidgetsBinding.instance.addObserver(this);
    _tasks = await _storageService.loadTasks();
    _isInitialized = true;
    notifyListeners();

    syncEngine.taskUpdates.listen((updatedTask) {
      _pendingUpdates[updatedTask.id] = updatedTask;
      _startTimerIfNeeded();
    });
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized && _initFuture != null) {
      await _initFuture;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground && _refreshTimer != null) {
      _processUpdates(forceUI: true);
    }
  }

  void _startTimerIfNeeded() {
    if (_refreshTimer != null && _refreshTimer!.isActive) return;
    _tickCount = 0;
    // SubTask 3.1: 独立监听线程进行全局进度计算与更新
    // Use a periodic timer running every 500ms
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), _onTick);
  }

  void _onTick(Timer timer) {
    _tickCount++;
    
    bool hasPending = _pendingUpdates.isNotEmpty;
    bool hasActive = _tasks.any((t) => t.status == SyncStatus.syncing) || 
                     _pendingUpdates.values.any((t) => t.status == SyncStatus.syncing);

    // SubTask 3.4: 无活跃任务时触发最终全量刷新并永久缓存，停止定时器
    if (!hasActive && !hasPending) {
      _finalRefresh();
      return;
    }

    if (_isForeground) {
      // SubTask 3.2: 前台高频刷新(0.5~1秒，更新UI和内存)
      // Process updates every tick (0.5s)
      _processUpdates(forceUI: true);
      
      // Persist active tasks occasionally even in foreground (every 5s)
      if (_tickCount % 10 == 0) {
        _persistActiveTasks();
      }
    } else {
      // SubTask 3.3: 后台静默刷新(5~10秒，仅更新内存与持久化不重绘UI)
      // Process updates every 10 ticks (5s)
      if (_tickCount % 10 == 0) {
        _processUpdates(forceUI: false);
        _persistActiveTasks(); // persist in background
      }
    }
  }

  Future<void> _processUpdates({required bool forceUI}) async {
    if (_pendingUpdates.isEmpty && !forceUI) return;

    List<SyncTask> completedTasks = [];

    // Apply pending updates to memory
    if (_pendingUpdates.isNotEmpty) {
      for (var task in _pendingUpdates.values) {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index >= 0) {
          _tasks[index] = task;
        } else {
          _tasks.add(task);
        }

        if (task.status == SyncStatus.completed) {
          completedTasks.add(task);
        }
      }
      _pendingUpdates.clear();
    }

    // Process completed tasks
    if (completedTasks.isNotEmpty) {
      for (var task in completedTasks) {
        _tasks.removeWhere((t) => t.id == task.id);
      }
      
      final historyTasks = await _storageService.loadHistory();
      historyTasks.addAll(completedTasks);
      await _storageService.saveHistory(historyTasks);
      
      // Update active tasks storage since we removed completed tasks
      await _persistActiveTasks();
    }

    // Update UI if required and in foreground
    if (forceUI && _isForeground) {
      notifyListeners();
    }
  }

  Future<void> _persistActiveTasks() async {
    await _storageService.saveTasks(_tasks);
  }

  Future<void> _finalRefresh() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    
    // Final full refresh
    await _processUpdates(forceUI: true);
    
    // Permanent cache
    await _persistActiveTasks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> addTask(SyncTask task) async {
    await _ensureInitialized();
    _tasks.add(task);
    await _storageService.saveTasks(_tasks);
    notifyListeners();
    _startTimerIfNeeded();
  }

  void updateTask(SyncTask task) {
    _pendingUpdates[task.id] = task;
    _startTimerIfNeeded();
  }

  void pauseUpload(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.isUploadPaused = true;
    updateTask(task);
  }

  void resumeUpload(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.isUploadPaused = false;
    updateTask(task);
  }

  void pauseDownload(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.isDownloadPaused = true;
    updateTask(task);
  }

  void resumeDownload(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.isDownloadPaused = false;
    updateTask(task);
  }

  void deleteTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.status = SyncStatus.failed;
    task.errorMessage = '用户已取消/删除该任务';
    _tasks.removeWhere((t) => t.id == taskId);
    _storageService.deleteTask(taskId);
    notifyListeners();
  }

  void pauseAll() async {
    await _ensureInitialized();
    for (var t in _tasks) {
      if (t.status == SyncStatus.syncing || t.status == SyncStatus.pending) {
        syncEngine.pauseTask(t.id);
        t.status = SyncStatus.paused;
        _storageService.saveTask(t);
      }
    }
    notifyListeners();
  }

  void startAll() async {
    await _ensureInitialized();
    // To actually start tasks, credentials are required. 
    // Here we just mark them as pending for the UI.
    for (var t in _tasks) {
      if (t.status == SyncStatus.paused || t.status == SyncStatus.failed) {
        t.status = SyncStatus.pending;
        _storageService.saveTask(t);
      }
    }
    notifyListeners();
    _startTimerIfNeeded();
  }

  void pauseTask(String id) {
    syncEngine.pauseTask(id);
    _setTaskStatus(id, SyncStatus.paused);
  }

  void resumeTask(String id) {
    // Requires credentials to start via SyncEngine. Marking as pending for now.
    _setTaskStatus(id, SyncStatus.pending);
    _startTimerIfNeeded();
  }
  
  void cancelTask(String id) {
    syncEngine.cancelTask(id);
    _setTaskStatus(id, SyncStatus.failed);
  }

  void _setTaskStatus(String id, SyncStatus status) async {
    await _ensureInitialized();
    for (var t in _tasks) {
      if (t.id == id) {
        t.status = status;
        _storageService.saveTask(t);
      }
    }
    notifyListeners();
  }

  Future<List<SyncTask>> getHistory() async {
    return await _storageService.loadHistory();
  }
}
