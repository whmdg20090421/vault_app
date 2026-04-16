import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# I will find the lines containing the remaining parts of CyberpunkBorder and remove them.
# The remaining part starts around line 60 (or earlier) and ends at `}\n\nfinal ValueNotifier<AppTheme>`
# Let's just find `class CyberpunkBorder` to `scale(double t) { ... }`

lines = content.split('\n')
new_lines = []
skip = False
for line in lines:
    if 'class CyberpunkBorder extends OutlinedBorder' in line:
        skip = True
    if not skip:
        new_lines.append(line)
    if skip and line.startswith('}'):
        skip = False

content = '\n'.join(new_lines)

# Now check for any other usages of CyberpunkBorder in _buildTheme. 
# Oh wait, there are still `CyberpunkBorder` usages at 573, 577 because my `_buildTheme` replacement only replaced a part?
# Let's check where `_buildTheme` was replaced.
