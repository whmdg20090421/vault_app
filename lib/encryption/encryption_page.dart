import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class EncryptionPage extends StatefulWidget {
  const EncryptionPage({super.key});

  @override
  State<EncryptionPage> createState() => _EncryptionPageState();
}

class _EncryptionPageState extends State<EncryptionPage> {
  List<String> _selectedPaths = [];

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // 动态请求权限: Android 11+ 使用 manageExternalStorage，旧版本使用 storage
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;
      
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;
      
      return false;
    }
    return true;
  }

  Future<void> _pickFiles() async {
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要存储权限才能选择文件')),
        );
      }
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );
      
      if (result != null) {
        setState(() {
          _selectedPaths.addAll(result.paths.whereType<String>());
          // 去重
          _selectedPaths = _selectedPaths.toSet().toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件失败: $e')),
        );
      }
    }
  }

  Future<void> _pickFolder() async {
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要存储权限才能选择文件夹')),
        );
      }
      return;
    }

    try {
      final result = await FilePicker.platform.getDirectoryPath();
      
      if (result != null) {
        setState(() {
          if (!_selectedPaths.contains(result)) {
            _selectedPaths.add(result);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件夹失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark && 
                        theme.colorScheme.secondary.value == 0xFFFF2D95;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '加密中心',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                      shadows: isCyberpunk ? [
                        Shadow(
                          color: theme.colorScheme.primary.withOpacity(0.8),
                          blurRadius: 8,
                        )
                      ] : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '选择需要加密的文件或文件夹',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.insert_drive_file_rounded,
                          title: '选择文件',
                          onTap: _pickFiles,
                          isCyberpunk: isCyberpunk,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.folder_rounded,
                          title: '选择文件夹',
                          onTap: _pickFolder,
                          isCyberpunk: isCyberpunk,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _selectedPaths.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 64,
                            color: theme.colorScheme.onSurface.withOpacity(0.2),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂未选择任何内容',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _selectedPaths.length,
                      itemBuilder: (context, index) {
                        final path = _selectedPaths[index];
                        final isDirectory = FileSystemEntity.isDirectorySync(path);
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: isCyberpunk ? 0 : 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: isCyberpunk 
                                ? BorderSide(color: theme.colorScheme.secondary.withOpacity(0.5))
                                : BorderSide.none,
                          ),
                          color: isCyberpunk ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isCyberpunk 
                                    ? theme.colorScheme.secondary.withOpacity(0.1)
                                    : theme.colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                                color: isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary,
                              ),
                            ),
                            title: Text(
                              path.split(Platform.pathSeparator).last,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              path,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.close_rounded, color: theme.colorScheme.error),
                              onPressed: () {
                                setState(() {
                                  _selectedPaths.removeAt(index);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_selectedPaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('加密功能即将推出')),
                      );
                    },
                    icon: const Icon(Icons.enhanced_encryption_rounded),
                    label: const Text(
                      '立即加密',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCyberpunk ? theme.colorScheme.tertiary : theme.colorScheme.primary,
                      foregroundColor: isCyberpunk ? theme.colorScheme.surface : theme.colorScheme.onPrimary,
                      elevation: isCyberpunk ? 8 : 2,
                      shadowColor: isCyberpunk ? theme.colorScheme.tertiary.withOpacity(0.5) : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isCyberpunk;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.isCyberpunk,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Material(
      color: isCyberpunk ? theme.colorScheme.surfaceContainer : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: isCyberpunk
              ? BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.5),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: theme.colorScheme.primary,
                shadows: isCyberpunk ? [
                  Shadow(
                    color: theme.colorScheme.primary.withOpacity(0.8),
                    blurRadius: 12,
                  )
                ] : null,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isCyberpunk ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
