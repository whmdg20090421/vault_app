import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../encryption/models/vault_config.dart';
import '../encryption/utils/crypto_utils.dart';
import '../models/sync_task.dart';
import '../services/sync_storage_service.dart';
import '../vfs/virtual_file_system.dart';
import '../vfs/local_vfs.dart';
import '../vfs/encrypted_vfs.dart';
import '../vfs/standard_vfs.dart';
import 'webdav_config.dart';
import 'webdav_storage.dart';
import 'webdav_new/webdav_client.dart';
import 'webdav_new/webdav_service.dart';
import '../widgets/vfs_folder_picker_dialog.dart';
import 'webdav_browser_page.dart';


class SyncConfigPage extends StatefulWidget {
  const SyncConfigPage({super.key});

  @override
  State<SyncConfigPage> createState() => _SyncConfigPageState();
}

class _VaultItem {
  final String path;
  final VaultConfig? config;
  _VaultItem(this.path, this.config);
}

class _SyncConfigPageState extends State<SyncConfigPage> {
  int _currentStep = 0;

  // Step 1: Vault
  List<_VaultItem> _vaults = [];
  bool _loadingVaults = true;
  _VaultItem? _selectedVault;
  Uint8List? _masterKey;

  // Step 2: Local Folder
  VirtualFileSystem? _localVfs;
  String _localPath = '/';
  String _selectedLocalFolder = '/';

  // Step 3: WebDAV
  List<WebDavConfig> _webDavConfigs = [];
  bool _loadingWebDavConfigs = true;
  WebDavConfig? _selectedWebDav;
  VirtualFileSystem? _cloudVfs;
  String _cloudPath = '/';
  String _selectedCloudFolder = '/';

  // Step 4: Options
  SyncDirection _direction = SyncDirection.cloudToLocal;
  SyncStrategy _strategy = SyncStrategy.skip;

  @override
  void initState() {
    super.initState();
    _loadVaults();
    _loadWebDavConfigs();
  }

