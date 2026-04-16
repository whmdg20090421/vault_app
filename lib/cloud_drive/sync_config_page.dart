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
import 'webdav_client_service.dart';

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
  List<VfsNode> _localDirs = [];
  bool _loadingLocalDirs = false;
  String _selectedLocalFolder = '/';

  // Step 3: WebDAV
  List<WebDavConfig> _webDavConfigs = [];
  bool _loadingWebDavConfigs = true;
  WebDavConfig? _selectedWebDav;
  VirtualFileSystem? _cloudVfs;
  String _cloudPath = '/';
  List<VfsNode> _cloudDirs = [];
  bool _loadingCloudDirs = false;
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
    setState(() => _loadingVaults = true);
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
    setState(() => _loadingWebDavConfigs = true);
    try {
      final repo = WebDavConfigRepository();
      final configs = await repo.listConfigs();
      if (mounted) setState(() => _webDavConfigs = configs);
    } finally {
      if (mounted) setState(() => _loadingWebDavConfigs = false);
    }
  }

  // --- Step 1 Actions ---
  void _unlockVault(_VaultItem item) {
    if (item.config == null) return;
    final pwdCtrl = TextEditingController();
    bool unlocking = false;

    showDialog(
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
                  final derivedKey = await CryptoUtils.deriveKeyAsync(
                    password: pwd,
                    saltBase64: config.salt,
                    kdfType: config.kdf,
                    kdfParams: config.kdfParams,
                  );
                  final nonceBytes = base64Url.decode(config.nonce);
                  final ciphertextBytes = base64Decode(config.validationCiphertext);
                  final decryptedBytes = CryptoUtils.decrypt(
                    key: derivedKey,
                    nonce: nonceBytes,
                    ciphertext: ciphertextBytes,
                    algorithm: config.algorithm,
                  );
                  if (utf8.decode(decryptedBytes) == 'vault_magic_encrypted') {
                    Navigator.pop(ctx);
                    _onVaultUnlocked(item, derivedKey);
                  } else {
                    throw Exception('Invalid magic');
                  }
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
  }

  void _onVaultUnlocked(_VaultItem item, Uint8List key) async {
    setState(() {
      _selectedVault = item;
      _masterKey = key;
    });
    
    // Init Local VFS
    final localVfs = LocalVfs(rootPath: item.path);
    if (item.config!.encryptFilename) {
      final encryptedVfs = EncryptedVfs(baseVfs: localVfs, masterKey: key);
      await encryptedVfs.initEncryptedDomain('/');
      _localVfs = encryptedVfs;
    } else {
      _localVfs = localVfs;
    }
    
    _localPath = '/';
    _selectedLocalFolder = '/';
    await _loadLocalDirs();
    
    setState(() {
      _currentStep = 1;
    });
  }

  // --- Step 2 Actions ---
  Future<void> _loadLocalDirs() async {
    if (_localVfs == null) return;
    setState(() => _loadingLocalDirs = true);
    try {
      final files = await _localVfs!.list(_localPath);
      final dirs = files.where((f) => f.isDirectory).toList();
      dirs.sort((a, b) => a.name.compareTo(b.name));
      if (mounted) setState(() => _localDirs = dirs);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载目录失败: \$e')));
    } finally {
      if (mounted) setState(() => _loadingLocalDirs = false);
    }
  }

  void _navigateLocal(String name) {
    setState(() {
      String newPath = '\$_localPath\$name/'.replaceAll('//', '/');
      _localPath = newPath;
      _selectedLocalFolder = newPath;
    });
    _loadLocalDirs();
  }

  void _navigateLocalUp() {
    if (_localPath == '/') return;
    setState(() {
      String p = _localPath.substring(0, _localPath.length - 1);
      int lastSlash = p.lastIndexOf('/');
      _localPath = lastSlash >= 0 ? p.substring(0, lastSlash + 1) : '/';
      _selectedLocalFolder = _localPath;
    });
    _loadLocalDirs();
  }

  // --- Step 3 Actions ---
  Future<void> _initCloudVfs(WebDavConfig config) async {
    setState(() {
      _selectedWebDav = config;
      _loadingCloudDirs = true;
    });
    try {
      final repo = WebDavConfigRepository();
      final pwd = await repo.readPassword(config.id);
      final client = WebDavClientService(
        url: config.url,
        username: config.username,
        password: pwd ?? '',
      );
      _cloudVfs = StandardVfs(client: client);
      _cloudPath = '/';
      _selectedCloudFolder = '/';
      await _loadCloudDirs();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接WebDAV失败: \$e')));
    } finally {
      if (mounted) setState(() => _loadingCloudDirs = false);
    }
  }

  Future<void> _loadCloudDirs() async {
    if (_cloudVfs == null) return;
    setState(() => _loadingCloudDirs = true);
    try {
      final files = await _cloudVfs!.list(_cloudPath);
      final dirs = files.where((f) => f.isDirectory).toList();
      dirs.sort((a, b) => a.name.compareTo(b.name));
      if (mounted) setState(() => _cloudDirs = dirs);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载云端目录失败: \$e')));
    } finally {
      if (mounted) setState(() => _loadingCloudDirs = false);
    }
  }

  void _navigateCloud(String name) {
    setState(() {
      String newPath = '\$_cloudPath\$name/'.replaceAll('//', '/');
      _cloudPath = newPath;
      _selectedCloudFolder = newPath;
    });
    _loadCloudDirs();
  }

  void _navigateCloudUp() {
    if (_cloudPath == '/') return;
    setState(() {
      String p = _cloudPath.substring(0, _cloudPath.length - 1);
      int lastSlash = p.lastIndexOf('/');
      _cloudPath = lastSlash >= 0 ? p.substring(0, lastSlash + 1) : '/';
      _selectedCloudFolder = _cloudPath;
    });
    _loadCloudDirs();
  }

  Future<void> _autoMatchCloudFolder() async {
    if (_cloudVfs == null) return;
    setState(() => _loadingCloudDirs = true);
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
        await _loadCloudDirs();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自动匹配/创建成功')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('自动匹配失败: \$e')));
    } finally {
      if (mounted) setState(() => _loadingCloudDirs = false);
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
        Text('当前路径: \$_localPath', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
          child: _loadingLocalDirs
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  if (_localPath != '/')
                    ListTile(
                      leading: const Icon(Icons.arrow_upward),
                      title: const Text('.. (返回上级)'),
                      onTap: _navigateLocalUp,
                    ),
                  ..._localDirs.map((dir) => ListTile(
                    leading: const Icon(Icons.folder, color: Colors.blue),
                    title: Text(dir.name),
                    onTap: () => _navigateLocal(dir.name),
                  )),
                ],
              ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {
            setState(() => _currentStep = 2);
          },
          child: const Text('确认选择该本地文件夹'),
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
              Expanded(child: Text('云端路径: \$_cloudPath', style: const TextStyle(fontWeight: FontWeight.bold))),
              TextButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('自动匹配'),
                onPressed: _autoMatchCloudFolder,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 200,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
            child: _loadingCloudDirs
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    if (_cloudPath != '/')
                      ListTile(
                        leading: const Icon(Icons.arrow_upward),
                        title: const Text('.. (返回上级)'),
                        onTap: _navigateCloudUp,
                      ),
                    ..._cloudDirs.map((dir) => ListTile(
                      leading: const Icon(Icons.folder, color: Colors.orange),
                      title: Text(dir.name),
                      onTap: () => _navigateCloud(dir.name),
                    )),
                  ],
                ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              setState(() => _currentStep = 3);
            },
            child: const Text('确认选择该云端文件夹'),
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
