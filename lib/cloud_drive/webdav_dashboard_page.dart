import 'package:flutter/material.dart';
import 'webdav_config.dart';
import 'webdav_state_manager.dart';
import 'webdav_browser_page.dart'; // We'll modify it slightly to not have a Scaffold if used in a Tab

class WebDAVDashboardPage extends StatefulWidget {
  final WebDavConfig config;

  const WebDAVDashboardPage({super.key, required this.config});

  @override
  State<WebDAVDashboardPage> createState() => _WebDAVDashboardPageState();
}

class _WebDAVDashboardPageState extends State<WebDAVDashboardPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.config.name),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: '概览'),
              Tab(text: '动态日志'),
              Tab(text: '文件浏览'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(), // File browser might have swipe gestures, so better disable TabBarView swipe
          children: [
            _OverviewTab(config: widget.config),
            _LogsTab(),
            WebDavBrowserPage(config: widget.config, isEmbedded: true),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final WebDavConfig config;

  const _OverviewTab({required this.config});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WebDAVStateManager.instance,
      builder: (context, _) {
        final state = WebDAVStateManager.instance;
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: ListTile(
                  title: const Text('服务器地址'),
                  subtitle: Text(config.url),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  title: const Text('用户名'),
                  subtitle: Text(config.username),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  title: const Text('最后同步时间'),
                  subtitle: Text(state.lastSyncTime != null
                      ? state.lastSyncTime.toString()
                      : '尚未同步'),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: state.isSyncing
                      ? null
                      : () => state.startSync(config),
                  icon: state.isSyncing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: Text(state.isSyncing ? '同步中...' : '开始同步'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WebDAVStateManager.instance,
      builder: (context, _) {
        final logs = WebDAVStateManager.instance.syncLogs;
        if (logs.isEmpty) {
          return const Center(child: Text('暂无日志'));
        }
        return ListView.builder(
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[logs.length - 1 - index]; // latest first
            return ListTile(
              leading: Icon(
                log.isError ? Icons.error : Icons.info,
                color: log.isError ? Colors.red : Colors.blue,
              ),
              title: Text(log.message),
              subtitle: Text(log.time.toString()),
            );
          },
        );
      },
    );
  }
}