import 'package:flutter/material.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新日志'),
      ),
      body: ListView(
        children: const [
          ExpansionTile(
            title: Text('版本 1.1.2'),
            children: [
              ListTile(
                title: Text('• 优化整体性能，提升应用响应速度\n• 修复部分已知问题'),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.1.1'),
            children: [
              ListTile(
                title: Text('• 改进云盘文件管理体验\n• 增强加密相册的安全性'),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.1.0'),
            children: [
              ListTile(
                title: Text('• 全新赛博朋克主题上线\n• 新增文件批量操作功能'),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.0.0'),
            children: [
              ListTile(
                title: Text('• 天眼·艨艟战舰首次发布\n• 提供基础云盘与加密功能'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
