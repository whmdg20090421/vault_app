import re

with open('lib/about_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

new_imports = """import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'changelog_page.dart';
import 'main.dart';"""
content = re.sub(r"import 'package:flutter/material\.dart';\n\nimport 'changelog_page\.dart';", new_imports, content)

new_class = """class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.single.path != null) {
      final sourcePath = result.files.single.path!;
      final docDir = await getApplicationDocumentsDirectory();
      final ext = sourcePath.split('.').last;
      final destPath = '${docDir.path}/custom_bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
      
      final file = File(sourcePath);
      await file.copy(destPath);
      
      await BackgroundSettings.instance.setImagePath(destPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
      ),
      body: ListenableBuilder(
        listenable: BackgroundSettings.instance,
        builder: (context, _) {
          final bg = BackgroundSettings.instance;
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const SizedBox(height: 40),
              const FlutterLogo(size: 100),
              const SizedBox(height: 20),
              Text(
                '天眼·艨艟战舰',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '版本: 1.1.3',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '包名: com.tianyan.vault',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Text(
                '天眼·艨艟战舰是一款提供高级数据加密与云端存储管理的应用程序。我们致力于保护您的数字资产安全。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('启用自定义背景'),
                      value: bg.enabled,
                      onChanged: (val) => bg.setEnabled(val),
                    ),
                    if (bg.enabled) ...[
                      ListTile(
                        leading: const Icon(Icons.image),
                        title: const Text('选择背景图片'),
                        subtitle: Text(bg.imagePath == null ? '未选择图片' : '已选择图片'),
                        trailing: bg.imagePath != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => bg.setImagePath(null),
                              )
                            : null,
                        onTap: _pickImage,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('背景图片透明度'),
                            Slider(
                              value: bg.imageOpacity,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (val) => bg.setImageOpacity(val),
                            ),
                            const Text('界面背景透明度'),
                            Slider(
                              value: bg.uiOpacity,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (val) => bg.setUiOpacity(val),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('更新日志'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ChangelogPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}"""
content = re.sub(r"class AboutPage extends StatelessWidget \{[\s\S]*", new_class, content)

with open('lib/about_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)

