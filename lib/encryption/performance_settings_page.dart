import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'services/encryption_task_manager.dart';

class PerformanceSettingsPage extends StatefulWidget {
  const PerformanceSettingsPage({super.key});

  @override
  State<PerformanceSettingsPage> createState() => _PerformanceSettingsPageState();
}

class _PerformanceSettingsPageState extends State<PerformanceSettingsPage> {
  static const _prefsKeyEncryptionCores = 'encryption_cores';
  static const _prefsKeyAllocationStrategy = 'encryption_allocation_strategy';

  late final TextEditingController _coresController;
  int _totalCores = 1;
  int _maxUsableCores = 1;
  int _selectedCores = 1;
  bool _autoRefreshOnStartup = false;
  String _allocationStrategy = 'smart';

  @override
  void initState() {
    super.initState();
    _coresController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _coresController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _totalCores = Platform.numberOfProcessors;
    _maxUsableCores = (_totalCores - 1).clamp(1, _totalCores);

    final saved = prefs.getInt(_prefsKeyEncryptionCores);
    _selectedCores = (saved ?? (_totalCores ~/ 2)).clamp(1, _maxUsableCores);
    _coresController.text = _selectedCores.toString();

    _autoRefreshOnStartup = prefs.getBool('auto_refresh_on_startup') ?? false;
    _allocationStrategy = prefs.getString(_prefsKeyAllocationStrategy) ?? 'smart';

    if (mounted) setState(() {});
  }

  Future<void> _toggleAutoRefresh(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_refresh_on_startup', value);
    setState(() {
      _autoRefreshOnStartup = value;
    });
  }

