import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  String _changelogData = '正在加载更新日志...';

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  Future<void> _loadChangelog() async {
    try {
      final data = await rootBundle.loadString('CHANGELOG.md');
      if (mounted) {
        setState(() {
          _changelogData = data;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _changelogData = '无法加载更新日志。\n错误信息: $e';
        });
      }
    }
  }

  List<Widget> _parseChangelog(String text) {
    // 简单的 Markdown 解析
    final sections = text.split(RegExp(r'(?=# 版本)'));
    List<Widget> tiles = [];
    
    for (final section in sections) {
      final lines = section.trim().split('\n');
      if (lines.isEmpty || lines[0].isEmpty) continue;
      
      final title = lines.first.replaceAll('#', '').trim();
      final bodyLines = lines.skip(1).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      
      tiles.add(
        ExpansionTile(
          title: Text(title),
          initiallyExpanded: tiles.isEmpty, // 默认展开第一个
          children: [
            ListTile(
              title: Text(bodyLines.join('\n')),
            ),
          ],
        ),
      );
    }
    
    if (tiles.isEmpty) {
      return [ListTile(title: Text(_changelogData))];
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新日志'),
      ),
      body: ListView(
        children: _parseChangelog(_changelogData),
      ),
    );
  }
}
