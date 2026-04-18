import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/encryption_task_manager.dart';

class PerformanceSettingsPage extends StatefulWidget {
  const PerformanceSettingsPage({super.key});

  @override
  State<PerformanceSettingsPage> createState() => _PerformanceSettingsPageState();
}

class _PerformanceSettingsPageState extends State<PerformanceSettingsPage> {
  static const _prefsKeyEncryptionCores = 'encryption_cores';

  late final TextEditingController _coresController;
  int _totalCores = 1;
  int _maxUsableCores = 1;
  int _selectedCores = 1;

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

    if (mounted) setState(() {});
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

