import re

with open('lib/encryption/vault_explorer_page.dart', 'r') as f:
    content = f.read()

# Remove isolates
content = re.sub(r'@visibleForTesting\s*Future<void> doImportFolderIsolate.*?\n}\n', '', content, flags=re.DOTALL)
content = re.sub(r'@visibleForTesting\s*Future<void> doExportFileIsolate.*?\n}\n', '', content, flags=re.DOTALL)
content = re.sub(r'Future<void> _doShareFilesIsolate.*?\n}\n', '', content, flags=re.DOTALL)

import_file_new = """  void _importFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      if (mounted) {
        setState(() {
          _isMenuOpen = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 ${result.files.length} 个文件添加到后台加密任务，请在顶部进度图标查看进度')),
        );
      }
      try {
        for (final file in result.files) {
          if (file.path != null) {
            final taskArgs = {
              'vaultDirectoryPath': widget.vaultDirectoryPath,
              'masterKey': widget.masterKey.toList(),
              'encryptFilename': widget.vaultConfig.encryptFilename,
            };
            EncryptionTaskManager().createEncryptionTask(file.path!, taskArgs: taskArgs);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入文件失败: $e')),
          );
        }
      }
    } else {
      if (mounted) setState(() => _isMenuOpen = false);
    }
  }"""

import_folder_new = """  void _importFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      if (mounted) {
        setState(() {
          _isMenuOpen = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已将文件夹添加到后台加密任务，请在顶部进度图标查看进度')),
        );
      }
      try {
        final taskArgs = {
          'vaultDirectoryPath': widget.vaultDirectoryPath,
          'masterKey': widget.masterKey.toList(),
          'encryptFilename': widget.vaultConfig.encryptFilename,
        };
        EncryptionTaskManager().createEncryptionTask(result, taskArgs: taskArgs);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入文件夹失败: $e')),
          );
        }
      }
    } else {
      if (mounted) setState(() => _isMenuOpen = false);
    }
  }"""

content = re.sub(r'  void _importFile\(\) async \{.*?(?=  void _importFolder\(\))', import_file_new + '\n\n', content, flags=re.DOTALL)
content = re.sub(r'  void _importFolder\(\) async \{.*?(?=  void _loadCurrentDirectory\(\))', import_folder_new + '\n\n', content, flags=re.DOTALL)

with open('lib/encryption/vault_explorer_page.dart', 'w') as f:
    f.write(content)
