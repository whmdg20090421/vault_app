import re

with open('lib/encryption/encryption_page.dart', 'r') as f:
    content = f.read()

# The class EncryptionProgressPanel is at the end of the file.
# Let's see where it starts.
# It starts at `class EncryptionProgressPanel extends StatefulWidget`
match = re.search(r'class EncryptionProgressPanel extends StatefulWidget.*', content, flags=re.DOTALL)
if match:
    content = content[:match.start()]
    with open('lib/encryption/encryption_page.dart', 'w') as f:
        f.write(content)
