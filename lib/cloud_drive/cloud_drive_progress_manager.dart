import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sync_task.dart';
import '../services/sync_storage_service.dart';
import '../services/sync_engine.dart' as old_sync_engine;
import 'webdav_storage.dart';
import 'webdav_new/webdav_client.dart';
import 'webdav_new/webdav_service.dart';
import 'webdav_new/sync_engine.dart' as new_sync_engine;

class CloudDriveProgressManager extends ChangeNotifier with WidgetsBindingObserver {
  bool _isInitialized = false;
  Future<void>? _initFuture;

  CloudDriveProgressManager._() {
    _initFuture = _init();
  }
  static final instance = CloudDriveProgressManager._();

  final SyncStorageService _storageService = SyncStorageService();
  final old_sync_engine.SyncEngine syncEngine = old_sync_engine.SyncEngine();

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

    for (var task in _tasks) {
      if (task.status == SyncStatus.syncing || task.status == SyncStatus.pending) {
        resumeTask(task.id);
      }
    }

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
    for (var t in _tasks) {
      if (t.status == SyncStatus.paused || t.status == SyncStatus.failed || t.status == SyncStatus.pending) {
        resumeTask(t.id);
      }
    }
    notifyListeners();
    _startTimerIfNeeded();
  }

  void pauseTask(String id) {
    syncEngine.pauseTask(id);
    _setTaskStatus(id, SyncStatus.paused);
  }

  Future<void> resumeTask(String id) async {
    await _ensureInitialized();
    final taskIndex = _tasks.indexWhere((t) => t.id == id);
    if (taskIndex < 0) return;

    final task = _tasks[taskIndex];
    if (task.status == SyncStatus.syncing) return;

    _setTaskStatus(id, SyncStatus.pending);
    _startTimerIfNeeded();

    try {
      final repo = WebDavConfigRepository();
      final configs = await repo.listConfigs();
      final config = configs.firstWhere(
        (c) => c.id == task.cloudWebDavId,
        orElse: () => throw Exception('WebDAV config not found for id: ${task.cloudWebDavId}')
      );
      final password = await repo.readPassword(config.id);

      final client = WebDavClient(
        baseUrl: config.url,
        username: config.username,
        password: password ?? '',
      );
      final service = WebDavService(client);
      final newEngine = new_sync_engine.SyncEngine(
        service: service,
        localDirPath: task.localVaultPath,
      );

      await newEngine.sync(task.cloudFolderPath, task: task);
    } catch (e) {
      task.errorMessage = 'Failed to resume: $e';
      _setTaskStatus(id, SyncStatus.failed);
    }
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