  Future<void> _loadVaults() async {
    if (mounted) setState(() => _loadingVaults = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList('vault_paths') ?? [];
      final List<_VaultItem> loaded = [];

      for (final path in paths) {
        final configFile = File('\$path/vault_config.json');
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
      if (mounted) setState(() => _vaults = loaded);
    } finally {
      if (mounted) setState(() => _loadingVaults = false);
    }
  }

  Future<void> _loadWebDavConfigs() async {
    if (mounted) setState(() => _loadingWebDavConfigs = true);
    try {
      final repo = WebDavConfigRepository();
      final configs = await repo.listConfigs();
      if (mounted) setState(() => _webDavConfigs = configs);
    } finally {
      if (mounted) setState(() => _loadingWebDavConfigs = false);
    }
  }

  // --- Step 1 Actions ---
  void _unlockVault(_VaultItem item) async {
    if (item.config == null) return;
    final pwdCtrl = TextEditingController();
    bool unlocking = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('解锁保险箱'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('正在解锁: \${item.config!.name}'),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '请输入密码'),
                enabled: !unlocking,
              ),
              if (unlocking) const Padding(padding: EdgeInsets.only(top: 16), child: CircularProgressIndicator()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: unlocking ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: unlocking ? null : () async {
                final pwd = pwdCtrl.text;
                if (pwd.isEmpty) return;
                setDialogState(() => unlocking = true);
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
                    if (utf8.decode(decryptedBytes) != 'vault_magic_encrypted') {
                      throw Exception('Invalid magic');
                    }
                    masterKey = kek;
                  }

                    Navigator.pop(ctx);
                  _onVaultUnlocked(item, masterKey);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码错误')));
                } finally {
                  if (mounted) setDialogState(() => unlocking = false);
                }
              },
              child: const Text('解锁'),
            ),
          ],
        ),
      ),
    );
    pwdCtrl.dispose();
  }

  void _onVaultUnlocked(_VaultItem item, Uint8List key) async {
    setState(() {
      _selectedVault = item;
      _masterKey = key;
    });
    
    // Init Local VFS
    final localVfs = LocalVfs(rootPath: item.path);
    if (item.config!.encryptFilename) {
      final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: key, encryptFilename: true);
      await encryptedVfs.initEncryptedDomain('/');
      _localVfs = encryptedVfs;
    } else {
      // Create EncryptedVfs with encryptFilename: false, so contents are still encrypted if needed
      final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: key, encryptFilename: false);
      await encryptedVfs.initEncryptedDomain('/');
      _localVfs = encryptedVfs;
    }
    
    _localPath = '/';
    _selectedLocalFolder = '/';
    
    if (mounted) {
      setState(() {
        _currentStep = 1;
      });
    }
  }

  // --- Step 2 Actions ---

  // --- Step 3 Actions ---
  Future<void> _initCloudVfs(WebDavConfig config) async {
    setState(() {
      _selectedWebDav = config;
    });
    try {
      final repo = WebDavConfigRepository();
      final password = await repo.readPassword(config.id) ?? '';

      final client = WebDavClient(
        baseUrl: config.url,
        username: config.username,
        password: password,
      );
      final service = WebDavService(client);
      _cloudVfs = StandardVfs(service);

      _cloudPath = '/';
      _selectedCloudFolder = '/';
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接WebDAV失败：${e.toString()}')));
    }
  }

  Future<void> _autoMatchCloudFolder() async {
    if (_cloudVfs == null) return;
    try {
      // 尝试访问与本地相同的路径
      String targetPath = _selectedLocalFolder;
      if (!targetPath.endsWith('/')) targetPath += '/';
      
      // 检查该目录是否存在
      try {
        await _cloudVfs!.list(targetPath);
        // 成功，说明存在
      } catch (e) {
        // 不存在，尝试创建
        await _cloudVfs!.mkdir(targetPath);
      }
      
      if (mounted) {
        setState(() {
          _cloudPath = targetPath;
          _selectedCloudFolder = targetPath;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自动匹配/创建成功')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('自动匹配失败：${e.toString()}')));
    }
  }

  // --- Step 4 Actions ---
  Future<void> _saveTask() async {
    if (_selectedVault == null || _selectedWebDav == null) return;

    final task = SyncTask(
        id: Uuid().v4(),
      direction: _direction,
      strategy: _strategy,
      items: [],
      createdAt: DateTime.now(),
      localVaultPath: _selectedVault!.path,
      cloudWebDavId: _selectedWebDav!.id,
      localFolderPath: _selectedLocalFolder,
      cloudFolderPath: _selectedCloudFolder,
    );

    final svc = SyncStorageService();
    await svc.saveTask(task);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同步任务创建成功')));
      Navigator.of(context).pop();
    }
  }

  // --- Builders ---
  Widget _buildVaultSelection() {
    if (_loadingVaults) return const Center(child: CircularProgressIndicator());
    if (_vaults.isEmpty) return const Text('没有可用的保险箱');
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _vaults.length,
      itemBuilder: (ctx, i) {
        final item = _vaults[i];
        final isSelected = _selectedVault?.path == item.path;
        return ListTile(
          leading: Icon(item.config != null ? Icons.lock : Icons.error, color: isSelected ? Colors.blue : null),
          title: Text(item.config?.name ?? '未配置'),
          subtitle: Text(item.path),
          selected: isSelected,
          onTap: () => _unlockVault(item),
        );
      },
    );
  }

  Widget _buildLocalFolderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已选路径: $_selectedLocalFolder', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text('选择本地文件夹'),
          onPressed: () async {
            if (_localVfs == null) return;
            final folder = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VfsFolderPickerDialog(
                  vfs: _localVfs!,
                  title: '选择本地文件夹',
                ),
              ),
            );
            if (folder != null && folder is String) {
              setState(() {
                _selectedLocalFolder = folder;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            setState(() => _currentStep = 2);
          },
          child: const Text('确认并下一步'),
        ),
      ],
    );
  }

  Widget _buildCloudFolderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_webDavConfigs.isEmpty) const Text('没有可用的 WebDAV 配置'),
        if (_webDavConfigs.isNotEmpty)
          DropdownButton<WebDavConfig>(
            value: _selectedWebDav,
            hint: const Text('选择 WebDAV 云盘'),
            dropdownColor: Theme.of(context).colorScheme.surface,
            isExpanded: true,
            items: _webDavConfigs.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
            onChanged: (val) {
              if (val != null) _initCloudVfs(val);
            },
          ),
        const SizedBox(height: 16),
        if (_cloudVfs != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('已选云端路径: $_selectedCloudFolder', style: const TextStyle(fontWeight: FontWeight.bold))),
              TextButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('自动匹配'),
                onPressed: _autoMatchCloudFolder,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.cloud_queue),
            label: const Text('选择云端文件夹'),
            onPressed: () async {
              final folder = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WebDavBrowserPage(
                    config: _selectedWebDav!,
                    isPickingFolder: true,
                  ),
                ),
              );
              if (folder != null && folder is String) {
                setState(() {
                  _selectedCloudFolder = folder;
                  _cloudPath = folder;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() => _currentStep = 3);
            },
            child: const Text('确认并下一步'),
          ),
        ],
      ],
    );
  }

  Widget _buildOptionsSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('同步方向:', style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<SyncDirection>(
          title: const Text('云端 -> 本地 (Cloud to Local)'),
          value: SyncDirection.cloudToLocal,
          groupValue: _direction,
          onChanged: (v) => setState(() => _direction = v!),
        ),
        RadioListTile<SyncDirection>(
          title: const Text('本地 -> 云端 (Local to Cloud)'),
          value: SyncDirection.localToCloud,
          groupValue: _direction,
          onChanged: (v) => setState(() => _direction = v!),
        ),
        RadioListTile<SyncDirection>(
          title: const Text('双向同步 (Two-Way Sync)'),
          value: SyncDirection.twoWay,
          groupValue: _direction,
          onChanged: (v) => setState(() => _direction = v!),
        ),
        const Divider(),
        const Text('冲突策略:', style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<SyncStrategy>(
          title: const Text('跳过 (Skip) - 保留现有文件'),
          value: SyncStrategy.skip,
          groupValue: _strategy,
          onChanged: (v) => setState(() => _strategy = v!),
        ),
        RadioListTile<SyncStrategy>(
          title: const Text('覆盖 (Overwrite) - 强制覆盖'),
          value: SyncStrategy.overwrite,
          groupValue: _strategy,
          onChanged: (v) => setState(() => _strategy = v!),
        ),
        RadioListTile<SyncStrategy>(
          title: const Text('合并 (Merge) - 按最新修改时间'),
          value: SyncStrategy.merge,
          groupValue: _strategy,
          onChanged: (v) => setState(() => _strategy = v!),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saveTask,
            child: const Text('创建同步任务'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建同步任务'),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepTapped: (step) {
          if (step == 1 && _selectedVault == null) return;
          if (step == 2 && _selectedVault == null) return;
          if (step == 3 && _selectedWebDav == null) return;
          setState(() => _currentStep = step);
        },
        controlsBuilder: (context, details) => const SizedBox.shrink(),
        steps: [
          Step(
            title: const Text('选择保险箱'),
            content: _buildVaultSelection(),
            isActive: _currentStep >= 0,
            state: _selectedVault != null ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('选择本地文件夹'),
            content: _buildLocalFolderSelection(),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('选择云端文件夹'),
            content: _buildCloudFolderSelection(),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('同步选项'),
            content: _buildOptionsSelection(),
            isActive: _currentStep >= 3,
          ),
        ],
      ),
    );
  }
}
