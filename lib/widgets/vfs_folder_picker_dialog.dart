import 'package:flutter/material.dart';
import '../vfs/virtual_file_system.dart';
import '../cloud_drive/webdav_new/webdav_logger.dart';
import 'error_dialog.dart';

class VfsFolderPickerDialog extends StatefulWidget {
  final VirtualFileSystem vfs;
  final String title;

  const VfsFolderPickerDialog({Key? key, required this.vfs, required this.title}) : super(key: key);

  @override
  State<VfsFolderPickerDialog> createState() => _VfsFolderPickerDialogState();
}

class _VfsFolderPickerDialogState extends State<VfsFolderPickerDialog> {
  List<String> _pathSegments = [];
  List<VfsNode> _items = [];
  bool _isLoading = true;

  String get _currentPath {
    if (_pathSegments.isEmpty) return '/';
    return '/${_pathSegments.join('/')}/';
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final list = await widget.vfs.list(_currentPath);
      
      // Sort: folders first, then files, both alphabetically
      list.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.compareTo(b.name);
      });
      
      if (mounted) {
        setState(() {
          _items = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        WebDavLogger.writeErrorLog('加载文件夹失败: $e');
        showVfsErrorDialog(context, '加载文件夹失败: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateTo(String folderName) {
    setState(() {
      _pathSegments.add(folderName.replaceAll('/', ''));
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBreadcrumbs(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadCurrentPath,
                    child: _items.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              Center(child: Text('目录为空')),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              if (item.isDirectory) {
                                return ListTile(
                                  leading: const Icon(Icons.folder, color: Colors.orange),
                                  title: Text(item.name),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _navigateTo(item.name),
                                );
                              } else {
                                return ListTile(
                                  leading: const Icon(Icons.insert_drive_file, color: Colors.grey),
                                  title: Text(item.name),
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('请选择文件夹')),
                                    );
                                  },
                                );
                              }
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pop(_currentPath);
        },
        icon: const Icon(Icons.check),
        label: const Text('选择当前目录'),
      ),
    );
  }
}
