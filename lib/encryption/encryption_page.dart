import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'services/vault_key_rotation_service.dart';
import 'widgets/encryption_progress_panel.dart';

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

enum _LegacyUpgradeChoice {
  later,
  upgradeNoReencrypt,
  upgradeAndReencrypt,
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

  String _generateRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(values);
  }

  Future<_LegacyUpgradeChoice> _askLegacyUpgradeChoice(VaultConfig config) async {
    final result = await showDialog<_LegacyUpgradeChoice>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('升级加密方式'),
          content: Text('检测到 ${config.name} 使用旧版加密结构，是否升级到最新版？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_LegacyUpgradeChoice.later),
              child: const Text('稍后再说'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_LegacyUpgradeChoice.upgradeAndReencrypt),
              child: const Text('升级并重新加密'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_LegacyUpgradeChoice.upgradeNoReencrypt),
              child: const Text('立即升级'),
            ),
          ],
        );
      },
    );
    return result ?? _LegacyUpgradeChoice.later;
  }

  Future<VaultConfig> _writeV2ConfigFromDek({
    required String vaultDirectoryPath,
    required VaultConfig baseConfig,
    required String password,
    required Uint8List dek,
  }) async {
    final salt = _generateRandomString(16);
    final nonce = _generateRandomString(12);
    final wrappedDekNonce = _generateRandomString(12);

    final validationCiphertext = await CryptoUtils.computeValidationCiphertextAsync(
      password: password,
      saltBase64: salt,
      kdfType: baseConfig.kdf,
      kdfParams: baseConfig.kdfParams,
      nonceBase64: nonce,
      algorithm: baseConfig.algorithm,
    );

    final kek = await CryptoUtils.deriveKeyAsync(
      password: password,
      saltBase64: salt,
      kdfType: baseConfig.kdf,
      kdfParams: baseConfig.kdfParams,
    );

    final wrappedDekCipher = CryptoUtils.encrypt(
      key: kek,
      nonce: base64Url.decode(wrappedDekNonce),
      plaintext: dek,
      algorithm: baseConfig.algorithm,
    );

    final newConfig = VaultConfig(
      version: 2,
      name: baseConfig.name,
      algorithm: baseConfig.algorithm,
      kdf: baseConfig.kdf,
      kdfParams: baseConfig.kdfParams,
      encryptFilename: baseConfig.encryptFilename,
      salt: salt,
      nonce: nonce,
      validationCiphertext: validationCiphertext,
      wrappedDekNonce: wrappedDekNonce,
      wrappedDekCiphertext: base64Encode(wrappedDekCipher),
    );

    final configFile = File('$vaultDirectoryPath/vault_config.json');
    await configFile.writeAsString(jsonEncode(newConfig.toJson()));

    return newConfig;
  }

  Future<VaultConfig> _upgradeLegacyVaultNoReencrypt({
    required String vaultDirectoryPath,
    required VaultConfig oldConfig,
    required String password,
    required Uint8List oldMasterKey,
  }) async {
    return _writeV2ConfigFromDek(
      vaultDirectoryPath: vaultDirectoryPath,
      baseConfig: oldConfig,
      password: password,
      dek: oldMasterKey,
    );
  }

  Future<void> _showUnlockDialog(_VaultItem item) async {
    if (item.config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置文件无效或不存在，无法解锁')),
      );
      return;
    }

    final passwordController = TextEditingController();
    bool isUnlocking = false;

    try {
      await showDialog(
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
                              String padBase64Url(String input) {
                                final pad = (4 - input.length % 4) % 4;
                                return input + List.filled(pad, '=').join();
                              }

                              final kek = await CryptoUtils.deriveKeyAsync(
                                password: pwd,
                                saltBase64: config.salt,
                                kdfType: config.kdf,
                                kdfParams: config.kdfParams,
                              );

                              Uint8List masterKey;
                              final isV2 = config.version >= 2 &&
                                  config.wrappedDekNonce != null &&
                                  config.wrappedDekCiphertext != null;

                              if (isV2) {
                                final wrappedDekNonceBytes = base64Url.decode(padBase64Url(config.wrappedDekNonce!));
                                final wrappedDekCipherBytes = base64Decode(config.wrappedDekCiphertext!);
                                masterKey = CryptoUtils.decrypt(
                                  key: kek,
                                  nonce: wrappedDekNonceBytes,
                                  ciphertext: wrappedDekCipherBytes,
                                  algorithm: config.algorithm,
                                );
                                if (masterKey.length != 32) {
                                  throw Exception('Invalid DEK length');
                                }
                              } else {
                                final nonceBytes = base64Url.decode(padBase64Url(config.nonce));
                                final ciphertextBytes = base64Decode(config.validationCiphertext);

                                final decryptedBytes = CryptoUtils.decrypt(
                                  key: kek,
                                  nonce: nonceBytes,
                                  ciphertext: ciphertextBytes,
                                  algorithm: config.algorithm,
                                );

                                final decryptedString = utf8.decode(decryptedBytes);
                                if (decryptedString != 'vault_magic_encrypted') {
                                  throw Exception('Invalid magic string');
                                }
                                masterKey = kek;
                              }

                              if (mounted) {
                                Navigator.of(context).pop();

                                VaultConfig configToUse = config;
                                if (!isV2) {
                                  final choice = await _askLegacyUpgradeChoice(config);
                                  if (choice == _LegacyUpgradeChoice.upgradeNoReencrypt) {
                                    configToUse = await _upgradeLegacyVaultNoReencrypt(
                                      vaultDirectoryPath: item.path,
                                      oldConfig: config,
                                      password: pwd,
                                      oldMasterKey: masterKey,
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('已升级到最新版加密结构')),
                                      );
                                    }
                                  } else if (choice == _LegacyUpgradeChoice.upgradeAndReencrypt) {
                                    final random = Random.secure();
                                    final newDek = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
                                    await VaultKeyRotationService().rotateInPlace(
                                      vaultDirectoryPath: item.path,
                                      oldMasterKey: masterKey,
                                      newMasterKey: newDek,
                                      encryptFilename: config.encryptFilename,
                                    );
                                    configToUse = await _writeV2ConfigFromDek(
                                      vaultDirectoryPath: item.path,
                                      baseConfig: config,
                                      password: pwd,
                                      dek: newDek,
                                    );
                                    masterKey = newDek;
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('已升级并完成重新加密')),
                                      );
                                    }
                                  }
                                }
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => VaultExplorerPage(
                                      vaultConfig: configToUse,
                                      masterKey: masterKey,
                                      vaultDirectoryPath: item.path,
                                    ),
                                  ),
                                );
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
    } finally {
      passwordController.dispose();
    }
  }

  Future<void> _showVaultActions(_VaultItem item, int index) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('修改密码'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showChangePasswordDialog(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('移除保险箱'),
                onTap: () {
                  Navigator.pop(context);
                  _removeVault(index);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showChangePasswordDialog(_VaultItem item) async {
    final config = item.config;
    if (config == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置文件无效或不存在')),
        );
      }
      return;
    }

    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool reencrypt = false;
    bool working = false;

    Future<bool> confirmReencrypt() async {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('确认重新加密'),
            content: const Text('重新加密会生成新的系统密钥，并对所有文件重新加密。请确认继续。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续'),
              ),
            ],
          );
        },
      );
      return result ?? false;
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text('修改密码'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: oldCtrl,
                        decoration: const InputDecoration(labelText: '原密码'),
                        obscureText: true,
                        enabled: !working,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newCtrl,
                        decoration: const InputDecoration(labelText: '新密码'),
                        obscureText: true,
                        enabled: !working,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmCtrl,
                        decoration: const InputDecoration(labelText: '确认新密码'),
                        obscureText: true,
                        enabled: !working,
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: reencrypt,
                        onChanged: working
                            ? null
                            : (v) {
                                setStateDialog(() {
                                  reencrypt = v ?? false;
                                });
                              },
                        title: const Text('重新加密（生成新密钥）'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (working) ...[
                        const SizedBox(height: 12),
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: working
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                          },
                    child: const Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: working
                        ? null
                        : () async {
                            final oldPwd = oldCtrl.text;
                            final newPwd = newCtrl.text;
                            final confirmPwd = confirmCtrl.text;
                            if (oldPwd.isEmpty || newPwd.isEmpty) return;
                            if (newPwd != confirmPwd) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('两次新密码不一致')),
                              );
                              return;
                            }

                            if (reencrypt) {
                              final ok = await confirmReencrypt();
                              if (!ok) return;
                            }

                            setStateDialog(() => working = true);
                            try {
                              String padBase64Url(String input) {
                                final pad = (4 - input.length % 4) % 4;
                                return input + List.filled(pad, '=').join();
                              }

                              Uint8List oldDek;
                              final isV2 = config.version >= 2 &&
                                  config.wrappedDekNonce != null &&
                                  config.wrappedDekCiphertext != null;

                              if (isV2) {
                                final kekOld = await CryptoUtils.deriveKeyAsync(
                                  password: oldPwd,
                                  saltBase64: config.salt,
                                  kdfType: config.kdf,
                                  kdfParams: config.kdfParams,
                                );
                                oldDek = CryptoUtils.decrypt(
                                  key: kekOld,
                                  nonce: base64Url.decode(padBase64Url(config.wrappedDekNonce!)),
                                  ciphertext: base64Decode(config.wrappedDekCiphertext!),
                                  algorithm: config.algorithm,
                                );
                                if (oldDek.length != 32) {
                                  throw Exception('Invalid DEK length');
                                }
                              } else {
                                final derivedOld = await CryptoUtils.deriveKeyAsync(
                                  password: oldPwd,
                                  saltBase64: config.salt,
                                  kdfType: config.kdf,
                                  kdfParams: config.kdfParams,
                                );
                                final decrypted = CryptoUtils.decrypt(
                                  key: derivedOld,
                                  nonce: base64Url.decode(padBase64Url(config.nonce)),
                                  ciphertext: base64Decode(config.validationCiphertext),
                                  algorithm: config.algorithm,
                                );
                                if (utf8.decode(decrypted) != 'vault_magic_encrypted') {
                                  throw Exception('Incorrect password');
                                }
                                oldDek = derivedOld;
                              }

                              Uint8List dekToUse = oldDek;
                              if (reencrypt) {
                                final random = Random.secure();
                                final newDek = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
                                await VaultKeyRotationService().rotateInPlace(
                                  vaultDirectoryPath: item.path,
                                  oldMasterKey: oldDek,
                                  newMasterKey: newDek,
                                  encryptFilename: config.encryptFilename,
                                );
                                dekToUse = newDek;
                              }

                              await _writeV2ConfigFromDek(
                                vaultDirectoryPath: item.path,
                                baseConfig: config,
                                password: newPwd,
                                dek: dekToUse,
                              );

                              if (mounted) {
                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('密码修改成功')),
                                );
                                _loadVaults();
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('密码错误或配置损坏')),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setStateDialog(() => working = false);
                              }
                            }
                          },
                    child: const Text('修改'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      oldCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    }
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

  void _showAddVaultBottomSheet() {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark && 
                        theme.colorScheme.primary.value == 0xFF00E5FF;

    showModalBottomSheet(
      context: context,
      backgroundColor: isCyberpunk ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface,
      shape: isCyberpunk
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xFF00E5FF), width: 1.0),
            )
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCyberpunk)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF00E5FF), width: 1.0)),
                  ),
                  child: Text(
                    '添加保险箱 (ADD VAULT)'.toUpperCase(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '添加保险箱',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ListTile(
                leading: Icon(Icons.create_new_folder_outlined, 
                  color: isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary),
                title: const Text('创建加密文件夹'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFolderAndConfig();
                },
              ),
              ListTile(
                leading: Icon(Icons.drive_folder_upload_outlined,
                  color: isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary),
                title: const Text('导入现有保险箱'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFolderAndConfig();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
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
              showEncryptionProgressPanel(context);
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
                        onLongPress: hasConfig ? () => _showVaultActions(item, index) : null,
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
        onPressed: _showAddVaultBottomSheet,
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}
