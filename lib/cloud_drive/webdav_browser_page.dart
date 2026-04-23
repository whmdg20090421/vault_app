import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'webdav_config.dart';
import 'webdav_storage.dart';
import 'webdav_new/webdav_client.dart';
import 'webdav_new/webdav_service.dart';

import '../vfs/virtual_file_system.dart';
import '../vfs/standard_vfs.dart';
import '../services/sync_storage_service.dart';
import '../models/sync_task.dart';
import '../utils/format_utils.dart';
import '../widgets/vfs_folder_picker_dialog.dart';

class WebDavBrowserPage extends StatefulWidget {
  const WebDavBrowserPage({
    super.key,
    required this.config,
    this.isEmbedded = false,
    this.isPickingFolder = false,
  });

  final WebDavConfig config;
  final bool isEmbedded;
  final bool isPickingFolder;

  @override
  State<WebDavBrowserPage> createState() => _WebDavBrowserPageState();
}

class _WebDavBrowserPageState extends State<WebDavBrowserPage> {
  WebDavService? _service;
  VirtualFileSystem? _vfs;
  bool _isLoading = true;
  String _error = '';

  List<String> _pathSegments = [];
  List<VfsNode> _files = [];
  Set<String> _syncedPaths = {};

  String get _currentPath {
    if (_pathSegments.isEmpty) return '/';
    return '/${_pathSegments.join('/')}/';
  }

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  Future<void> _loadSyncStatus() async {
    try {
      final syncStorage = SyncStorageService();
      final tasks = await syncStorage.loadTasks();
      final syncedPaths = <String>{};
      
      for (final task in tasks) {
        if (task.cloudWebDavId == widget.config.id) {
          for (final item in task.items) {
            if (item.status == SyncStatus.completed) {
              syncedPaths.add(item.path);
            }
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _syncedPaths = syncedPaths;
        });
      }
    } catch (e) {
      // Ignore sync status load error
    }
  }

