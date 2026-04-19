import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../theme/app_theme.dart';

import 'models/vault_config.dart';
import 'utils/crypto_utils.dart';
import '../utils/format_utils.dart';
import 'vault_config_page.dart';
import 'vault_explorer_page.dart';
import 'services/encryption_task_manager.dart';

class EncryptionPage extends StatefulWidget {
  const EncryptionPage({super.key});

  @override
  State<EncryptionPage> createState() => _EncryptionPageState();
}

class _VaultItem {
  final String path;
  final VaultConfig? config;

  _VaultItem(this.path, this.config);
}

class _EncryptionPageState extends State<EncryptionPage> {
  List<_VaultItem> _vaults = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVaults();
  }

  Future<void> _loadVaults() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList('vault_paths') ?? [];
      final List<_VaultItem> loaded = [];

      for (final path in paths) {
        final configFile = File('$path/vault_config.json');
        if (await configFile.exists()) {
          try {
            final jsonStr = await configFile.readAsString();
            final jsonMap = jsonDecode(jsonStr);
            final config = VaultConfig.fromJson(jsonMap);
            loaded.add(_VaultItem(path, config));
          } catch (e) {
            loaded.add(_VaultItem(path, null));
          }
        } else {
          loaded.add(_VaultItem(path, null));
        }
      }

      if (mounted) {
        setState(() {
          _vaults = loaded;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;
      
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;
      
      return false;
    }
    return true;
  }

  Future<void> _pickFolderAndConfig() async {
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
      
      if (result != null && mounted) {
        // 跳转到配置页面
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VaultConfigPage(vaultDirectoryPath: result),
          ),
        );
        // 返回后重新加载
        _loadVaults();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件夹失败: $e')),
        );
      }
    }
  }

  void _showUnlockDialog(_VaultItem item) {
    if (item.config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置文件无效或不存在，无法解锁')),
      );
      return;
    }

    final passwordController = TextEditingController();
    bool isUnlocking = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('解锁保险箱 (Unlock Vault)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('正在解锁: ${item.config!.name}'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: '请输入密码 (Password)'),
                      obscureText: true,
                      enabled: !isUnlocking,
                    ),
                    if (isUnlocking) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUnlocking ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消 (Cancel)'),
                ),
                ElevatedButton(
                  onPressed: isUnlocking
                      ? null
                      : () async {
                          final pwd = passwordController.text;
                          if (pwd.isEmpty) return;

                          setStateDialog(() {
                            isUnlocking = true;
                          });

                          try {
                            final config = item.config!;
                            // Derive key
                            final derivedKey = await CryptoUtils.deriveKeyAsync(
                              password: pwd,
                              saltBase64: config.salt,
                              kdfType: config.kdf,
                              kdfParams: config.kdfParams,
                            );

                            // Try to decrypt validation ciphertext
                            final nonceBytes = base64Url.decode(config.nonce);
                            final ciphertextBytes = base64Decode(config.validationCiphertext);
                            
                            final decryptedBytes = CryptoUtils.decrypt(
                              key: derivedKey,
                              nonce: nonceBytes,
                              ciphertext: ciphertextBytes,
                              algorithm: config.algorithm,
                            );

                            final decryptedString = utf8.decode(decryptedBytes);
                            if (decryptedString == 'vault_magic_encrypted') {
                              if (mounted) {
                                Navigator.of(context).pop(); // Close dialog
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => VaultExplorerPage(
                                      vaultConfig: config,
                                      masterKey: derivedKey,
                                      vaultDirectoryPath: item.path,
                                    ),
                                  ),
                                );
                              }
                            } else {
                              throw Exception('Invalid magic string');
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('密码错误或配置损坏 (Incorrect password or corrupted config)')),
                            );
                          } finally {
                            if (mounted) {
                              setStateDialog(() {
                                isUnlocking = false;
                              });
                            }
                          }
                        },
                  child: const Text('解锁 (Unlock)'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() => passwordController.dispose());
  }

  Future<void> _removeVault(int index) async {
    final path = _vaults[index].path;
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('vault_paths') ?? [];
    paths.remove(path);
    await prefs.setStringList('vault_paths', paths);

    if (mounted) {
      setState(() {
        _vaults.removeAt(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark && 
                        theme.colorScheme.primary.value == 0xFF00E5FF;

    return Scaffold(
      appBar: AppBar(
        title: Text('加密保险箱 (VAULTS)'.toUpperCase()),
        actions: [
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
          : _vaults.isEmpty
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
                        '暂无保险箱，点击右下角添加',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _vaults.length,
                  itemBuilder: (context, index) {
                    final item = _vaults[index];
                    final hasConfig = item.config != null;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: isCyberpunk ? 0 : 1,
                      shape: isCyberpunk
                          ? const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                              side: BorderSide(color: Color(0xFF00E5FF), width: 1.0),
                            )
                          : RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                      color: isCyberpunk ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface,
                      child: ListTile(
                        onTap: () => _showUnlockDialog(item),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isCyberpunk 
                                ? theme.colorScheme.secondary.withValues(alpha: 0.1)
                                : theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: isCyberpunk ? BorderRadius.zero : BorderRadius.circular(12),
                          ),
                          child: Icon(
                            hasConfig ? Icons.lock : Icons.error_outline,
                            color: hasConfig
                                ? (isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary)
                                : theme.colorScheme.error,
                          ),
                        ),
                        title: Text(
                          hasConfig ? item.config!.name : '未配置 (Unconfigured)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          item.path,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          onPressed: () => _removeVault(index),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFolderAndConfig,
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class EncryptionProgressPanel extends StatefulWidget {
  final ScrollController scrollController;

  const EncryptionProgressPanel({super.key, required this.scrollController});

  @override
  State<EncryptionProgressPanel> createState() => _EncryptionProgressPanelState();
}

class _EncryptionProgressPanelState extends State<EncryptionProgressPanel> with SingleTickerProviderStateMixin {
  final List<String> _navigationStack = [];
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateBack() {
    if (_navigationStack.isNotEmpty) {
      setState(() {
        _navigationStack.removeLast();
      });
    }
  }

  void _navigateTo(String taskId) {
    setState(() {
      _navigationStack.add(taskId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark &&
                        theme.colorScheme.primary.value == 0xFF00E5FF;
    final surfaceColor = theme.dialogTheme.backgroundColor ??
        theme.cardTheme.color ??
        theme.colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: isCyberpunk ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(16)),
        border: isCyberpunk
            ? Border(top: BorderSide(color: theme.colorScheme.primary, width: 2))
            : null,
      ),
      child: ListenableBuilder(
        listenable: EncryptionTaskManager(),
        builder: (context, _) {
          final manager = EncryptionTaskManager();
          
          EncryptionTask? currentParent;
          List<EncryptionTask> currentTasks = manager.tasks;
          String title = '加密任务进度';
          
          if (_navigationStack.isNotEmpty) {
            final parentId = _navigationStack.last;
            currentParent = manager.findTask(parentId);
            if (currentParent != null) {
              currentTasks = currentParent.children;
              title = currentParent.name;
            } else {
              // If parent was deleted (cancelled), pop it
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigateBack();
              });
            }
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    if (_navigationStack.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _navigateBack,
                      ),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isCyberpunk ? theme.colorScheme.secondary : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (_navigationStack.isEmpty)
                TabBar(
                  controller: _tabController,
                  labelColor: isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
                  indicatorColor: isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary,
                  tabs: const [
                    Tab(text: '进行中'),
                    Tab(text: '历史记录'),
                  ],
                ),
              if (isCyberpunk)
                Divider(height: 1, color: theme.colorScheme.primary.withOpacity(0.5)),
              if (manager.tasks.isNotEmpty && _navigationStack.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: manager.hasActiveTasks ? Colors.orange.withOpacity(0.8) : theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: Icon(manager.hasActiveTasks ? Icons.pause_circle_filled : Icons.play_circle_filled),
                      label: Text(
                        manager.hasActiveTasks ? '一键全部暂停' : '一键全部开始',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        if (manager.hasActiveTasks) {
                          manager.pauseAll();
                        } else {
                          manager.resumeAll();
                        }
                      },
                    ),
                  ),
                ),
              Expanded(
                child: _navigationStack.isEmpty
                    ? TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTaskList(context, currentTasks, theme, false),
                          _buildTaskList(context, manager.historyTasks, theme, true),
                        ],
                      )
                    : _buildTaskList(context, currentTasks, theme, false),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, List<EncryptionTask> tasks, ThemeData theme, bool isHistory) {
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          '当前没有任务',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: _TaskCard(
                  task: task,
                  onFolderTap: isHistory ? (_) {} : _navigateTo,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  final EncryptionTask task;
  final ValueChanged<String> onFolderTap;

  const _TaskCard({
    required this.task,
    required this.onFolderTap,
  });

  String _formatEta(int seconds) {
    if (seconds <= 0) return '';
    if (seconds > 60) {
      final mins = seconds ~/ 60;
      final secs = seconds % 60;
      return ' (剩余 ${mins}分${secs}秒)';
    }
    return ' (剩余 ${seconds}秒)';
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    return ' (速度: ${FormatUtils.formatBytes(bytesPerSec.round())}/s)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark &&
                        theme.colorScheme.primary.value == 0xFF00E5FF;
    
    final statusColor = _getStatusColor(task.status, theme);
    final statusText = _getStatusText(task.status);
    final progress = task.progress;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCyberpunk ? Colors.transparent : theme.colorScheme.surface,
        borderRadius: isCyberpunk ? BorderRadius.zero : BorderRadius.circular(16),
        border: isCyberpunk
            ? Border.all(color: theme.colorScheme.primary.withOpacity(0.3))
            : Border.all(color: Colors.transparent),
        boxShadow: isCyberpunk
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: isCyberpunk ? BorderRadius.zero : BorderRadius.circular(16),
        child: InkWell(
          borderRadius: isCyberpunk ? BorderRadius.zero : BorderRadius.circular(16),
          onTap: task.isDirectory && task.children.isNotEmpty
              ? () => onFolderTap(task.id)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    task.isDirectory ? Icons.folder : Icons.insert_drive_file,
                    color: isCyberpunk ? theme.colorScheme.primary : theme.colorScheme.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      border: Border.all(color: statusColor.withOpacity(0.5)),
                      borderRadius: isCyberpunk ? BorderRadius.zero : BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: isCyberpunk ? BorderRadius.zero : BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  minHeight: isCyberpunk ? 2 : 4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%${(task.status == 'encrypting' || task.status == 'pending') ? _formatEta(task.etaSeconds) : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontFamily: isCyberpunk ? 'Courier' : null,
                    ),
                  ),
                  Text(
                    '${FormatUtils.formatBytes(task.processedBytes)} / ${FormatUtils.formatBytes(task.totalBytes)}${(task.status == 'encrypting' || task.status == 'pending') ? _formatSpeed(task.currentSpeed) : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontFamily: isCyberpunk ? 'Courier' : null,
                    ),
                  ),
                ],
              ),
              if (task.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  task.error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (task.status == 'encrypting' || task.status == 'pending')
                    IconButton(
                      icon: const Icon(Icons.pause, size: 20),
                      onPressed: () => EncryptionTaskManager().pauseTask(task.id),
                      tooltip: '暂停',
                    ),
                  if (task.status == 'paused' || task.status == 'failed')
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 20),
                      onPressed: () => EncryptionTaskManager().updateTaskStatus(task.id, 'pending'),
                      tooltip: '继续',
                    ),
                  if (task.status != 'completed')
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => EncryptionTaskManager().removeTask(task.id),
                      tooltip: '取消',
                    ),
                ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status, ThemeData theme) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'failed':
        return theme.colorScheme.error;
      case 'encrypting':
        return theme.colorScheme.primary;
      case 'paused':
        return Colors.orange;
      case 'pending':
      default:
        return theme.colorScheme.onSurface.withOpacity(0.5);
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'completed':
        return '完成';
      case 'failed':
        return '失败';
      case 'encrypting':
        return '加密中';
      case 'paused':
        return '已暂停';
      case 'pending':
      default:
        return '等待中';
    }
  }
}
