import 'package:flutter/material.dart';

import 'webdav_config.dart';

class WebDavEditResult {
  const WebDavEditResult({
    required this.config,
    required this.password,
  });

  final WebDavConfig config;
  final String? password;
}

class WebDavEditPage extends StatefulWidget {
  const WebDavEditPage({super.key, this.initial});

  final WebDavConfig? initial;

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

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('保存'),
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
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    );
  }
}

