import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_task.dart';

class SyncStorageService {
  static const String _tasksKey = 'sync_tasks_key';
  static const String _historyKey = 'sync_history_key';

  /// 保存所有的同步任务
  Future<void> saveTasks(List<SyncTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_tasksKey, jsonString);
  }

  /// 获取所有保存的同步任务
  Future<List<SyncTask>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_tasksKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decodedList = jsonDecode(jsonString);
      return decodedList.map((e) => SyncTask.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error loading tasks: $e');
      return [];
    }
  }

  /// 保存所有的同步历史记录
  Future<void> saveHistory(List<SyncTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_historyKey, jsonString);
  }

  /// 获取所有保存的同步历史记录
  Future<List<SyncTask>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_historyKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decodedList = jsonDecode(jsonString);
      return decodedList.map((e) => SyncTask.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error loading history tasks: $e');
      return [];
    }
  }

  /// 保存单个同步任务（添加或更新）
  Future<void> saveTask(SyncTask task) async {
    final tasks = await loadTasks();
    final index = tasks.indexWhere((t) => t.id == task.id);

    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.add(task);
    }

    await saveTasks(tasks);
  }

  /// 删除单个同步任务
  Future<void> removeTask(String taskId) async {
    final tasks = await loadTasks();
    tasks.removeWhere((t) => t.id == taskId);
    await saveTasks(tasks);
  }

  /// 清空所有任务
  Future<void> clearAllTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tasksKey);
  }
}
