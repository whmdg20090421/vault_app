import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models/sync_task.dart';
import 'sync_storage_service.dart';

class _SyncIsolateParams {
  final SyncTask task;
  final String url;
  final String user;
  final String password;
  final String localVfsRoot;
  final SendPort sendPort;

  _SyncIsolateParams({
    required this.task,
    required this.url,
    required this.user,
    required this.password,
    required this.localVfsRoot,
    required this.sendPort,
  });
}

class SyncEngine {
  final Map<String, Isolate> _isolates = {};
  final Map<String, SendPort> _isolateSendPorts = {};
  final SyncStorageService _storageService = SyncStorageService();

  final _taskUpdates = StreamController<SyncTask>.broadcast();
  Stream<SyncTask> get taskUpdates => _taskUpdates.stream;

  Future<void> startTask(SyncTask task, String url, String user, String password, String localVfsRoot) async {
    if (_isolates.containsKey(task.id)) return;

    task.status = SyncStatus.syncing;
    task.startedAt = DateTime.now();
    await _storageService.saveTask(task);
    _taskUpdates.add(task);

    final receivePort = ReceivePort();
    
    final params = _SyncIsolateParams(
      task: task,
      url: url,
      user: user,
      password: password,
      localVfsRoot: localVfsRoot,
      sendPort: receivePort.sendPort,
    );

    final isolate = await Isolate.spawn(_syncIsolateEntry, params);
    _isolates[task.id] = isolate;

    receivePort.listen((message) async {
      if (message is SendPort) {
        _isolateSendPorts[task.id] = message;
      } else if (message is SyncTask) {
        await _storageService.saveTask(message);
        _taskUpdates.add(message);

        if (message.status == SyncStatus.completed || 
            message.status == SyncStatus.failed || 
            message.status == SyncStatus.paused) {
          _cleanupIsolate(task.id);
          receivePort.close();
        }
      }
    });
  }

  void pauseTask(String taskId) {
    _isolateSendPorts[taskId]?.send('pause');
  }

  void cancelTask(String taskId) {
    _isolateSendPorts[taskId]?.send('cancel');
  }

  void _cleanupIsolate(String taskId) {
    _isolates[taskId]?.kill(priority: Isolate.immediate);
    _isolates.remove(taskId);
    _isolateSendPorts.remove(taskId);
  }
}

void _syncIsolateEntry(_SyncIsolateParams params) async {
  final receivePort = ReceivePort();
  params.sendPort.send(receivePort.sendPort);

  bool isPaused = false;
  bool isCancelled = false;

  receivePort.listen((message) {
    if (message == 'pause') {
      isPaused = true;
    } else if (message == 'cancel') {
      isCancelled = true;
    }
  });

  SyncTask task = params.task;
  int consecutiveFileFailures = 0;

  final httpClient = HttpClient();

  Future<HttpClientRequest> createRequest(String method, String path) async {
    String fullUrl = params.url;
    if (fullUrl.endsWith('/')) {
      fullUrl = fullUrl.substring(0, fullUrl.length - 1);
    }
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    final segments = path.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/');
    final uri = Uri.parse(fullUrl + segments);
    final request = await httpClient.openUrl(method, uri);
    final auth = 'Basic ${base64Encode(utf8.encode('${params.user}:${params.password}'))}';
    request.headers.add('Authorization', auth);
    return request;
  }

  for (int i = 0; i < task.items.length; i++) {
    if (isPaused || isCancelled) break;

    SyncFileItem item = task.items[i];
    if (item.status == SyncStatus.completed) continue;

    item.status = SyncStatus.syncing;
    task.items[i] = item;
    params.sendPort.send(task);

    bool fileSuccess = false;

    while (item.retryCount < SyncFileItem.maxRetries) {
      if (isPaused || isCancelled) break;

      try {
        if (task.direction == SyncDirection.cloudToLocal) {
          // Download
          final req = await createRequest('GET', item.path);
          final resp = await req.close();
          if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');

          final localFile = File('${params.localVfsRoot}/${item.path}');
          await localFile.parent.create(recursive: true);

          final tempFile = File('${localFile.path}.sync_tmp');
          final sink = tempFile.openWrite();

          bool interrupted = false;
          await for (final chunk in resp) {
            if (isPaused || isCancelled) {
              interrupted = true;
              break;
            }
            sink.add(chunk);
          }
          await sink.flush();
          await sink.close();

          if (interrupted) {
            if (await tempFile.exists()) await tempFile.delete();
            item.retryCount = 0;
            item.status = SyncStatus.paused;
            break;
          } else {
            if (await localFile.exists()) await localFile.delete();
            await tempFile.rename(localFile.path);
            fileSuccess = true;
            break;
          }
        } else {
          // Upload
          final localFile = File('${params.localVfsRoot}/${item.path}');
          if (!await localFile.exists()) throw Exception('Local file not found');

          final req = await createRequest('PUT', item.path);
          final fileSize = await localFile.length();
          req.contentLength = fileSize;

          final stream = localFile.openRead();
          bool interrupted = false;
          await for (final chunk in stream) {
            if (isPaused || isCancelled) {
              interrupted = true;
              break;
            }
            req.add(chunk);
          }

          if (interrupted) {
            req.abort();
            item.retryCount = 0;
            item.status = SyncStatus.paused;
            break;
          }

          final resp = await req.close();
          if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
          fileSuccess = true;
          break;
        }
      } catch (e) {
        item.retryCount++;
        item.errorMessage = e.toString();
        
        if (item.retryCount >= 3) {
          break; // Let the outer logic handle pausing and consecutive failures
        }
        
        // Wait before retry
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (isPaused || isCancelled) {
      if (item.status == SyncStatus.syncing) {
        item.status = SyncStatus.paused;
      }
    } else if (fileSuccess) {
      item.status = SyncStatus.completed;
      item.retryCount = 0;
      item.errorMessage = null;
      consecutiveFileFailures = 0;
    } else {
      // Failed to sync file after retries or skipped due to retry count
      if (item.retryCount >= 3) {
        item.status = SyncStatus.paused;
      } else {
        item.status = SyncStatus.failed;
      }
      consecutiveFileFailures++;
    }

    task.items[i] = item;
    params.sendPort.send(task);

    if (consecutiveFileFailures >= 10) {
      task.status = SyncStatus.paused;
      task.errorMessage = 'Too many consecutive file failures';
      params.sendPort.send(task);
      return;
    }
  }

  if (isCancelled) {
    task.status = SyncStatus.failed;
    task.errorMessage = 'Task cancelled';
  } else if (isPaused || task.status == SyncStatus.paused) {
    task.status = SyncStatus.paused;
  } else {
    bool allCompleted = task.items.every((i) => i.status == SyncStatus.completed);
    if (allCompleted) {
      task.status = SyncStatus.completed;
      task.completedAt = DateTime.now();
    } else {
      task.status = SyncStatus.failed;
      task.errorMessage = 'Some files failed to sync';
    }
  }

  params.sendPort.send(task);
}
