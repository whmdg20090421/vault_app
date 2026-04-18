import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/stats_service.dart';
import 'models/vault_config.dart';
import '../utils/format_utils.dart';
import '../vfs/virtual_file_system.dart';
import '../vfs/local_vfs.dart';
import '../vfs/encrypted_vfs.dart';
import 'services/encryption_task_manager.dart';
import 'dart:isolate';
import '../theme/app_theme.dart';
import 'encryption_page.dart';

Future<void> doImportFileIsolate(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final files = args['files'] as List<Map<String, String>>;
  final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
  final masterKey = args['masterKey'] as Uint8List;
  final encryptFilename = args['encryptFilename'] as bool;
  final taskId = args['taskId'] as String;

  final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
  final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: masterKey, encryptFilename: encryptFilename);
  await encryptedVfs.initEncryptedDomain('/');
  VirtualFileSystem vfs = encryptedVfs;

  try {
    for (final fileInfo in files) {
      final localPath = fileInfo['localPath']!;
      final remotePath = fileInfo['remotePath']!;
      final file = File(localPath);
      if (await file.exists()) {
        final size = await file.length();
        final childId = '$taskId/${p.basename(localPath)}';
        
        sendPort.send({
          'type': 'add_child',
          'taskId': taskId,
          'child': {
            'id': childId,
            'name': p.basename(localPath),
            'isDirectory': false,
            'totalBytes': size,
          }
        });

        int bytesProcessed = 0;
        int lastReportedBytes = 0;
        int lastReportTime = DateTime.now().millisecondsSinceEpoch;
        
        final stream = file.openRead().map((chunk) {
          bytesProcessed += chunk.length;
          final now = DateTime.now().millisecondsSinceEpoch;
          // Throttle progress updates to every 500ms or 1MB
          if (bytesProcessed - lastReportedBytes >= 1024 * 1024 || now - lastReportTime >= 500) {
            sendPort.send({'type': 'progress', 'taskId': childId, 'bytes': bytesProcessed});
            lastReportedBytes = bytesProcessed;
            lastReportTime = now;
          }
          return chunk;
        });
        await vfs.uploadStream(stream, size, remotePath);
        // Ensure final progress is reported
        sendPort.send({'type': 'progress', 'taskId': childId, 'bytes': bytesProcessed});
      }
    }
    sendPort.send({'type': 'done', 'taskId': taskId});
  } catch (e) {
    sendPort.send({'type': 'error', 'taskId': taskId, 'error': e.toString()});
  }
}

Future<void> doImportFolderIsolate(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final result = args['result'] as String;
  final currentPath = args['currentPath'] as String;
  final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
  final masterKey = args['masterKey'] as Uint8List;
  final encryptFilename = args['encryptFilename'] as bool;
  final taskId = args['taskId'] as String;
  final skipFileIds = args['skipFileIds'] as List<String>? ?? [];

  final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
  final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: masterKey, encryptFilename: encryptFilename);
  await encryptedVfs.initEncryptedDomain('/');
  VirtualFileSystem vfs = encryptedVfs;

  try {
    final dir = Directory(result);
    if (await dir.exists()) {
      final baseName = p.basename(result);
      final remoteDirPath = p.join(currentPath, baseName).replaceAll(r'\', '/');
      await vfs.mkdir(remoteDirPath);

      // Build task tree recursively
      Map<String, dynamic> buildTree(Directory d, String parentId) {
        int totalSize = 0;
        List<Map<String, dynamic>> children = [];
        for (final entity in d.listSync()) {
          final id = '$parentId/${p.basename(entity.path)}';
          if (entity is File) {
            final size = entity.lengthSync();
            totalSize += size;
            children.add({
              'id': id,
              'name': p.basename(entity.path),
              'isDirectory': false,
              'totalBytes': size,
              'path': entity.path,
            });
          } else if (entity is Directory) {
            final childMap = buildTree(entity, id);
            totalSize += childMap['totalBytes'] as int;
            children.add(childMap);
          }
        }
        return {
          'id': parentId,
          'name': p.basename(d.path),
          'isDirectory': true,
          'totalBytes': totalSize,
          'children': children,
        };
      }

      final treeMap = buildTree(dir, taskId);
      sendPort.send({'type': 'tree', 'tree': treeMap});

      // Skip processing here, let ETM (EncryptionTaskManager) pumpQueue handle the actual multi-threaded file import
      sendPort.send({'type': 'done', 'taskId': taskId});
    }
  } catch (e) {
    sendPort.send({'type': 'error', 'taskId': taskId, 'error': e.toString()});
  }
}

