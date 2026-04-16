import 'package:flutter/material.dart';

import 'webdav_config.dart';

class WebDavBrowserPage extends StatelessWidget {
  const WebDavBrowserPage({
    super.key,
    required this.config,
  });

  final WebDavConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(config.name),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'WebDAV 预览',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text('URL: ${config.url}'),
          const SizedBox(height: 6),
          Text('用户名: ${config.username}'),
          const SizedBox(height: 16),
          Text(
            '当前仅完成“进入第 1 级目录”的预览页面骨架（/）。后续将补充目录列表与文件操作。',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