  Future<void> _setAllocationStrategy(String value) async {
    if (value == _allocationStrategy) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyAllocationStrategy, value);
    setState(() {
      _allocationStrategy = value;
    });
    EncryptionTaskManager().pumpQueue();
  }

  Future<void> _persist(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyEncryptionCores, value);
    EncryptionTaskManager().pumpQueue();
  }

  void _setCores(int value) {
    final clamped = value.clamp(1, _maxUsableCores);
    if (clamped == _selectedCores) return;
    setState(() {
      _selectedCores = clamped;
      _coresController.text = _selectedCores.toString();
    });
    _persist(_selectedCores);
  }

  Future<void> _runCompatibilityTest() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在进行兼容性测试...'),
          ],
        ),
      ),
    );

    try {
      final dataSize = 10 * 1024 * 1024;
      final random = Random.secure();
      final data = Uint8List(dataSize);
      for (int i = 0; i < dataSize; i++) {
        data[i] = random.nextInt(256);
      }

      final secretKeyBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final secretKey = SecretKey(secretKeyBytes);
      final nonce = List<int>.generate(12, (_) => random.nextInt(256));

      // 1. FlutterCryptography
      final flutterCrypto = FlutterCryptography.defaultInstance;
      final flutterCipher = flutterCrypto.aesGcm(secretKeyLength: 32);
      
      final flutterStart = DateTime.now();
      await flutterCipher.encrypt(data, secretKey: secretKey, nonce: nonce);
      final flutterEnd = DateTime.now();
      final flutterTime = flutterEnd.difference(flutterStart).inMilliseconds;
      final flutterSpeed = flutterTime > 0
          ? ((dataSize / 1024 / 1024) / (flutterTime / 1000)).toStringAsFixed(2)
          : '∞';

      // 2. DartCryptography (Software)
      final dartCrypto = DartCryptography.defaultInstance;
      final dartCipher = dartCrypto.aesGcm(secretKeyLength: 32);
      
      final dartStart = DateTime.now();
      await dartCipher.encrypt(data, secretKey: secretKey, nonce: nonce);
      final dartEnd = DateTime.now();
      final dartTime = dartEnd.difference(dartStart).inMilliseconds;
      final dartSpeed = dartTime > 0
          ? ((dataSize / 1024 / 1024) / (dartTime / 1000)).toStringAsFixed(2)
          : '∞';

      final chachaCipher = Chacha20.poly1305Aead();
      final chachaStart = DateTime.now();
      await chachaCipher.encrypt(data, secretKey: secretKey, nonce: nonce);
      final chachaEnd = DateTime.now();
      final chachaTime = chachaEnd.difference(chachaStart).inMilliseconds;
      final chachaSpeed = chachaTime > 0
          ? ((dataSize / 1024 / 1024) / (chachaTime / 1000)).toStringAsFixed(2)
          : '∞';

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('测试结果'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('测试数据: 10 MB'),
                const SizedBox(height: 8),
                const Text('AES-256-GCM', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('硬件加速 (FlutterCryptography):', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('延迟: $flutterTime ms'),
                Text('速度: $flutterSpeed MB/s'),
                const SizedBox(height: 16),
                const Text('软件实现 (DartCryptography):', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('延迟: $dartTime ms'),
                Text('速度: $dartSpeed MB/s'),
                const SizedBox(height: 16),
                const Text('ChaCha20-Poly1305', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('硬件加速:', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('当前实现不支持'),
                const SizedBox(height: 16),
                const Text('软件实现 (DartCryptography):', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('延迟: $chachaTime ms'),
                Text('速度: $chachaSpeed MB/s'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('测试失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCyberpunk = theme.brightness == Brightness.dark &&
                        theme.colorScheme.primary.value == 0xFF00E5FF;
                        
    return Scaffold(
      appBar: AppBar(
        title: const Text('性能设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            decoration: BoxDecoration(
              color: isCyberpunk ? Colors.transparent : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: isCyberpunk
                  ? Border.all(color: theme.colorScheme.primary.withOpacity(0.3))
                  : Border.all(color: Colors.transparent),
              boxShadow: isCyberpunk
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('启动时自动刷新统计数据'),
                  subtitle: const Text('每次启动应用时自动计算文件统计信息'),
                  value: _autoRefreshOnStartup,
                  onChanged: _toggleAutoRefresh,
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('兼容性测试'),
                  subtitle: const Text('测试硬件加密与软件加密在当前设备的性能差异 (10MB)'),
                  trailing: const Icon(Icons.speed_rounded),
                  contentPadding: EdgeInsets.zero,
                  onTap: _runCompatibilityTest,
                ),
                const SizedBox(height: 16),
                Text(
                  '加密CPU数量 (${_selectedCores}/${_totalCores})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (_maxUsableCores > 1)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: theme.colorScheme.primary,
                      inactiveTrackColor: theme.colorScheme.primary.withOpacity(0.2),
                      thumbColor: theme.colorScheme.primary,
                      overlayColor: theme.colorScheme.primary.withOpacity(0.1),
                    ),
                    child: Slider(
                      value: _selectedCores.toDouble(),
                      min: 1,
                      max: _maxUsableCores.toDouble(),
                      divisions: (_maxUsableCores - 1).clamp(1, 100),
                      label: _selectedCores.toString(),
                      onChanged: (v) => _setCores(v.round()),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text('当前设备可用核心数仅为 1，无法调整。', style: TextStyle(color: Colors.grey)),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _coresController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '手动输入CPU数量',
                    helperText: '范围: 1 ~ $_maxUsableCores',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: (v) => _setCores(int.tryParse(v) ?? _selectedCores),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  '加密分配策略',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  title: const Text('智能分配 (推荐)'),
                  subtitle: const Text('自动在硬件加速与软件加密之间分配任务，以压榨全部算力'),
                  value: 'smart',
                  groupValue: _allocationStrategy,
                  onChanged: (v) => v != null ? _setAllocationStrategy(v) : null,
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.colorScheme.primary,
                ),
                RadioListTile<String>(
                  title: const Text('仅硬件加速'),
                  subtitle: const Text('仅使用 FlutterCryptography 进行硬件加速加密'),
                  value: 'hardware',
                  groupValue: _allocationStrategy,
                  onChanged: (v) => v != null ? _setAllocationStrategy(v) : null,
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.colorScheme.primary,
                ),
                RadioListTile<String>(
                  title: const Text('仅软件加密'),
                  subtitle: const Text('仅使用 DartCryptography 纯软件实现加密'),
                  value: 'software',
                  groupValue: _allocationStrategy,
                  onChanged: (v) => v != null ? _setAllocationStrategy(v) : null,
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