  Future<void> _initClient() async {
    try {
      final repository = WebDavConfigRepository();
      final password = await repository.readPassword(widget.config.id) ?? '';

      final client = WebDavClient(
        baseUrl: widget.config.url,
        username: widget.config.username,
        password: password,
      );
      final service = WebDavService(client);
      _service = service;
      _vfs = StandardVfs(service);

      await _loadCurrentPath();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '初始化客户端失败：${e.toString()}';
        });
      }
    }
  }

  Future<void> _loadCurrentPath() async {
    if (_vfs == null) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = '';
      });
    }

    try {
      await _loadSyncStatus();
      final list = await _vfs!.list(_currentPath);

      // Sort: folders first, then alphabetically
      list.sort((a, b) {
        if (a.isDirectory == b.isDirectory) {
          return a.name.compareTo(b.name);
        }
        return a.isDirectory ? -1 : 1;
      });

      if (mounted) {
        setState(() {
          _files = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载目录失败：${e.toString()}';
        });
      }
    }
  }

  void _navigateTo(String folderName) {
    setState(() {
      String cleanName = folderName;
      if (cleanName.endsWith('/')) {
        cleanName = cleanName.substring(0, cleanName.length - 1);
      }
      if (cleanName.startsWith('/')) {
        cleanName = cleanName.substring(1);
      }
      _pathSegments.add(cleanName);
    });
    _loadCurrentPath();
  }

  void _navigateUpTo(int index) {
    if (index < -1 || index >= _pathSegments.length) return;
    setState(() {
      if (index == -1) {
        _pathSegments.clear();
      } else {
        _pathSegments = _pathSegments.sublist(0, index + 1);
      }
    });
    _loadCurrentPath();
  }

  Widget _buildBreadcrumbs() {
    final List<Widget> crumbs = [];
    
    // Add Root
    crumbs.add(
      InkWell(
        onTap: () => _navigateUpTo(-1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Text(
            'Root',
            style: TextStyle(
              color: _pathSegments.isEmpty ? Colors.black : Colors.blue,
              fontWeight: _pathSegments.isEmpty ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );

    for (int i = 0; i < _pathSegments.length; i++) {
      crumbs.add(const Text('/'));
      crumbs.add(
        InkWell(
          onTap: () => _navigateUpTo(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Text(
              _pathSegments[i],
              style: TextStyle(
                color: i == _pathSegments.length - 1 ? Colors.black : Colors.blue,
                fontWeight: i == _pathSegments.length - 1 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: crumbs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBreadcrumbs(),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                  ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
                  : RefreshIndicator(
                      onRefresh: _loadCurrentPath,
                      child: _files.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 100),
                                Center(child: Text('空目录')),
                              ],
                            )
                          : ListView.builder(
                              itemCount: _files.length,
                              itemBuilder: (context, index) {
                                final file = _files[index];
                                final isDir = file.isDirectory;
                                
                                // 检查同步状态
                                bool isSynced = false;
                                if (!isDir) {
                                  String cleanPath = file.path;
                                  if (cleanPath.startsWith('/')) {
                                    cleanPath = cleanPath.substring(1);
                                  }
                                  isSynced = _syncedPaths.contains(cleanPath) || _syncedPaths.contains(file.path);
                                }

                                final listTile = ListTile(
                                  leading: Icon(
                                    isDir ? Icons.folder : Icons.insert_drive_file,
                                    color: isDir ? Colors.orange : Colors.blue,
                                  ),
                                  title: Text(file.name),
                                  subtitle: isDir ? null : Row(
                                    children: [
                                      Text(FormatUtils.formatBytes(file.size)),
                                      const SizedBox(width: 8),
                                      if (isSynced)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.green.withOpacity(0.5)),
                                          ),
                                          child: const Text('已同步', style: TextStyle(fontSize: 10, color: Colors.green)),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.grey.withOpacity(0.5)),
                                          ),
                                          child: const Text('未同步', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                        ),
                                    ],
                                  ),
                                  onTap: isDir ? () => _navigateTo(file.name) : null,
                                  trailing: widget.isPickingFolder ? null : PopupMenuButton<String>(
                                    color: Theme.of(context).colorScheme.surface,
                                    onSelected: (value) async {
                                      if (value == 'delete') {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('确认删除'),
                                            content: Text('确定要删除 ${file.name} 吗？'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, false),
                                                child: const Text('取消'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, true),
                                                child: const Text('删除', style: TextStyle(color: Colors.red)),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true && _service != null) {
                                          try {
                                            await _service!.remove(file.path);
                                            _loadCurrentPath();
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('删除失败: $e')),
                                              );
                                            }
                                          }
                                        }
                                      } else if (value == 'move' || value == 'copy') {
                                        if (_service == null) return;
                                        final result = await showDialog<String>(
                                          context: context,
                                          builder: (_) => VfsFolderPickerDialog(
                                            vfs: StandardVfs(_service!),
                                            initialPath: '/',
                                          ),
                                        );
                                        if (result != null) {
                                          try {
                                            final targetPath = p.join(result, file.name).replaceAll('\\', '/');
                                            if (value == 'move') {
                                              await _service!.move(file.path, targetPath);
                                            } else {
                                              await _service!.copy(file.path, targetPath);
                                            }
                                            _loadCurrentPath();
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('${value == 'move' ? '移动' : '复制'}失败: $e')),
                                              );
                                            }
                                          }
                                        }
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(value: 'move', child: Text('移动')),
                                      PopupMenuItem(value: 'copy', child: Text('复制')),
                                      PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );

                                return listTile;
                              },
                            ),
                    ),
        ),
      ],
    );

    if (widget.isEmbedded) {
      return Scaffold(
        body: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPickingFolder ? '选择目录' : widget.config.name),
        centerTitle: true,
      ),
      body: body,
      floatingActionButton: widget.isPickingFolder
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.pop(context, _currentPath);
              },
              icon: const Icon(Icons.check),
              label: const Text('选择此文件夹'),
            )
          : null,
    );
  }
}
