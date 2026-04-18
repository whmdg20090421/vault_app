import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

enum PermissionMode { normal, root }
enum RootBehavior { defaultBehavior, always }

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  bool _isLoading = true;
  bool _isDirty = false;

  PermissionMode _currentMode = PermissionMode.normal;
  RootBehavior _currentBehavior = RootBehavior.defaultBehavior;

  PermissionMode _savedMode = PermissionMode.normal;
  RootBehavior _savedBehavior = RootBehavior.defaultBehavior;

  bool _isRootGranted = false;
  bool _isCheckingRoot = false;
  String? _rootError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedMode = PermissionMode.values[prefs.getInt('security_permission_mode') ?? 0];
      _savedBehavior = RootBehavior.values[prefs.getInt('security_root_behavior') ?? 0];
      
      _currentMode = _savedMode;
      _currentBehavior = _savedBehavior;
      _isLoading = false;
    });

    if (_currentMode == PermissionMode.root) {
      _checkRoot();
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('security_permission_mode', _currentMode.index);
    await prefs.setInt('security_root_behavior', _currentBehavior.index);

    setState(() {
      _savedMode = _currentMode;
      _savedBehavior = _currentBehavior;
      _isDirty = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  void _markDirty() {
    setState(() {
      _isDirty = (_currentMode != _savedMode) || (_currentBehavior != _savedBehavior);
    });
  }

  Future<void> _checkRoot() async {
    setState(() {
      _isCheckingRoot = true;
      _rootError = null;
    });

    try {
      final result = await Process.run('su', ['-c', 'id']);
      setState(() {
        if (result.exitCode == 0) {
          _isRootGranted = true;
        } else {
          _isRootGranted = false;
          _rootError = '获取 Root 权限失败 (Exit code: ${result.exitCode})';
        }
        _isCheckingRoot = false;
      });
    } catch (e) {
      setState(() {
        _isRootGranted = false;
        _rootError = '无法执行 su 命令: $e';
        _isCheckingRoot = false;
      });
    }
  }

  void _onPopInvoked(bool didPop) async {
    if (didPop) return;

    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('您有未保存的更改。确定要放弃这些更改并退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃更改', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final canSave = !_isCheckingRoot && (_currentMode != PermissionMode.root || _isRootGranted);

    return PopScope(
      canPop: !_isDirty,
      onPopInvoked: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('安全设置'),
          actions: [
            if (_isDirty)
              TextButton(
                onPressed: canSave ? _saveSettings : null,
                child: const Text('确认'),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '权限模式',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            RadioListTile<PermissionMode>(
              title: const Text('普通模式'),
              subtitle: const Text('使用标准应用权限运行'),
              value: PermissionMode.normal,
              groupValue: _currentMode,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _currentMode = value;
                    _markDirty();
                  });
                }
              },
            ),
            RadioListTile<PermissionMode>(
              title: const Text('Root 模式'),
              subtitle: const Text('需要 Root 权限以执行高级操作'),
              value: PermissionMode.root,
              groupValue: _currentMode,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _currentMode = value;
                    _markDirty();
                  });
                  _checkRoot();
                }
              },
            ),
            if (_currentMode == PermissionMode.root) ...[
              const Divider(),
              const Text(
                'Root 行为设置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_isCheckingRoot)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2),
                      SizedBox(width: 16),
                      Text('正在检测 Root 权限...'),
                    ],
                  ),
                )
              else if (!_isRootGranted)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _rootError ?? 'Root 权限未授予',
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _checkRoot,
                        child: const Text('重新检测'),
                      ),
                    ],
                  ),
                )
              else ...[
                RadioListTile<RootBehavior>(
                  title: const Text('默认'),
                  subtitle: const Text('需要时临时申请'),
                  value: RootBehavior.defaultBehavior,
                  groupValue: _currentBehavior,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _currentBehavior = value;
                        _markDirty();
                      });
                    }
                  },
                ),
                RadioListTile<RootBehavior>(
                  title: const Text('始终'),
                  subtitle: const Text('始终保持 Root 状态'),
                  value: RootBehavior.always,
                  groupValue: _currentBehavior,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _currentBehavior = value;
                        _markDirty();
                      });
                    }
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
