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
        // 检查是否已有 vault_config.json
        final configFile = File('$result/vault_config.json');
        if (await configFile.exists()) {
          final prefs = await SharedPreferences.getInstance();
          final vaultPaths = prefs.getStringList('vault_paths') ?? [];
          if (!vaultPaths.contains(result)) {
            vaultPaths.add(result);
            await prefs.setStringList('vault_paths', vaultPaths);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('检测到已有保险箱，已自动导入配置')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('该保险箱已存在于列表中')),
              );
            }
          }
          _loadVaults();
          return;
        }

        // 跳转到配置页面创建新保险箱
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

class EncryptionProgressPanel extends StatelessWidget {
  final ScrollController scrollController;

  const EncryptionProgressPanel({super.key, required this.scrollController});

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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '加密任务进度',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isCyberpunk ? theme.colorScheme.secondary : null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: ListenableBuilder(
              listenable: EncryptionTaskManager(),
              builder: (context, child) {
                final tasks = EncryptionTaskManager().tasks;
                if (tasks.isEmpty) {
                  return SingleChildScrollView(
                    controller: scrollController,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 32),
                            Icon(
                              Icons.inbox_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurface.withOpacity(0.2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '暂无数据',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _TaskCard(task: task, isCyberpunk: isCyberpunk, theme: theme);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatefulWidget {
  final EncryptionTask task;
  final bool isCyberpunk;
  final ThemeData theme;
  final int depth;

  const _TaskCard({
    required this.task,
    required this.isCyberpunk,
    required this.theme,
    this.depth = 0,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _isExpanded = false;

  void _resumeTask(BuildContext context) async {
    final args = widget.task.taskArgs!;
    final vaultDir = args['vaultDirectoryPath'] as String;
    final configFile = File('$vaultDir/vault_config.json');
    if (!await configFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vault config not found!')));
      return;
    }
    final configStr = await configFile.readAsString();
    final config = VaultConfig.fromJson(jsonDecode(configStr));

    String? password;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final pwdController = TextEditingController();
        bool isUnlocking = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('解锁保险箱 (Unlock)'),
            content: TextField(
              controller: pwdController,
              decoration: const InputDecoration(labelText: '密码 (Password)'),
              obscureText: true,
              enabled: !isUnlocking,
            ),
            actions: [
              TextButton(
                onPressed: isUnlocking ? null : () => Navigator.pop(context),
                child: const Text('取消 (Cancel)'),
              ),
              ElevatedButton(
                onPressed: isUnlocking
                    ? null
                    : () async {
                        setStateDialog(() => isUnlocking = true);
                        try {
                            final derivedKey = await CryptoUtils.deriveKeyAsync(
                              password: pwdController.text,
                              saltBase64: config.salt,
                              kdfType: config.kdf,
                              kdfParams: config.kdfParams,
                            );
                            
                            final ciphertextBytes = base64Decode(config.validationCiphertext);
                            final nonceBytes = base64Url.decode(config.nonce);
                            
                            final decryptedBytes = CryptoUtils.decrypt(
                              key: derivedKey,
                              nonce: nonceBytes,
                              ciphertext: ciphertextBytes,
                              algorithm: config.algorithm,
                            );

                            final decryptedString = utf8.decode(decryptedBytes);
                            if (decryptedString != 'vault_magic_encrypted') {
                              throw Exception('Wrong password');
                            }
                            password = pwdController.text;
                            Navigator.pop(context);
                          } catch (e) {
                            setStateDialog(() => isUnlocking = false);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('错误 (Error): 密码错误或解密失败')));
                          }
                      },
                child: isUnlocking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('确定 (OK)'),
              ),
            ],
          ),
        );
      },
    );

    if (password == null) return;

    final masterKey = await CryptoUtils.deriveKeyAsync(
      password: password!,
      saltBase64: config.salt,
      kdfType: config.kdf,
      kdfParams: config.kdfParams,
    );

    EncryptionTaskManager().updateTaskStatus(widget.task.id, 'encrypting', error: null);

    final receivePort = ReceivePort();
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
            isDirectory: childMap['isDirectory'] as bool? ?? false,
            totalBytes: childMap['totalBytes'] as int,
          );
          EncryptionTaskManager().addChild(tid, child);
        } else if (type == 'tree') {
          final treeMap = message['tree'] as Map<String, dynamic>;
          EncryptionTaskManager().updateTaskTree(tid, treeMap);
        } else if (type == 'done') {
          EncryptionTaskManager().updateTaskStatus(tid, 'completed');
          receivePort.close();
        } else if (type == 'error') {
          final error = message['error'] as String;
          EncryptionTaskManager().updateTaskStatus(tid, 'failed', error: error);
          receivePort.close();
        }
      }
    });

    final isolateArgs = Map<String, dynamic>.from(args);
    isolateArgs['sendPort'] = receivePort.sendPort;
    isolateArgs['masterKey'] = masterKey;
    isolateArgs['encryptFilename'] = config.encryptFilename;

    if (args['type'] == 'import_files') {
      final allFiles = (args['files'] as List<dynamic>).map((e) => Map<String, String>.from(e as Map)).toList();
      final List<Map<String, String>> remainingFiles = [];
      
      for (final f in allFiles) {
        final childId = '${widget.task.id}/${p.basename(f['localPath']!)}';
        final childTask = widget.task.children.where((c) => c.id == childId).firstOrNull;
        if (childTask == null || childTask.status != 'completed') {
          remainingFiles.add(f);
        }
      }
      
      if (remainingFiles.isEmpty) {
        EncryptionTaskManager().updateTaskStatus(widget.task.id, 'completed');
        return;
      }
      isolateArgs['files'] = remainingFiles;
      spawnImportFile(isolateArgs).catchError((e) {
        EncryptionTaskManager().updateTaskStatus(widget.task.id, 'failed', error: e.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Isolate启动失败或运行异常: $e')),
          );
        }
      });
    } else if (args['type'] == 'import_folder') {
      final List<String> skipFileIds = [];
      
      void findCompletedFiles(EncryptionTask t) {
        if (!t.isDirectory && t.status == 'completed') {
          skipFileIds.add(t.id);
        }
        for (final c in t.children) {
          findCompletedFiles(c);
        }
      }
      findCompletedFiles(widget.task);
      
      isolateArgs['skipFileIds'] = skipFileIds;
      spawnImportFolder(isolateArgs).catchError((e) {
        EncryptionTaskManager().updateTaskStatus(widget.task.id, 'failed', error: e.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Isolate启动失败或运行异常: $e')),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.task.children.isNotEmpty;
    final padding = EdgeInsets.only(
      left: widget.depth == 0 ? 0 : 16.0,
      bottom: widget.depth == 0 ? 12.0 : 0.0,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasChildren ? () => setState(() => _isExpanded = !_isExpanded) : null,
          child: Padding(
            padding: EdgeInsets.all(widget.depth == 0 ? 16.0 : 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (hasChildren)
                      Icon(
                        _isExpanded ? Icons.folder_open : Icons.folder,
                        size: 20,
                        color: widget.theme.colorScheme.primary,
                      )
                    else if (widget.depth > 0)
                      Icon(Icons.insert_drive_file, size: 16, color: widget.theme.colorScheme.secondary),
                    if (hasChildren || widget.depth > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.task.name,
                        style: TextStyle(
                          fontWeight: widget.depth == 0 ? FontWeight.bold : FontWeight.normal,
                          fontSize: widget.depth == 0 ? 16 : 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildStatusBadge(widget.theme, widget.task.status),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: widget.task.progress,
                  backgroundColor: widget.theme.colorScheme.surfaceContainerHighest,
                  color: _getStatusColor(widget.theme, widget.task.status),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(widget.task.progress * 100).toStringAsFixed(1)}%',
                      style: widget.theme.textTheme.bodySmall,
                    ),
                    Text(
                      '${FormatUtils.formatBytes(widget.task.processedBytes)} / ${FormatUtils.formatBytes(widget.task.totalBytes)}',
                      style: widget.theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ],
                ),
                if (widget.task.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.task.error!,
                    style: widget.theme.textTheme.bodySmall?.copyWith(color: widget.theme.colorScheme.error),
                  ),
                ],
                if (widget.depth == 0 && widget.task.status == 'paused' && widget.task.taskArgs != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () => _resumeTask(context),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('继续加密 (Resume)'),
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasChildren && _isExpanded)
          Column(
            children: widget.task.children.map((child) {
              return _TaskCard(
                task: child,
                isCyberpunk: widget.isCyberpunk,
                theme: widget.theme,
                depth: widget.depth + 1,
              );
            }).toList(),
          ),
      ],
    );

    if (widget.depth == 0) {
      return Padding(
        padding: padding,
        child: Card(
          elevation: widget.isCyberpunk ? 0 : 1,
          shape: widget.isCyberpunk
              ? const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                  side: BorderSide(color: Color(0xFF00E5FF), width: 1.0),
                )
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
          color: widget.isCyberpunk ? widget.theme.colorScheme.surfaceContainer : widget.theme.colorScheme.surface,
          child: content,
        ),
      );
    } else {
      return Padding(
        padding: padding,
        child: content,
      );
    }
  }

  Widget _buildStatusBadge(ThemeData theme, String status) {
    Color color;
    String text;
    switch (status) {
      case 'completed':
        color = theme.colorScheme.primary;
        text = '完成';
        break;
      case 'encrypting':
        color = theme.colorScheme.secondary;
        text = '加密中';
        break;
      case 'paused':
        color = theme.colorScheme.tertiary;
        text = '已暂停';
        break;
      case 'failed':
        color = theme.colorScheme.error;
        text = '失败';
        break;
      default:
        color = theme.colorScheme.outline;
        text = '等待中';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(ThemeData theme, String status) {
    switch (status) {
      case 'completed':
        return theme.colorScheme.primary;
      case 'encrypting':
        return theme.colorScheme.secondary;
      case 'paused':
        return theme.colorScheme.tertiary;
      case 'failed':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.outline;
    }
  }


}
