import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../theme/background_settings.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  Future<void> _pickImage(BuildContext context) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final bgDir = Directory('${appDir.path}/backgrounds');
      await bgDir.create(recursive: true);

      final previousPath = BackgroundSettings.instance.imagePath;
      if (previousPath != null) {
        try {
          final previous = File(previousPath);
          if (previous.path.startsWith(bgDir.path) && await previous.exists()) {
            await previous.delete();
          }
        } catch (_) {}
      }

      final ext = pickedFile.name.contains('.') ? '.${pickedFile.name.split('.').last}' : '';
      final savedImage = File('${bgDir.path}/bg_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(pickedFile.path).copy(savedImage.path);
      BackgroundSettings.instance.setImagePath(savedImage.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主题与背景设置'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([appTheme, BackgroundSettings.instance]),
        builder: (context, _) {
          final theme = appTheme.value;
          final bg = BackgroundSettings.instance;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '主题',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<AppTheme>(
                segments: const [
                  ButtonSegment(
                    value: AppTheme.defaultTheme,
                    label: Text('默认主题'),
                    icon: Icon(Icons.auto_awesome_rounded),
                  ),
                  ButtonSegment(
                    value: AppTheme.cyberpunk,
                    label: Text('赛博朋克'),
                    icon: Icon(Icons.bolt_rounded),
                  ),
                  ButtonSegment(
                    value: AppTheme.pureBlack,
                    label: Text('极简黑'),
                    icon: Icon(Icons.dark_mode_rounded),
                  ),
                ],
                selected: {theme},
                onSelectionChanged: (selection) => appTheme.value = selection.first,
                showSelectedIcon: true,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('启用自定义背景'),
                value: bg.enabled,
                onChanged: (val) => bg.setEnabled(val),
                contentPadding: EdgeInsets.zero,
              ),
              if (bg.enabled) ...[
                ListTile(
                  title: const Text('选择背景图片'),
                  subtitle: Text(bg.imagePath != null ? '已选择图片' : '未选择图片'),
                  trailing: const Icon(Icons.image),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _pickImage(context),
                ),
                if (bg.imagePath != null) ...[
                  const SizedBox(height: 16),
                  Text('背景遮罩不透明度: ${(bg.imageOpacity * 100).toInt()}%'),
                  Slider(
                    value: bg.imageOpacity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) => bg.setImageOpacity(val),
                  ),
                  const SizedBox(height: 8),
                  Text('UI 组件不透明度: ${(bg.uiOpacity * 100).toInt()}%'),
                  Slider(
                    value: bg.uiOpacity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) => bg.setUiOpacity(val),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}
