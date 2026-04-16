import 'package:flutter/material.dart';

enum SyncTaskStatus { pending, running, paused, failed, completed }

class SyncTask {
  SyncTask({
    required this.id,
    required this.name,
    required this.isFolder,
    this.totalSize = 0,
    this.transferredSize = 0,
    this.status = SyncTaskStatus.pending,
    this.children = const [],
  });

  final String id;
  final String name;
  final bool isFolder;
  final int totalSize;
  int transferredSize;
  SyncTaskStatus status;
  List<SyncTask> children;

  double get progress {
    if (totalSize == 0) return 0;
    return transferredSize / totalSize;
  }
}

class CloudDriveProgressManager extends ChangeNotifier {
  CloudDriveProgressManager._() {
    // For demo purposes, add some tasks initially
    addDemoTasks();
  }
  static final instance = CloudDriveProgressManager._();

  final List<SyncTask> _tasks = [];
  List<SyncTask> get tasks => _tasks;

  bool get hasActiveTasks => _tasks.any((t) => t.status == SyncTaskStatus.running);

  void addTask(SyncTask task) {
    _tasks.add(task);
    notifyListeners();
  }

  void pauseAll() {
    for (var t in _tasks) {
      if (t.status == SyncTaskStatus.running || t.status == SyncTaskStatus.pending) {
        t.status = SyncTaskStatus.paused;
      }
    }
    notifyListeners();
  }

  void startAll() {
    for (var t in _tasks) {
      if (t.status == SyncTaskStatus.paused || t.status == SyncTaskStatus.failed) {
        t.status = SyncTaskStatus.pending; // or running
      }
    }
    notifyListeners();
  }

  void startTask(String id) {
    _setTaskStatus(id, SyncTaskStatus.running);
  }

  void pauseTask(String id) {
    _setTaskStatus(id, SyncTaskStatus.paused);
  }

  void resumeTask(String id) {
    _setTaskStatus(id, SyncTaskStatus.running);
  }

  void _setTaskStatus(String id, SyncTaskStatus status) {
    for (var t in _tasks) {
      if (t.id == id) {
        t.status = status;
      }
    }
    notifyListeners();
  }
  
  // For demo
  void addDemoTasks() {
    if (_tasks.isNotEmpty) return;
    _tasks.addAll([
      SyncTask(
        id: '1',
        name: '照片备份',
        isFolder: true,
        status: SyncTaskStatus.running,
        children: [
          SyncTask(id: '1-1', name: 'IMG_001.jpg', isFolder: false, totalSize: 100, transferredSize: 50, status: SyncTaskStatus.running),
          SyncTask(id: '1-2', name: 'IMG_002.jpg', isFolder: false, totalSize: 100, transferredSize: 0, status: SyncTaskStatus.pending),
          SyncTask(id: '1-3', name: 'IMG_003.jpg', isFolder: false, totalSize: 100, transferredSize: 100, status: SyncTaskStatus.completed),
        ]
      ),
      SyncTask(
        id: '2',
        name: '工作文档.pdf',
        isFolder: false,
        totalSize: 200,
        transferredSize: 50,
        status: SyncTaskStatus.paused,
      ),
      SyncTask(
        id: '3',
        name: '视频素材.mp4',
        isFolder: false,
        totalSize: 1000,
        transferredSize: 100,
        status: SyncTaskStatus.failed,
      ),
    ]);
    notifyListeners();
  }
}
