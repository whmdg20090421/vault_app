import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/vault_config.dart';
import 'utils/crypto_utils.dart';
import 'vault_config_page.dart';
import 'vault_explorer_page.dart';

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
    setState(() {
      _isLoading = true;
    });

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

      setState(() {
        _vaults = loaded;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
                            final derivedKey = CryptoUtils.deriveKey(
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
    );
  }

  Future<void> _removeVault(int index) async {
    final path = _vaults[index].path;
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('vault_paths') ?? [];
    paths.remove(path);
    await prefs.setStringList('vault_paths', paths);

    setState(() {
      _vaults.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark && 
                        theme.colorScheme.secondary.value == 0xFF00F0FF;

    return Scaffold(
      appBar: AppBar(
        title: const Text('加密保险箱 (Vaults)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: '加密进度',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isCyberpunk 
                            ? BorderSide(color: theme.colorScheme.secondary.withOpacity(0.5))
                            : BorderSide.none,
                      ),
                      color: isCyberpunk ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface,
                      child: ListTile(
                        onTap: () => _showUnlockDialog(item),
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
                        theme.colorScheme.secondary.value == 0xFF00F0FF;

    final mockData = [
      {
        'root': '内部存储 (Internal Storage)',
        'icon': Icons.smartphone,
        'folders': [
          {'name': 'DCIM/Camera', 'encrypted': 5, 'total': 10},
          {'name': 'Pictures/Screenshots', 'encrypted': 12, 'total': 12},
          {'name': 'Download', 'encrypted': 0, 'total': 8},
        ]
      },
      {
        'root': 'SD卡 (SD Card)',
        'icon': Icons.sd_storage,
        'folders': [
          {'name': 'Movies', 'encrypted': 45, 'total': 100},
          {'name': 'Music', 'encrypted': 2, 'total': 2},
        ]
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: isCyberpunk
            ? Border(top: BorderSide(color: theme.colorScheme.secondary, width: 2))
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
            child: ListView.builder(
              controller: scrollController,
              itemCount: mockData.length,
              itemBuilder: (context, index) {
                final rootData = mockData[index];
                final rootName = rootData['root'] as String;
                final rootIcon = rootData['icon'] as IconData;
                final folders = rootData['folders'] as List<Map<String, dynamic>>;

                return ExpansionTile(
                  leading: Icon(rootIcon, color: theme.colorScheme.primary),
                  title: Text(
                    rootName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  initiallyExpanded: index == 0,
                  children: folders.map((folder) {
                    final folderName = folder['name'] as String;
                    final encrypted = folder['encrypted'] as int;
                    final total = folder['total'] as int;
                    final progress = total > 0 ? encrypted / total : 0.0;
                    final progressPercent = (progress * 100).toStringAsFixed(1);

                    return Padding(
                      padding: const EdgeInsets.only(left: 48, right: 24, bottom: 16, top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  folderName,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 1,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '已加密 $encrypted / $total',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '$progressPercent%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
