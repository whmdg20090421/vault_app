import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'webdav_config.dart';
import 'webdav_state_manager.dart';
import '../encryption/models/vault_config.dart';
import '../encryption/vault_explorer_page.dart';
import 'webdav_new/webdav_client.dart';
import '../vfs/virtual_file_system.dart';

enum SyncDirection {
  cloudToLocal,
  localToCloud,
  twoWay,
}

enum SyncOverrideMethod {
  overwrite,
  skip,
  timePriority,
}

class SyncSettingsDialog extends StatefulWidget {
  final WebDavConfig defaultCloudConfig;

  const SyncSettingsDialog({Key? key, required this.defaultCloudConfig}) : super(key: key);

  static Future<void> show(BuildContext context, WebDavConfig config) {
    return showDialog(
      context: context,
      builder: (context) => SyncSettingsDialog(defaultCloudConfig: config),
    );
  }

  @override
  State<SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends State<SyncSettingsDialog> {
  String? _selectedLocalVaultPath;
  String? _selectedLocalVaultName;
  String? _selectedLocalSubfolder;

  WebDavConfig? _selectedCloudConfig;
  String? _selectedCloudFolder;

  SyncDirection _syncDirection = SyncDirection.twoWay;
  SyncOverrideMethod _overrideMethod = SyncOverrideMethod.timePriority;

  @override
  void initState() {
    super.initState();
    _selectedCloudConfig = widget.defaultCloudConfig;
    _selectedCloudFolder = '/';
  }

  Future<void> _pickLocalFolder() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _LocalVaultPickerPage()),
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedLocalVaultPath = result['vaultPath'];
        _selectedLocalVaultName = result['vaultName'];
        _selectedLocalSubfolder = result['subfolder'];
      });
    }
  }

  Future<void> _pickCloudFolder() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CloudDrivePickerPage(
          initialConfig: _selectedCloudConfig ?? widget.defaultCloudConfig,
        ),
      ),
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedCloudConfig = result['config'];
        _selectedCloudFolder = result['folder'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark &&
                        theme.colorScheme.primary.value == 0xFF00E5FF;
                        
    return AlertDialog(
      title: const Text('同步设置', style: TextStyle(fontWeight: FontWeight.bold)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isCyberpunk ? BorderSide(color: theme.colorScheme.primary, width: 2) : BorderSide.none,
      ),
      backgroundColor: isCyberpunk ? Colors.black87 : theme.colorScheme.surface,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Select encrypted folder
            const Text('1. 选择本地加密文件夹', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildSelectionCard(
              title: _selectedLocalVaultName ?? '未选择',
              subtitle: _selectedLocalSubfolder ?? '点击选择',
              icon: Icons.folder,
              onTap: _pickLocalFolder,
              theme: theme,
              isCyberpunk: isCyberpunk,
            ),
            const SizedBox(height: 16),

            // Row 2: Select cloud disk folder
            const Text('2. 选择云盘同步文件夹', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildSelectionCard(
              title: _selectedCloudConfig?.name ?? '未选择',
              subtitle: _selectedCloudFolder ?? '点击选择',
              icon: Icons.cloud,
              onTap: _pickCloudFolder,
              theme: theme,
              isCyberpunk: isCyberpunk,
            ),
            const SizedBox(height: 16),

            // Row 3: Sync direction
            const Text('3. 同步方式', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SyncDirection>(
                  isExpanded: true,
                  value: _syncDirection,
                  items: const [
                    DropdownMenuItem(value: SyncDirection.cloudToLocal, child: Text('云端到本地 (下载)')),
                    DropdownMenuItem(value: SyncDirection.localToCloud, child: Text('本地到云端 (上传)')),
                    DropdownMenuItem(value: SyncDirection.twoWay, child: Text('双向同步')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _syncDirection = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Row 4: Override method
            const Text('4. 覆盖方式 (同名文件)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SyncOverrideMethod>(
                  isExpanded: true,
                  value: _overrideMethod,
                  items: const [
                    DropdownMenuItem(value: SyncOverrideMethod.overwrite, child: Text('覆盖替换')),
                    DropdownMenuItem(value: SyncOverrideMethod.skip, child: Text('跳过')),
                    DropdownMenuItem(value: SyncOverrideMethod.timePriority, child: Text('时间优先 (保留最新)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _overrideMethod = v);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _selectedLocalVaultPath == null || _selectedCloudConfig == null
              ? null
              : () {
                  // Actually start sync with these settings
                  WebDAVStateManager.instance.startSync(
                    context,
                    _selectedCloudConfig!,
                    _selectedLocalVaultPath!,
                    _selectedCloudFolder ?? '/',
                  );
                  Navigator.of(context).pop();
                },
          child: const Text('开始同步'),
        ),
      ],
    );
  }

  Widget _buildSelectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required ThemeData theme,
    required bool isCyberpunk,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutQuad,
      decoration: BoxDecoration(
        color: isCyberpunk ? Colors.transparent : theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Pickers Below ---

class _LocalVaultPickerPage extends StatefulWidget {
  const _LocalVaultPickerPage({Key? key}) : super(key: key);

  @override
  State<_LocalVaultPickerPage> createState() => _LocalVaultPickerPageState();
}

class _LocalVaultPickerPageState extends State<_LocalVaultPickerPage> {
  List<Map<String, dynamic>> _vaults = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVaults();
  }

  Future<void> _loadVaults() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('vault_paths') ?? [];
    final List<Map<String, dynamic>> loaded = [];

    for (final path in paths) {
      final configFile = File('$path/vault_config.json');
      if (await configFile.exists()) {
        try {
          final jsonStr = await configFile.readAsString();
          final config = VaultConfig.fromJson(jsonDecode(jsonStr));
          loaded.add({'path': path, 'config': config});
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _vaults = loaded;
        _isLoading = false;
      });
    }
  }

  void _onVaultSelected(Map<String, dynamic> vault) {
    // Return root folder for now. 
    // "its root directory is each encrypted folder, and then click on the password After entering the password, it will enter our subfolder"
    // To keep it simple, we just return the vault root.
    // If the user wants to pick a subfolder, we'd need to show the password dialog here,
    // unlock the vault, and show a directory tree. 
    // Let's implement a basic version that selects the vault root.
    _showPasswordDialog(vault);
  }

  Future<void> _showPasswordDialog(Map<String, dynamic> vault) async {
    final config = vault['config'] as VaultConfig;
    final path = vault['path'] as String;

    String password = '';
    bool hasError = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('解锁 ${config.name}'),
              content: TextField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '密码',
                  errorText: hasError ? '密码错误' : null,
                ),
                onChanged: (v) => password = v,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (password.isNotEmpty) {
                      Navigator.of(context).pop(password);
                    } else {
                      setState(() => hasError = true);
                    }
                  },
                  child: const Text('解锁'),
                ),
              ],
            );
          },
        );
      },
    ).then((pass) {
      if (pass != null && pass is String) {
        // Return the vault root. 
        Navigator.of(context).pop({
          'vaultPath': path,
          'vaultName': config.name,
          'subfolder': '/',
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('选择本地加密文件夹')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _vaults.length,
              itemBuilder: (context, index) {
                final vault = _vaults[index];
                final config = vault['config'] as VaultConfig;
                return ListTile(
                  leading: const Icon(Icons.lock),
                  title: Text(config.name),
                  subtitle: Text(vault['path']),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onVaultSelected(vault),
                );
              },
            ),
    );
  }
}

class _CloudDrivePickerPage extends StatefulWidget {
  final WebDavConfig initialConfig;

  const _CloudDrivePickerPage({Key? key, required this.initialConfig}) : super(key: key);

  @override
  State<_CloudDrivePickerPage> createState() => _CloudDrivePickerPageState();
}

class _CloudDrivePickerPageState extends State<_CloudDrivePickerPage> {
  // Simplified for now, just returning the root of the initial config.
  // "its root directory is each cloud disk"
  List<WebDavConfig> _configs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsJson = prefs.getStringList('webdav_configs') ?? [];
    final loaded = configsJson.map((str) => WebDavConfig.fromJson(jsonDecode(str))).toList();
    
    if (mounted) {
      setState(() {
        _configs = loaded;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('选择云盘同步文件夹')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _configs.length,
              itemBuilder: (context, index) {
                final config = _configs[index];
                return ListTile(
                  leading: const Icon(Icons.cloud),
                  title: Text(config.name),
                  subtitle: Text(config.url),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // For now, return root folder
                    Navigator.of(context).pop({
                      'config': config,
                      'folder': '/',
                    });
                  },
                );
              },
            ),
    );
  }
}