@visibleForTesting
Future<void> doExportFileIsolate(Map<String, dynamic> args) async {
  final nodePath = args['nodePath'] as String;
  final outFilePath = args['outFilePath'] as String;
  final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
  final masterKey = args['masterKey'] as Uint8List;
  final encryptFilename = args['encryptFilename'] as bool;

  final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
  final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: masterKey, encryptFilename: encryptFilename);
  await encryptedVfs.initEncryptedDomain('/');
  VirtualFileSystem vfs = encryptedVfs;

  final stream = await vfs.open(nodePath);
  final outFile = File(outFilePath);
  final sink = outFile.openWrite();
  try {
    await stream.pipe(sink);
  } finally {
    await sink.close();
  }
}

Future<void> _doShareFilesIsolate(Map<String, dynamic> args) async {
  final nodes = args['nodes'] as List<Map<String, String>>;
  final shareDirPath = args['shareDirPath'] as String;
  final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
  final masterKey = args['masterKey'] as Uint8List;
  final encryptFilename = args['encryptFilename'] as bool;

  final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
  final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: masterKey, encryptFilename: encryptFilename);
  await encryptedVfs.initEncryptedDomain('/');
  VirtualFileSystem vfs = encryptedVfs;

  for (final node in nodes) {
    final nodePath = node['path']!;
    final nodeName = node['name']!;
    final stream = await vfs.open(nodePath);
    final tempFile = File(p.join(shareDirPath, nodeName));
    final sink = tempFile.openWrite();
    try {
      await stream.pipe(sink);
    } finally {
      await sink.close();
    }
  }
}

class VaultExplorerPage extends StatefulWidget {
  final VaultConfig vaultConfig;
  final Uint8List masterKey;
  final String vaultDirectoryPath;

  const VaultExplorerPage({
    super.key,
    required this.vaultConfig,
    required this.masterKey,
    required this.vaultDirectoryPath,
  });

  @override
  State<VaultExplorerPage> createState() => _VaultExplorerPageState();
}

class _VaultExplorerPageState extends State<VaultExplorerPage> {
  bool _isMenuOpen = false;
  late VirtualFileSystem _vfs;
  String _currentPath = '/';
  List<VfsNode> _files = [];
  bool _isLoading = true;
  bool _isMultiSelectMode = false;
  final Set<VfsNode> _selectedNodes = {};
  final List<ReceivePort> _receivePorts = [];
  final List<Directory> _tempDirs = [];

  @override
  void dispose() {
    for (final port in _receivePorts) {
      try {
        port.close();
      } catch (_) {}
    }
    _receivePorts.clear();

    for (final dir in _tempDirs) {
      Future<void>(() async {
        try {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}
      });
    }
    _tempDirs.clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initVfs();
  }

