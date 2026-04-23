import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
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
import 'widgets/encryption_progress_panel.dart';
import 'dart:isolate';
import '../theme/app_theme.dart';
import 'encryption_page.dart';









@visibleForTesting
Future<void> doExportFileIsolate(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  try {
    final nodePath = args['nodePath'] as String;
    final outFilePath = args['outFilePath'] as String;
    final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
    final masterKey = args['masterKey'] as Uint8List;
    final encryptFilename = args['encryptFilename'] as bool;

    final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
    final encryptedVfs = EncryptedVfs(
      baseVfs: localVfs,
      masterKey: masterKey,
      encryptFilename: encryptFilename,
    );
    await encryptedVfs.initEncryptedDomain('/');

    final outFile = File(outFilePath);
    final sink = outFile.openWrite();
    final stream = await encryptedVfs.open(nodePath);
    await for (final chunk in stream) {
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
    sendPort.send({'type': 'done'});
  } catch (e) {
    sendPort.send({'type': 'error', 'error': e.toString()});
  }
}

Future<void> _doShareFilesIsolate(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  try {
    final nodes = args['nodes'] as List<Map<String, String>>;
    final shareDirPath = args['shareDirPath'] as String;
    final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
    final masterKey = args['masterKey'] as Uint8List;
    final encryptFilename = args['encryptFilename'] as bool;

    final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
    final encryptedVfs = EncryptedVfs(
      baseVfs: localVfs,
      masterKey: masterKey,
      encryptFilename: encryptFilename,
    );
    await encryptedVfs.initEncryptedDomain('/');

    for (final node in nodes) {
      final nodePath = node['path']!;
      final name = node['name']!;
      final outFile = File(p.join(shareDirPath, name));
      final sink = outFile.openWrite();
      final stream = await encryptedVfs.open(nodePath);
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    }
    sendPort.send({'type': 'done'});
  } catch (e) {
    sendPort.send({'type': 'error', 'error': e.toString()});
  }
}

class VaultExplorerPage
 extends StatefulWidget {
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
  final List<Timer> _previewTimers = [];
  
  VfsNode? _clipboardNode;
  bool _isCut = false;

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

    for (final timer in _previewTimers) {
      timer.cancel();
    }
    _previewTimers.clear();

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
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 ${result.files.length} 个文件添加到后台加密任务，请在顶部进度图标查看进度')),
        );
      }
      try {
        for (final file in result.files) {
          if (file.path != null) {
            final taskArgs = <String, dynamic>{
              'vaultDirectoryPath': widget.vaultDirectoryPath,
              'masterKey': widget.masterKey.toList(),
              'encryptFilename': widget.vaultConfig.encryptFilename,
              'currentPath': _currentPath,
            };
            EncryptionTaskManager().createEncryptionTask(file.path!, taskArgs: taskArgs);
          }
        }
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
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已将文件夹添加到后台加密任务，请在顶部进度图标查看进度')),
        );
      }
      try {
        final taskArgs = {
          'vaultDirectoryPath': widget.vaultDirectoryPath,
          'masterKey': widget.masterKey.toList(),
          'encryptFilename': widget.vaultConfig.encryptFilename,
          'currentPath': _currentPath,
        };
        EncryptionTaskManager().createEncryptionTask(result, taskArgs: taskArgs);
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
      final receivePort = ReceivePort();
      
      await Isolate.spawn(doExportFileIsolate, {
        'sendPort': receivePort.sendPort,
        'nodePath': node.path,
        'outFilePath': outFile.path,
        'vaultDirectoryPath': widget.vaultDirectoryPath,
        'masterKey': widget.masterKey,
        'encryptFilename': widget.vaultConfig.encryptFilename,
      });

      final completer = Completer<void>();
      receivePort.listen((message) {
        if (message['type'] == 'done') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('导出成功: ${outFile.path}')),
            );
          }
          completer.complete();
          receivePort.close();
        } else if (message['type'] == 'error') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('导出失败: ${message['error']}')),
            );
          }
          completer.completeError(message['error']);
          receivePort.close();
        }
      });

      await completer.future;

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _newFolder() async {
    setState(() => _isMenuOpen = false);
    final controller = TextEditingController();
    try {
      await showDialog(
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
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _paste() async {
    if (_clipboardNode == null) return;
    
    final node = _clipboardNode!;
    final isCut = _isCut;
    
    // reset clipboard
    setState(() {
      _clipboardNode = null;
      _isCut = false;
    });

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final newPath = p.join(_currentPath, node.name).replaceAll(r'\', '/');
      
      if (isCut) {
        await _vfs.rename(node.path, newPath);
      } else {
        await _copyRecursive(node, newPath);
      }
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作成功')),
        );
        _loadFiles();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _copyRecursive(VfsNode node, String destPath) async {
    if (node.isDirectory) {
      await _vfs.mkdir(destPath);
      final children = await _vfs.list(node.path);
      for (final child in children) {
        await _copyRecursive(child, p.join(destPath, child.name).replaceAll(r'\', '/'));
      }
    } else {
      final stream = await _vfs.open(node.path);
      await _vfs.uploadStream(stream, node.size, destPath);
    }
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

  Future<Directory> _getCacheDirectory() async {
    Directory? tempDir;
    if (Platform.isAndroid) {
      final dirs = await getExternalCacheDirectories();
      if (dirs != null && dirs.isNotEmpty) {
        tempDir = dirs.first;
      }
    }
    return tempDir ?? await getTemporaryDirectory();
  }

  Future<void> _renameFile(VfsNode file) async {
    final controller = TextEditingController(text: file.name);
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: '新名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }

    if (result != null && result.isNotEmpty && result != file.name) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
      }
      try {
        final newPath = p.join(p.dirname(file.path), result).replaceAll(r'\', '/');
        await _vfs.rename(file.path, newPath);
        if (mounted) {
          Navigator.pop(context); // Close loading
          _loadFiles();
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('重命名失败: $e')),
          );
        }
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
      final tempDir = await _getCacheDirectory();
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
        final receivePort = ReceivePort();
        final args = {
          'sendPort': receivePort.sendPort,
          'nodes': nodesToShare,
          'shareDirPath': shareDir.path,
          'vaultDirectoryPath': widget.vaultDirectoryPath,
          'masterKey': widget.masterKey,
          'encryptFilename': widget.vaultConfig.encryptFilename,
        };
        await Isolate.spawn(_doShareFilesIsolate, args);

        final completer = Completer<void>();
        receivePort.listen((message) {
          if (message['type'] == 'done') {
            completer.complete();
            receivePort.close();
          } else if (message['type'] == 'error') {
            completer.completeError(message['error']);
            receivePort.close();
          }
        });
        await completer.future;
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
      final tempDir = await _getCacheDirectory();
      final previewDir = Directory(p.join(tempDir.path, 'vault_preview_${DateTime.now().millisecondsSinceEpoch}'));
      await previewDir.create(recursive: true);
      _tempDirs.add(previewDir);

      final tempFile = File(p.join(previewDir.path, file.name));
      final receivePort = ReceivePort();
      
      await Isolate.spawn(doExportFileIsolate, {
        'sendPort': receivePort.sendPort,
        'nodePath': file.path,
        'outFilePath': tempFile.path,
        'vaultDirectoryPath': widget.vaultDirectoryPath,
        'masterKey': widget.masterKey,
        'encryptFilename': widget.vaultConfig.encryptFilename,
      });

      final completer = Completer<void>();
      receivePort.listen((message) {
        if (message['type'] == 'done') {
          completer.complete();
          receivePort.close();
        } else if (message['type'] == 'error') {
          completer.completeError(message['error']);
          receivePort.close();
        }
      });

      await completer.future;

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        final result = await OpenFilex.open(tempFile.path);
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打开文件失败: ${result.message}')),
          );
        }
        final timer = Timer(const Duration(minutes: 10), () async {
          try {
            if (await previewDir.exists()) {
              await previewDir.delete(recursive: true);
            }
          } catch (_) {}
          _tempDirs.remove(previewDir);
        });
        _previewTimers.add(timer);
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
                  if (_clipboardNode != null)
                    IconButton(
                      icon: const Icon(Icons.paste),
                      tooltip: '粘贴',
                      onPressed: _paste,
                    ),
                  IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: '加密进度',
                    onPressed: () {
                      showEncryptionProgressPanel(context);
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
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            builder: (context) {
                              return SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.check_box_outlined),
                                      title: const Text('多选'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        setState(() {
                                          _isMultiSelectMode = true;
                                          _selectedNodes.add(file);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.edit),
                                      title: const Text('重命名'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _renameFile(file);
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.drive_file_move_outline),
                                      title: const Text('移动'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        setState(() {
                                          _clipboardNode = file;
                                          _isCut = true;
                                        });
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.copy),
                                      title: const Text('复制'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        setState(() {
                                          _clipboardNode = file;
                                          _isCut = false;
                                        });
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.delete, color: Colors.red),
                                      title: const Text('删除', style: TextStyle(color: Colors.red)),
                                      onTap: () {
                                        Navigator.pop(context);
                                        setState(() {
                                          _selectedNodes.clear();
                                          _selectedNodes.add(file);
                                        });
                                        _deleteSelected();
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
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
                            showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('打开文件'),
                                content: Text('是否打开文件 ${file.name}?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('确定'),
                                  ),
                                ],
                              ),
                            ).then((confirm) {
                              if (confirm == true) {
                                _previewFile(file);
                              }
                            });
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
