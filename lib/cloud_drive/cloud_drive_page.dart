import 'package:flutter/material.dart';
import '../main.dart';

import 'security_detector.dart';
import 'security_level.dart';
import 'webdav_config.dart';
import 'webdav_browser_page.dart';
import 'webdav_edit_page.dart';
import 'webdav_storage.dart';

import 'sync_config_page.dart';

class CloudDrivePage extends StatefulWidget {
  const CloudDrivePage({
    super.key,
    WebDavConfigRepository? repository,
    SecurityDetector? securityDetector,
  })  : _repository = repository,
        _securityDetector = securityDetector;

  final WebDavConfigRepository? _repository;
  final SecurityDetector? _securityDetector;

  @override
  State<CloudDrivePage> createState() => _CloudDrivePageState();
}

class _CloudDrivePageState extends State<CloudDrivePage> {
  late final WebDavConfigRepository _repository;
  late final SecurityDetector _securityDetector;

  bool _loading = true;
  List<WebDavConfig> _configs = const [];
  SecurityLevel? _securityLevel;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? WebDavConfigRepository();
    _securityDetector = widget._securityDetector ?? SecurityDetector();
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) {
      return;
    }
    setState(() => _loading = true);
    final configs = await _repository.listConfigs();
    final level = await _repository.readSecurityLevel();
    if (!mounted) {
      return;
    }
    setState(() {
      _configs = configs;
      _securityLevel = level;
      _loading = false;
    });
  }

  Future<void> _ensureSecurityLevel() async {
    if (_securityLevel != null) {
      return;
    }
    final detected = await _securityDetector.detect();
    await _repository.writeSecurityLevel(detected);
    if (!mounted) {
      return;
    }
    setState(() => _securityLevel = detected);

    final theme = Theme.of(context);
    final title = detected == SecurityLevel.level1 ? '安全存储提示' : '安全存储提醒';
    final content = detected == SecurityLevel.level1
        ? '当前设备支持硬件级安全存储（Level 1），授权密码将安全保存。'
        : '当前设备仅支持软件级安全存储（Level 2），授权密码仍会保存，但安全等级较低。';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('知道了', style: TextStyle(color: theme.colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final result = await Navigator.of(context).push<WebDavEditResult>(
      MaterialPageRoute(
        builder: (_) => WebDavEditPage(
          securityLevel: _securityLevel?.toJson(),
          hasStoredPassword: false,
        ),
      ),
    );
    if (result == null) {
      return;
    }

    await _ensureSecurityLevel();
    await _repository.upsertConfig(result.config, password: result.password);
    await _reload();
  }

  Future<void> _edit(WebDavConfig config) async {
    final hasPassword = await _repository.hasPassword(config.id);
    final result = await Navigator.of(context).push<WebDavEditResult>(
      MaterialPageRoute(
        builder: (_) => WebDavEditPage(
          initial: config,
          securityLevel: _securityLevel?.toJson(),
          hasStoredPassword: hasPassword,
        ),
      ),
    );
    if (result == null) {
      return;
    }

    await _ensureSecurityLevel();
    await _repository.upsertConfig(result.config, password: result.password);
    await _reload();
  }

  Future<void> _delete(WebDavConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确认删除“${config.name}”？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _repository.deleteConfig(config.id);
    await _reload();
  }

  Widget _securityBanner(ThemeData theme) {
    final level = _securityLevel;
    if (level != SecurityLevel.level2) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: theme.isCyberpunk ? BorderRadius.zero : BorderRadius.circular(12),
        border: theme.isCyberpunk ? Border.all(color: theme.colorScheme.tertiary, width: 2) : null,
      ),
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Icon(Icons.warning_rounded, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '当前设备仅支持软件级安全存储，已保存但安全等级较低。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _levelIcon() {
    return switch (_securityLevel) {
      SecurityLevel.level1 => Icons.verified_rounded,
      SecurityLevel.level2 => Icons.warning_rounded,
      _ => Icons.shield_outlined,
    };
  }

  Color? _levelColor(ThemeData theme) {
    return switch (_securityLevel) {
      SecurityLevel.level1 => theme.colorScheme.primary,
      SecurityLevel.level2 => theme.colorScheme.tertiary,
      _ => theme.colorScheme.outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Column(
          children: [
            _securityBanner(theme),
            Expanded(
              child: _configs.isEmpty
                  ? Center(
                      child: Text(
                        '暂无 WebDAV 配置',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _configs.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = _configs[index];
                        return Card(
                          child: ListTile(
                            leading:
                                Icon(_levelIcon(), color: _levelColor(theme)),
                            title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${item.username} · ${item.url}', maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => WebDavBrowserPage(config: item),
                                ),
                              );
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '编辑',
                                  onPressed: () => _edit(item),
                                  icon: const Icon(Icons.edit_rounded),
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  onPressed: () => _delete(item),
                                  icon: const Icon(Icons.delete_rounded),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'sync_task_btn',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SyncConfigPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('新建同步任务'),
                ),
                const SizedBox(height: 16),
                FloatingActionButton.extended(
                  heroTag: 'add_webdav_btn',
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增 WebDAV'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