  void _initVfs() async {
    final localVfs = LocalVfs(rootPath: widget.vaultDirectoryPath);
    final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: widget.masterKey, encryptFilename: widget.vaultConfig.encryptFilename);
    await encryptedVfs.initEncryptedDomain('/');
    _vfs = encryptedVfs;
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    if (mounted) setState(() => _isLoading = true);
    _isMultiSelectMode = false;
    _selectedNodes.clear();
    try {
      final files = await _vfs.list(_currentPath);
      // Sort: directories first, then files
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.compareTo(b.name);
      });
      if (mounted) {
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _importFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      if (mounted) {
        setState(() {
          _isMenuOpen = false;
          // _isLoading = false; 立即关闭加载动画，解阻塞 UI 线程
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 ${result.files.length} 个文件添加到后台加密任务')),
        );
      }
      try {
        int totalSize = 0;
        final filesToProcess = <Map<String, String>>[];
        for (final file in result.files) {
          if (file.path != null) {
            final localPath = file.path!;
            final remotePath = p.join(_currentPath, file.name).replaceAll(r'\', '/');
            filesToProcess.add({'localPath': localPath, 'remotePath': remotePath});
            totalSize += file.size;
          }
        }

        if (filesToProcess.isEmpty) return;

        final taskId = DateTime.now().millisecondsSinceEpoch.toString();
        final taskName = filesToProcess.length == 1 
            ? p.basename(filesToProcess.first['localPath']!)
            : '批量导入 ${filesToProcess.length} 个文件';

        final taskArgs = {
          'type': 'import_files',
          'files': filesToProcess,
          'vaultDirectoryPath': widget.vaultDirectoryPath,
          'encryptFilename': widget.vaultConfig.encryptFilename,
          'taskId': taskId,
        };

        final children = filesToProcess.map((f) {
          return EncryptionTask(
            id: '$taskId/${p.basename(f['localPath']!)}',
            name: p.basename(f['localPath']!),
            isDirectory: false,
            totalBytes: File(f['localPath']!).lengthSync(),
            status: 'pending',
            taskArgs: {
              'path': f['localPath'],
              'remotePath': f['remotePath'],
            }
          );
        }).toList();

        // Pass masterKey to taskArgs for worker pool
        taskArgs['masterKey'] = widget.masterKey;

        final task = EncryptionTask(
          id: taskId,
          name: taskName,
          isDirectory: true, // Treat batch as directory so children are pumped
          totalBytes: totalSize,
          status: 'pending',
          taskArgs: taskArgs,
          children: children,
        );

        EncryptionTaskManager().addTask(task);
        EncryptionTaskManager().pumpQueue();

        // We still need a listener for the progress, but now EncryptionTaskManager handles it via its global receive port!
        // We can just skip spawning the isolate here, ETM will do it!
        // BUT wait, doImportFileIsolate is used by ETM.
        // So we just skip all the receivePort logic here!
        /*
        final receivePort = ReceivePort();
        _receivePorts.add(receivePort);
        receivePort.listen((message) {
          if (message is Map<String, dynamic>) {
            final type = message['type'];
            final tid = message['taskId'] as String;
            if (type == 'progress') {
              final bytes = message['bytes'] as int;
              EncryptionTaskManager().updateTaskProgress(tid, bytes);
            } else if (type == 'add_child') {
              final childMap = message['child'] as Map<String, dynamic>;
              final child = EncryptionTask(
                id: childMap['id'] as String,
                name: childMap['name'] as String,
                isDirectory: childMap['isDirectory'] as bool,
                totalBytes: childMap['totalBytes'] as int,
              );
              EncryptionTaskManager().addChild(tid, child);
            } else if (type == 'done') {
              final t = EncryptionTaskManager().findTask(tid);
                if (t != null && t.children.isNotEmpty && t.id == tid) {
                  // Do not complete root task, let ETM handle it.
                } else {
                  EncryptionTaskManager().updateTaskStatus(tid, 'completed');
                }
              StatsService().recalculate();
              if (mounted) {
                _loadCurrentDirectory();
              }
              receivePort.close();
              _receivePorts.remove(receivePort);
            } else if (type == 'error') {
              final error = message['error'] as String;
              EncryptionTaskManager().updateTaskStatus(tid, 'failed', error: error);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('导入文件失败: $error')),
                );
              }
              receivePort.close();
              _receivePorts.remove(receivePort);
            }
          }
        });

        final args = {
          'sendPort': receivePort.sendPort,
          'files': filesToProcess,
          'vaultDirectoryPath': widget.vaultDirectoryPath,
          'masterKey': widget.masterKey,
          'encryptFilename': widget.vaultConfig.encryptFilename,
          'taskId': taskId,
        };

        Isolate.spawn(doImportFileIsolate, args).then((isolate) {
          EncryptionTaskManager().registerIsolate(taskId, isolate);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入文件失败: $e')),
          );
        }
      }
    } else {
      if (mounted) setState(() => _isMenuOpen = false);
    }
  }

  void _importFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      if (mounted) {
        setState(() {
          _isMenuOpen = false;
          // _isLoading = false; 立即关闭加载动画，解阻塞 UI 线程
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到后台加密任务，请在任务面板查看进度')),
        );
      }
      try {
        final dir = Directory(result);
        if (await dir.exists()) {
          int totalSize = 0;
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              totalSize += await entity.length();
            }
          }

          final baseName = p.basename(result);
          final taskId = DateTime.now().millisecondsSinceEpoch.toString();
          
          final taskArgs = {
            'type': 'import_folder',
            'result': result,
            'currentPath': _currentPath,
            'vaultDirectoryPath': widget.vaultDirectoryPath,
            'encryptFilename': widget.vaultConfig.encryptFilename,
            'taskId': taskId,
          };

          final task = EncryptionTask(
            id: taskId,
            name: baseName,
            totalBytes: totalSize,
            status: 'encrypting',
            taskArgs: taskArgs,
          );

          EncryptionTaskManager().addTask(task);

          final receivePort = ReceivePort();
          _receivePorts.add(receivePort);
          receivePort.listen((message) {
            if (message is Map<String, dynamic>) {
              final type = message['type'];
              final tid = message['taskId'] as String;
              if (type == 'progress') {
                final bytes = message['bytes'] as int;
                EncryptionTaskManager().updateTaskProgress(tid, bytes);
              } else if (type == 'tree') {
                final treeMap = message['tree'] as Map<String, dynamic>;
                EncryptionTaskManager().updateTaskTree(tid, treeMap);
              } else if (type == 'done') {
                final t = EncryptionTaskManager().findTask(tid);
                if (t != null && t.children.isNotEmpty && t.id == tid) {
                  // Do not complete root task, let ETM handle it.
                } else {
                  EncryptionTaskManager().updateTaskStatus(tid, 'completed');
                }
                StatsService().recalculate();
                if (mounted) {
                  _loadCurrentDirectory();
                }
                receivePort.close();
                _receivePorts.remove(receivePort);
              } else if (type == 'error') {
                final error = message['error'] as String;
                EncryptionTaskManager().updateTaskStatus(tid, 'failed', error: error);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('导入文件夹失败: $error')),
                  );
                }
                receivePort.close();
                _receivePorts.remove(receivePort);
              }
            }
          });

          final args = {
            'sendPort': receivePort.sendPort,
            'result': result,
            'currentPath': _currentPath,
            'vaultDirectoryPath': widget.vaultDirectoryPath,
            'masterKey': widget.masterKey,
            'encryptFilename': widget.vaultConfig.encryptFilename,
            'taskId': taskId,
          };

          Isolate.spawn(doImportFolderIsolate, args).then((isolate) {
            EncryptionTaskManager().registerIsolate(taskId, isolate);
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入文件夹失败: $e')),
          );
        }
      }
    } else {
      if (mounted) setState(() => _isMenuOpen = false);
    }
  }

  void _loadCurrentDirectory() {
    _loadFiles();
  }

  Future<void> _exportFile(VfsNode node) async {
    try {
      final selectedDir = await FilePicker.platform.getDirectoryPath();
      if (selectedDir == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('正在导出: ${node.name}...')),
        );
      }

      final outFile = File(p.join(selectedDir, node.name));
      await Isolate.spawn(doExportFileIsolate, {
        'nodePath': node.path,
        'outFilePath': outFile.path,
        'vaultDirectoryPath': widget.vaultDirectoryPath,
        'masterKey': widget.masterKey,
        'encryptFilename': widget.vaultConfig.encryptFilename,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出成功: ${outFile.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  void _newFolder() {
    setState(() => _isMenuOpen = false);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新建文件夹'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '文件夹名称'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  try {
                    final newPath = p.join(_currentPath, name).replaceAll(r'\', '/');
                    await _vfs.mkdir(newPath);
                    if (mounted) {
                      Navigator.of(context).pop();
                      _loadFiles();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('创建失败: $e')),
                      );
                    }
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    ).whenComplete(() => controller.dispose());
  }

  Future<void> _deleteSelected() async {
    if (_selectedNodes.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedNodes.length} 项吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      for (final node in _selectedNodes) {
        await _vfs.delete(node.path);
      }
      StatsService().recalculate();
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
        _loadFiles();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _shareSelected() async {
    if (_selectedNodes.isEmpty) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final shareDir = Directory(p.join(tempDir.path, 'vault_share_${DateTime.now().millisecondsSinceEpoch}'));
      await shareDir.create(recursive: true);
      _tempDirs.add(shareDir);

      final xFiles = <XFile>[];
      final nodesToShare = <Map<String, String>>[];
      for (final node in _selectedNodes) {
        if (node.isDirectory) continue;
        nodesToShare.add({'path': node.path, 'name': node.name});
        xFiles.add(XFile(p.join(shareDir.path, node.name)));
      }

      if (nodesToShare.isNotEmpty) {
        final args = {
          'nodes': nodesToShare,
          'shareDirPath': shareDir.path,
          'vaultDirectoryPath': widget.vaultDirectoryPath,
          'masterKey': widget.masterKey,
          'encryptFilename': widget.vaultConfig.encryptFilename,
        };
        await Isolate.spawn(_doShareFilesIsolate, args);
      }

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        if (xFiles.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可分享的文件')),
          );
          return;
        }
        try {
          await Share.shareXFiles(xFiles, text: '来自加密保险箱的分享');
        } finally {
          try {
            if (await shareDir.exists()) {
              await shareDir.delete(recursive: true);
            }
          } catch (_) {}
          _tempDirs.remove(shareDir);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  Future<void> _previewFile(VfsNode file) async {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final previewDir = Directory(p.join(tempDir.path, 'vault_preview_${DateTime.now().millisecondsSinceEpoch}'));
      await previewDir.create(recursive: true);
      _tempDirs.add(previewDir);

      final tempFile = File(p.join(previewDir.path, file.name));
      await Isolate.spawn(doExportFileIsolate, {
        'nodePath': file.path,
        'outFilePath': tempFile.path,
        'vaultDirectoryPath': widget.vaultDirectoryPath,
        'masterKey': widget.masterKey,
        'encryptFilename': widget.vaultConfig.encryptFilename,
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        final result = await OpenFilex.open(tempFile.path);
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打开文件失败: ${result.message}')),
          );
        }
        Timer(const Duration(minutes: 10), () async {
          try {
            if (await previewDir.exists()) {
              await previewDir.delete(recursive: true);
            }
          } catch (_) {}
          _tempDirs.remove(previewDir);
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解密预览失败: $e')),
        );
      }
    }
  }

  Widget _buildExpandableFab() {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isMenuOpen) ...[
          _buildFabOption('新建空文件夹', Icons.create_new_folder, _newFolder),
          const SizedBox(height: 16),
          _buildFabOption('导入明文文件夹', Icons.drive_folder_upload, _importFolder),
          const SizedBox(height: 16),
          _buildFabOption('导入明文文件', Icons.upload_file, _importFile),
          const SizedBox(height: 16),
        ],
        FloatingActionButton(
          heroTag: 'vault_explorer_fab',
          onPressed: () {
            setState(() {
              _isMenuOpen = !_isMenuOpen;
            });
          },
          backgroundColor: theme.colorScheme.primary,
          child: Icon(_isMenuOpen ? Icons.close : Icons.add),
        ),
      ],
    );
  }

  Widget _buildFabOption(String label, IconData icon, VoidCallback onPressed) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: theme.isCyberpunk ? BorderRadius.zero : BorderRadius.circular(8),
            border: theme.isCyberpunk ? Border.all(color: const Color(0xFF00E5FF)) : null,
            boxShadow: theme.isCyberpunk ? [] : [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 16),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onPressed,
          backgroundColor: theme.colorScheme.secondary,
          child: Icon(icon, color: theme.colorScheme.onSecondary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _currentPath == '/',
      onPopInvoked: (didPop) {
        if (!didPop && _currentPath != '/') {
          setState(() {
            _currentPath = p.dirname(_currentPath).replaceAll(r'\', '/');
            if (_currentPath.isEmpty) _currentPath = '/';
          });
          _loadFiles();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isMultiSelectMode
              ? Text('已选择 ${_selectedNodes.length} 项')
              : Text(_currentPath == '/' ? widget.vaultConfig.name.toUpperCase() : p.basename(_currentPath)),
          leading: _isMultiSelectMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isMultiSelectMode = false;
                      _selectedNodes.clear();
                    });
                  },
                )
              : (_currentPath != '/'
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        setState(() {
                          _currentPath = p.dirname(_currentPath).replaceAll(r'\', '/');
                          if (_currentPath.isEmpty) _currentPath = '/';
                        });
                        _loadFiles();
                      },
                    )
                  : null),
          actions: _isMultiSelectMode
              ? [
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: _selectedNodes.any((n) => !n.isDirectory) ? _shareSelected : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _selectedNodes.isNotEmpty ? _deleteSelected : null,
                  ),
                ]
              : [
                  IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: '加密进度',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        barrierColor: theme.colorScheme.scrim.withValues(alpha: 0.6),
                        shape: theme.isCyberpunk 
                            ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
                            : const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                        clipBehavior: Clip.antiAlias,
                        builder: (context) => DraggableScrollableSheet(
                          initialChildSize: 0.6,
                          minChildSize: 0.4,
                          maxChildSize: 0.9,
                          expand: false,
                          builder: (context, scrollController) => EncryptionProgressPanel(
                            scrollController: scrollController,
                          ),
                        ),
                      );
                    },
                  ),
                ],
        ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '保险箱目前为空',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final isSelected = _selectedNodes.contains(file);
                    return ListTile(
                      leading: _isMultiSelectMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedNodes.add(file);
                                  } else {
                                    _selectedNodes.remove(file);
                                  }
                                });
                              },
                            )
                          : Icon(
                              file.isDirectory ? Icons.folder : Icons.insert_drive_file,
                              color: file.isDirectory ? theme.colorScheme.primary : theme.colorScheme.secondary,
                            ),
                      title: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: file.isDirectory ? null : Text(FormatUtils.formatBytes(file.size)),
                      onLongPress: () {
                        if (!_isMultiSelectMode) {
                          setState(() {
                            _isMultiSelectMode = true;
                            _selectedNodes.add(file);
                          });
                        }
                      },
                      onTap: () {
                        if (_isMultiSelectMode) {
                          setState(() {
                            if (isSelected) {
                              _selectedNodes.remove(file);
                            } else {
                              _selectedNodes.add(file);
                            }
                          });
                        } else {
                          if (file.isDirectory) {
                            setState(() {
                              _currentPath = file.path;
                            });
                            _loadFiles();
                          } else {
                            _previewFile(file);
                          }
                        }
                      },
                    );
                  },
                ),
      floatingActionButton: _isMultiSelectMode ? null : _buildExpandableFab(),
    ),
    );
  }
}
