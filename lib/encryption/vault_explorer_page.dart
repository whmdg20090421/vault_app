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

Future<void> _doImportFileIsolate(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final files = args['files'] as List<Map<String, String>>;
  final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
  final masterKey = args['masterKey'] as Uint8List;
  final encryptFilename = args['encryptFilename'] as bool;
  final taskId = args['taskId'] as String;

  final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
  VirtualFileSystem vfs;
  if (encryptFilename) {
    final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: masterKey);
    await encryptedVfs.initEncryptedDomain('/');
    vfs = encryptedVfs;
  } else {
    vfs = localVfs;
  }

  try {
    int processedBytes = 0;
    for (final fileInfo in files) {
      final localPath = fileInfo['localPath']!;
      final remotePath = fileInfo['remotePath']!;
      final file = File(localPath);
      if (await file.exists()) {
        final size = await file.length();
        await vfs.upload(localPath, remotePath);
        processedBytes += size;
        sendPort.send({'type': 'progress', 'taskId': taskId, 'bytes': processedBytes});
      }
    }
    sendPort.send({'type': 'done', 'taskId': taskId});
  } catch (e) {
    sendPort.send({'type': 'error', 'taskId': taskId, 'error': e.toString()});
  }
}

Future<void> _doImportFolderIsolate(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final result = args['result'] as String;
  final currentPath = args['currentPath'] as String;
  final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
  final masterKey = args['masterKey'] as Uint8List;
  final encryptFilename = args['encryptFilename'] as bool;
  final taskId = args['taskId'] as String;

  final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
  VirtualFileSystem vfs;
  if (encryptFilename) {
    final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: masterKey);
    await encryptedVfs.initEncryptedDomain('/');
    vfs = encryptedVfs;
  } else {
    vfs = localVfs;
  }

  try {
    final dir = Directory(result);
    if (await dir.exists()) {
      final baseName = p.basename(result);
      final remoteDirPath = p.join(currentPath, baseName).replaceAll(r'\', '/');
      await vfs.mkdir(remoteDirPath);

      int processedBytes = 0;

      await for (final entity in dir.list(recursive: true)) {
        final relativePath = p.relative(entity.path, from: result);
        final remotePath = p.join(remoteDirPath, relativePath).replaceAll(r'\', '/');
        if (entity is File) {
          final size = await entity.length();
          await vfs.upload(entity.path, remotePath);
          processedBytes += size;
          sendPort.send({'type': 'progress', 'taskId': taskId, 'bytes': processedBytes});
        } else if (entity is Directory) {
          await vfs.mkdir(remotePath);
        }
      }
    }
    sendPort.send({'type': 'done', 'taskId': taskId});
  } catch (e) {
    sendPort.send({'type': 'error', 'taskId': taskId, 'error': e.toString()});
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

  @override
  void initState() {
    super.initState();
    _initVfs();
  }

  void _initVfs() async {
    final localVfs = LocalVfs(rootPath: widget.vaultDirectoryPath);
    if (widget.vaultConfig.encryptFilename) {
      final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: widget.masterKey);
      await encryptedVfs.initEncryptedDomain('/');
      _vfs = encryptedVfs;
    } else {
      _vfs = localVfs;
    }
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

        final task = EncryptionTask(
          id: taskId,
          name: taskName,
          totalBytes: totalSize,
          status: 'encrypting',
        );

        EncryptionTaskManager().addTask(task);

        final receivePort = ReceivePort();
        receivePort.listen((message) {
          if (message is Map<String, dynamic>) {
            final type = message['type'];
            final tid = message['taskId'] as String;
            if (type == 'progress') {
              final bytes = message['bytes'] as int;
              EncryptionTaskManager().updateTaskProgress(tid, bytes);
            } else if (type == 'done') {
              EncryptionTaskManager().updateTaskStatus(tid, 'completed');
              StatsService().recalculate();
              if (mounted) {
                _loadCurrentDirectory();
              }
              receivePort.close();
            } else if (type == 'error') {
              final error = message['error'] as String;
              EncryptionTaskManager().updateTaskStatus(tid, 'failed', error: error);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('导入文件失败: $error')),
                );
              }
              receivePort.close();
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

        Isolate.run(() => _doImportFileIsolate(args));
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
          
          final task = EncryptionTask(
            id: taskId,
            name: baseName,
            totalBytes: totalSize,
            status: 'encrypting',
          );

          EncryptionTaskManager().addTask(task);

          final receivePort = ReceivePort();
          receivePort.listen((message) {
            if (message is Map<String, dynamic>) {
              final type = message['type'];
              final tid = message['taskId'] as String;
              if (type == 'progress') {
                final bytes = message['bytes'] as int;
                EncryptionTaskManager().updateTaskProgress(tid, bytes);
              } else if (type == 'done') {
                EncryptionTaskManager().updateTaskStatus(tid, 'completed');
                StatsService().recalculate();
                if (mounted) {
                  _loadCurrentDirectory();
                }
                receivePort.close();
              } else if (type == 'error') {
                final error = message['error'] as String;
                EncryptionTaskManager().updateTaskStatus(tid, 'failed', error: error);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('导入文件夹失败: $error')),
                  );
                }
                receivePort.close();
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

          Isolate.run(() => _doImportFolderIsolate(args));
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

      final stream = await _vfs.open(node.path);
      final outFile = File(p.join(selectedDir, node.name));
      final sink = outFile.openWrite();
      await stream.pipe(sink);

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

      final xFiles = <XFile>[];
      for (final node in _selectedNodes) {
        if (node.isDirectory) continue; // 仅支持分享文件
        final stream = await _vfs.open(node.path);
        final tempFile = File(p.join(shareDir.path, node.name));
        final sink = tempFile.openWrite();
        await stream.pipe(sink);
        xFiles.add(XFile(tempFile.path));
      }

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        if (xFiles.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可分享的文件')),
          );
          return;
        }
        await Share.shareXFiles(xFiles, text: '来自加密保险箱的分享');
        // 分享完成后清理临时文件
        if (await shareDir.exists()) {
          await shareDir.delete(recursive: true);
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

      final stream = await _vfs.open(file.path);
      final tempFile = File(p.join(previewDir.path, file.name));
      final sink = tempFile.openWrite();
      await stream.pipe(sink);

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        final result = await OpenFilex.open(tempFile.path);
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打开文件失败: ${result.message}')),
          );
        }
        // 由于预览可能是异步外部进程，我们不能立即删除文件，可以依赖系统的临时目录清理，
        // 或者保留一段时间。这里为简便，依赖系统自动清理临时目录。
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
              : null,
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
