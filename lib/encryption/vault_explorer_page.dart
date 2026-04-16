import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'models/vault_config.dart';

class VaultExplorerPage extends StatefulWidget {
  final VaultConfig vaultConfig;
  final Uint8List masterKey;
  final String vaultDirectoryPath;

  const VaultExplorerPage({
    super.key,
    required this.vaultConfig,
    required this.masterKey,
    required this.vaultDirectoryPath,
  });

  @override
  State<VaultExplorerPage> createState() => _VaultExplorerPageState();
}

class _VaultExplorerPageState extends State<VaultExplorerPage> {
  bool _isMenuOpen = false;

  void _importFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已选择 ${result.files.length} 个文件，准备导入 (加密功能开发中)')),
      );
    }
    setState(() => _isMenuOpen = false);
  }

  void _importFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已选择文件夹: $result，准备导入 (加密功能开发中)')),
      );
    }
    setState(() => _isMenuOpen = false);
  }

  void _newFolder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('新建文件夹功能开发中')),
    );
    setState(() => _isMenuOpen = false);
  }

  Widget _buildExpandableFab() {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isMenuOpen) ...[
          _buildFabOption('新建空文件夹', Icons.create_new_folder, _newFolder),
          const SizedBox(height: 16),
          _buildFabOption('导入明文文件夹', Icons.drive_folder_upload, _importFolder),
          const SizedBox(height: 16),
          _buildFabOption('导入明文文件', Icons.upload_file, _importFile),
          const SizedBox(height: 16),
        ],
        FloatingActionButton(
          heroTag: 'vault_explorer_fab',
          onPressed: () {
            setState(() {
              _isMenuOpen = !_isMenuOpen;
            });
          },
          backgroundColor: theme.colorScheme.primary,
          child: Icon(_isMenuOpen ? Icons.close : Icons.add),
        ),
      ],
    );
  }

  Widget _buildFabOption(String label, IconData icon, VoidCallback onPressed) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 16),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onPressed,
          backgroundColor: theme.colorScheme.secondary,
          child: Icon(icon, color: theme.colorScheme.onSecondary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark && 
                        theme.colorScheme.secondary.value == 0xFF00F0FF;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vaultConfig.name),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: theme.colorScheme.onSurface.withOpacity(0.2),
            ),
            const SizedBox(height: 16),
            Text(
              '保险箱目前为空',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildExpandableFab(),
    );
  }
}
