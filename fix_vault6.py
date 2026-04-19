import re

with open('lib/encryption/vault_explorer_page.dart', 'r') as f:
    content = f.read()

content = re.sub(r'showModalBottomSheet\(.*?scrollController: scrollController,\n\s*\),\n\s*\),\n\s*\);', 'showEncryptionProgressPanel(context);', content, flags=re.DOTALL)

with open('lib/encryption/vault_explorer_page.dart', 'w') as f:
    f.write(content)
