import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PerformanceSettingsPage extends StatefulWidget {
  const PerformanceSettingsPage({super.key});

  @override
  State<PerformanceSettingsPage> createState() => _PerformanceSettingsPageState();
}

class _PerformanceSettingsPageState extends State<PerformanceSettingsPage> {
  static const _prefsKeyBenchmarkCores = 'benchmark_cores';

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

    final saved = prefs.getInt(_prefsKeyBenchmarkCores);
    _selectedCores = (saved ?? _maxUsableCores).clamp(1, _maxUsableCores);
    _coresController.text = _selectedCores.toString();

    if (mounted) setState(() {});
  }

  Future<void> _persist(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyBenchmarkCores, value);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('性能设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '加密核心数量 (${_selectedCores}/${_totalCores})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_maxUsableCores > 1)
            Slider(
              value: _selectedCores.toDouble(),
              min: 1,
              max: _maxUsableCores.toDouble(),
              divisions: (_maxUsableCores - 1).clamp(1, 100),
              label: _selectedCores.toString(),
              onChanged: (v) => _setCores(v.round()),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Text('当前设备可用核心数仅为 1，无法调整。', style: TextStyle(color: Colors.grey)),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _coresController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '核心数量',
              helperText: '范围: 1 ~ $_maxUsableCores',
            ),
            onSubmitted: (v) => _setCores(int.tryParse(v) ?? _selectedCores),
          ),
        ],
      ),
    );
  }
}

