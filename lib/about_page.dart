import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'changelog_page.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '加载中...';
  String _packageName = '加载中...';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = '${info.version}+${info.buildNumber}';
          _packageName = info.packageName;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _version = '未知版本';
          _packageName = '未知包名';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
      ),
      body: ListView(
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
            '版本: $_version',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '包名: $_packageName',
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
      ),
    );
  }
}
