import re

with open('lib/encryption/vault_explorer_page.dart', 'r') as f:
    content = f.read()

# Remove the second occurrence
content = content.replace('''@visibleForTesting
Future<void> doImportFolderIsolate(Map<String, dynamic> args) async {
  await Future.delayed(const Duration(milliseconds: 500));
}''', '', 1)

with open('lib/encryption/vault_explorer_page.dart', 'w') as f:
    f.write(content)
