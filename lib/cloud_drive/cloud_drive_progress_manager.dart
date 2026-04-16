import 'package:flutter/material.dart';
import '../models/sync_task.dart';
import '../services/sync_storage_service.dart';
import '../services/sync_engine.dart';

class CloudDriveProgressManager extends ChangeNotifier {
  CloudDriveProgressManager._() {
    _init();
  }
  static final instance = CloudDriveProgressManager._();

  final SyncStorageService _storageService = SyncStorageService();
  final SyncEngine syncEngine = SyncEngine();

  List<SyncTask> _tasks = [];
  List<SyncTask> get tasks => _tasks;

  bool get hasActiveTasks => _tasks.any((t) => t.status == SyncStatus.syncing);

  Future<void> _init() async {
    _tasks = await _storageService.loadTasks();
    notifyListeners();

    syncEngine.taskUpdates.listen((updatedTask) {
      final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
      if (index >= 0) {
        _tasks[index] = updatedTask;
      } else {
        _tasks.add(updatedTask);
      }
      notifyListeners();
    });
  }

  Future<void> addTask(SyncTask task) async {
    _tasks.add(task);
    await _storageService.saveTask(task);
    notifyListeners();
  }

  void pauseAll() {
    for (var t in _tasks) {
      if (t.status == SyncStatus.syncing || t.status == SyncStatus.pending) {
        syncEngine.pauseTask(t.id);
        t.status = SyncStatus.paused;
        _storageService.saveTask(t);
      }
    }
    notifyListeners();
  }

  void startAll() {
    // To actually start tasks, credentials are required. 
    // Here we just mark them as pending for the UI.
    for (var t in _tasks) {
      if (t.status == SyncStatus.paused || t.status == SyncStatus.failed) {
        t.status = SyncStatus.pending;
        _storageService.saveTask(t);
      }
    }
    notifyListeners();
  }

  void pauseTask(String id) {
    syncEngine.pauseTask(id);
    _setTaskStatus(id, SyncStatus.paused);
  }

  void resumeTask(String id) {
    // Requires credentials to start via SyncEngine. Marking as pending for now.
    _setTaskStatus(id, SyncStatus.pending);
  }
  
  void cancelTask(String id) {
    syncEngine.cancelTask(id);
    _setTaskStatus(id, SyncStatus.failed);
  }

  void _setTaskStatus(String id, SyncStatus status) {
    for (var t in _tasks) {
      if (t.id == id) {
        t.status = status;
        _storageService.saveTask(t);
      }
    }
    notifyListeners();
  }
}
