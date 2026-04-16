import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import 'webdav_config.dart';
import 'webdav_storage.dart';
import 'webdav_client_service.dart';

import '../vfs/virtual_file_system.dart';
import '../vfs/standard_vfs.dart';
import '../services/sync_storage_service.dart';
import '../models/sync_task.dart';
import '../utils/format_utils.dart';
import 'webdav_state_manager.dart';

class WebDavBrowserPage extends StatefulWidget {
  const WebDavBrowserPage({
    super.key,
    required this.config,
    this.isEmbedded = false,
  });

  final WebDavConfig config;
  final bool isEmbedded;

  @override
  State<WebDavBrowserPage> createState() => _WebDavBrowserPageState();


class _WebDavBrowserPageState extends State<WebDavBrowserPage> {
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
      final repo = WebDavConfigRepository();
      final password = await repo.readPassword(widget.config.id);
      
      final client = WebDavClientService(
        url: widget.config.url,
        username: widget.config.username,
        password: password ?? '',
      );
      
      _vfs = StandardVfs(client: client);

      await _loadCurrentPath();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '初始化客户端失败：${translateWebDavError(e)}';
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
          _error = '加载目录失败：${translateWebDavError(e)}';
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

  Future<void> _createFolder() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(() => nameController.dispose());

    if (name != null && name.trim().isNotEmpty) {
      if (mounted) setState(() => _isLoading = true);
      try {
        final newPath = '$_currentPath${name.trim()}/'.replaceAll('//', '/');
        await _vfs!.mkdir(newPath);
        if (mounted) await _loadCurrentPath();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建文件夹失败：${translateWebDavError(e)}')));
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      
      if (mounted) setState(() => _isLoading = true);
      try {
        final remotePath = '$_currentPath$fileName'.replaceAll('//', '/');
        await _vfs!.upload(file.path, remotePath);
        if (mounted) await _loadCurrentPath();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传文件失败：${translateWebDavError(e)}')));
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteItem(VfsNode file) async {
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

    if (confirm == true) {
      await _deleteItemWithoutConfirm(file);
    }
  }

  Future<void> _deleteItemWithoutConfirm(VfsNode file) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await _vfs!.delete(file.path);
      WebDAVStateManager.instance.addLog('已删除云端文件: ${file.name}');
      if (mounted) await _loadCurrentPath();
    } catch (e) {
      WebDAVStateManager.instance.addLog('删除云端文件失败: ${file.name} - $e', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：${translateWebDavError(e)}')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _renameItem(VfsNode file) async {
    final nameController = TextEditingController(text: file.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(() => nameController.dispose());

    if (newName != null && newName.trim().isNotEmpty && newName != file.name) {
      if (mounted) setState(() => _isLoading = true);
      try {
        String p = file.path;
        if (p.endsWith('/')) {
          p = p.substring(0, p.length - 1);
        }
        int lastSlash = p.lastIndexOf('/');
        String parentPath = lastSlash >= 0 ? p.substring(0, lastSlash + 1) : '/';
        
        String newPath = '$parentPath${newName.trim()}';
        if (file.isDirectory && !newPath.endsWith('/')) {
          newPath += '/';
        }
        
        await _vfs!.rename(file.path, newPath);
        if (mounted) await _loadCurrentPath();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败：${translateWebDavError(e)}')));
          setState(() => _isLoading = false);
        }
      }
    }
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
                                  onLongPress: () {
                                    if (widget.isEmbedded) {
                                      _deleteItem(file);
                                    }
                                  },
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'rename') {
                                        _renameItem(file);
                                      } else if (value == 'delete') {
                                        _deleteItem(file);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: Text('重命名'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('删除', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );

                                if (widget.isEmbedded) {
                                  return Dismissible(
                                    key: Key(file.path),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      color: Colors.red,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      child: const Icon(Icons.delete, color: Colors.white),
                                    ),
                                    confirmDismiss: (direction) async {
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
                                      return confirm == true;
                                    },
                                    onDismissed: (direction) {
                                      _deleteItemWithoutConfirm(file);
                                    },
                                    child: listTile,
                                  );
                                }

                                return listTile;
                              },
                            ),
                    ),
        ),
      ],
    );

    final floatingActionButton = FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.create_new_folder),
                  title: const Text('新建文件夹'),
                  onTap: () {
                    Navigator.pop(context);
                    _createFolder();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('上传文件'),
                  onTap: () {
                    Navigator.pop(context);
                    _uploadFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: const Icon(Icons.add),
    );

    if (widget.isEmbedded) {
      return Scaffold(
        body: body,
        floatingActionButton: floatingActionButton,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.name),
        centerTitle: true,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
