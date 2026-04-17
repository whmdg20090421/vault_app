import 'package:flutter/material.dart';

import 'webdav_config.dart';
import 'webdav_client_service.dart';
import 'webdav_storage.dart';

class WebDavEditResult {
  const WebDavEditResult({
    required this.config,
    required this.password,
  });

  final WebDavConfig config;
  final String? password;
}

class WebDavEditPage extends StatefulWidget {
  const WebDavEditPage({
    super.key,
    this.initial,
    this.securityLevel,
    this.hasStoredPassword,
  });

  final WebDavConfig? initial;
  final String? securityLevel;
  final bool? hasStoredPassword;

  @override
  State<WebDavEditPage> createState() => _WebDavEditPageState();
}

class _WebDavEditPageState extends State<WebDavEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  bool get _isEdit => widget.initial != null;

  bool _isTesting = false;

  String? get _passwordStatusText {
    if (!_isEdit) {
      return null;
    }
    final hasStored = widget.hasStoredPassword ?? false;
    if (!hasStored) {
      return '授权密码未存储（当前将继续使用已保存的密码，直到你重新输入并保存）';
    }
    final level = widget.securityLevel;
    if (level == 'level2') {
      return '授权密码已存储，但设备仅支持软件级安全存储（安全等级较低）';
    }
    if (level == 'level1') {
      return '授权密码已安全存储（硬件级）';
    }
    return '授权密码已存储';
  }

  Color? _passwordStatusColor(ThemeData theme) {
    if (!_isEdit) {
      return null;
    }
    final hasStored = widget.hasStoredPassword ?? false;
    if (!hasStored) {
      return theme.colorScheme.outline;
    }
    if (widget.securityLevel == 'level2') {
      return theme.colorScheme.tertiary;
    }
    return theme.colorScheme.primary;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _urlController = TextEditingController(text: initial?.url ?? '');
    _usernameController = TextEditingController(text: initial?.username ?? '');
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateNotEmpty(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '不能为空';
    }
    return null;
  }

  String? _validateUrl(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return '不能为空';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'URL 无效';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (_isEdit && (value == null || value.isEmpty)) {
      return null;
    }
    return _validateNotEmpty(value);
  }

  Future<void> _testAndSubmit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isTesting = true;
    });

    try {
      final url = _urlController.text.trim();
      final username = _usernameController.text.trim();
      String password = _passwordController.text;

      if (_isEdit && password.isEmpty) {
        final repo = WebDavConfigRepository();
        final storedPassword = await repo.readPassword(widget.initial!.id);
        if (storedPassword != null) {
          password = storedPassword;
        }
      }

      final service = WebDavService(
        url: url,
        username: username,
        password: password,
      );

      await service.readDir('/');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接成功')),
        );
        _submit();
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接失败'),
            content: Text(translateWebDavError(e)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final id =
        widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final config = WebDavConfig(
      id: id,
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      username: _usernameController.text.trim(),
    );

    final password = _passwordController.text;
    final passwordValue = password.isEmpty ? null : password;

    Navigator.of(context).pop(WebDavEditResult(config: config, password: passwordValue));
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? '编辑 WebDAV' : '新增 WebDAV';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isTesting ? null : _testAndSubmit,
            child: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('测试/连接'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '命名',
                border: OutlineInputBorder(),
              ),
              validator: _validateNotEmpty,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '连接网站（URL）',
                border: OutlineInputBorder(),
              ),
              validator: _validateUrl,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '账户名',
                border: OutlineInputBorder(),
              ),
              validator: _validateNotEmpty,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '授权密码',
                border: const OutlineInputBorder(),
                helperText: _isEdit ? '留空则保持不变' : null,
              ),
              validator: _validatePassword,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _testAndSubmit(),
            ),
            if (_passwordStatusText != null) ...[
              const SizedBox(height: 10),
              Text(
                _passwordStatusText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _passwordStatusColor(theme),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
