import re

with open('lib/encryption/vault_explorer_page.dart', 'r') as f:
    content = f.read()

skeletons = """
@visibleForTesting
Future<void> doImportFolderIsolate(Map<String, dynamic> args) async {
  await Future.delayed(const Duration(milliseconds: 500));
}

@visibleForTesting
Future<void> doExportFileIsolate(Map<String, dynamic> args) async {
  await Future.delayed(const Duration(milliseconds: 500));
}

Future<void> _doShareFilesIsolate(Map<String, dynamic> args) async {
  await Future.delayed(const Duration(milliseconds: 500));
}

class VaultExplorerPage
"""

content = content.replace('class VaultExplorerPage', skeletons)

with open('lib/encryption/vault_explorer_page.dart', 'w') as f:
    f.write(content)
