import re

with open('lib/encryption/vault_explorer_page.dart', 'r') as f:
    content = f.read()

old_str = """                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        barrierColor: theme.colorScheme.scrim.withValues(alpha: 0.6),
                        shape: theme.isCyberpunk
                            ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
                            : const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                        clipBehavior: Clip.antiAlias,
                        builder: (context) => DraggableScrollableSheet(
                          initialChildSize: 0.6,
                          minChildSize: 0.4,
                          maxChildSize: 0.9,
                          expand: false,
                          builder: (context, scrollController) => EncryptionProgressPanel(
                            scrollController: scrollController,
                          ),
                        ),
                      );"""

new_str = "                      showEncryptionProgressPanel(context);"

content = content.replace(old_str, new_str)

with open('lib/encryption/vault_explorer_page.dart', 'w') as f:
    f.write(content)
