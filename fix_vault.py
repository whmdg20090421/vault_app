import re

with open('lib/encryption/vault_explorer_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace _importFiles logic
import_files_pattern = re.compile(
    r'final taskId = DateTime\.now\(\)\.millisecondsSinceEpoch\.toString\(\);[\s\S]*?EncryptionTaskManager\(\)\.pumpQueue\(\);',
    re.MULTILINE
)
import_files_replacement = """
          for (final f in filesToProcess) {
            await EncryptionTaskManager().createEncryptionTask(
              f['localPath']!,
              taskArgs: {
                'remotePath': f['remotePath'],
                'vaultDirectoryPath': widget.vaultDirectoryPath,
                'masterKey': widget.masterKey,
                'encryptFilename': widget.vaultConfig.encryptFilename,
              }
            );
          }
"""
content = import_files_pattern.sub(import_files_replacement, content)

# Replace _importFolder logic
import_folder_pattern = re.compile(
    r'final taskId = DateTime\.now\(\)\.millisecondsSinceEpoch\.toString\(\);[\s\S]*?await Isolate\.spawn\(doImportFolderIsolate, args\);\s*EncryptionTaskManager\(\)\.pumpQueue\(\);',
    re.MULTILINE
)
import_folder_replacement = """
            await EncryptionTaskManager().createEncryptionTask(
              result,
              taskArgs: {
                'remotePath': p.join(_currentPath, p.basename(result)).replaceAll(r'\\\\', '/'),
                'vaultDirectoryPath': widget.vaultDirectoryPath,
                'masterKey': widget.masterKey,
                'encryptFilename': widget.vaultConfig.encryptFilename,
              }
            );
"""
content = import_folder_pattern.sub(import_folder_replacement, content)

# Remove `EncryptionTaskManager().registerIsolate(taskId, isolate);` from the file
content = re.sub(r'EncryptionTaskManager\(\)\.registerIsolate\(.*?\);\n', '', content)

with open('lib/encryption/vault_explorer_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)
