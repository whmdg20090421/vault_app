import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

import 'models/vault_config.dart';
import 'utils/crypto_utils.dart';

class VaultConfigPage extends StatefulWidget {
  final String vaultDirectoryPath;

  const VaultConfigPage({super.key, required this.vaultDirectoryPath});

  @override
  State<VaultConfigPage> createState() => _VaultConfigPageState();
}

class _VaultConfigPageState extends State<VaultConfigPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  String _selectedAlgorithm = 'AES-256-GCM';
  String _selectedKDF = 'PBKDF2';
  bool _encryptFilename = true;

  // KDF Parameters
  int _pbkdf2Iterations = 600000;
  
  int _argon2Iterations = 3;
  int _argon2Memory = 65536; // 64 MB
  int _argon2Parallelism = 4;

  int _scryptN = 1048576; // 2^20
  int _scryptR = 8;
  int _scryptP = 1;

  final List<String> _algorithms = ['AES-256-GCM', 'ChaCha20-Poly1305'];
  final List<String> _kdfs = ['PBKDF2', 'Argon2id', 'Scrypt'];

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码不匹配 (Passwords do not match)')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final name = _nameController.text.trim();
      final password = _passwordController.text;
      final salt = _generateRandomString(16);
      final nonce = _generateRandomString(12);
      
      Map<String, dynamic> kdfParams = {};
      if (_selectedKDF == 'PBKDF2') {
        kdfParams = {'iterations': _pbkdf2Iterations};
      } else if (_selectedKDF == 'Argon2id') {
        kdfParams = {
          'iterations': _argon2Iterations,
          'memory': _argon2Memory,
          'parallelism': _argon2Parallelism,
        };
      } else if (_selectedKDF == 'Scrypt') {
        kdfParams = {
          'N': _scryptN,
          'r': _scryptR,
          'p': _scryptP,
        };
      }

      // Derive key and generate validation ciphertext
      final derivedKey = CryptoUtils.deriveKey(
        password: password,
        saltBase64: salt,
        kdfType: _selectedKDF,
        kdfParams: kdfParams,
      );

      final nonceBytes = base64Url.decode(nonce);
      final magicPlaintext = Uint8List.fromList(utf8.encode('vault_magic_encrypted'));
      final encryptedMagic = CryptoUtils.encrypt(
        key: derivedKey,
        nonce: nonceBytes,
        plaintext: magicPlaintext,
        algorithm: _selectedAlgorithm,
      );
      
      final validationCiphertext = base64Encode(encryptedMagic);

      final config = VaultConfig(
        name: name,
        algorithm: _selectedAlgorithm,
        kdf: _selectedKDF,
        kdfParams: kdfParams,
        encryptFilename: _encryptFilename,
        salt: salt,
        nonce: nonce,
        validationCiphertext: validationCiphertext,
      );

      final configFile = File('${widget.vaultDirectoryPath}/vault_config.json');
      await configFile.writeAsString(jsonEncode(config.toJson()));

      // Save path to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final vaultPaths = prefs.getStringList('vault_paths') ?? [];
      if (!vaultPaths.contains(widget.vaultDirectoryPath)) {
        vaultPaths.add(widget.vaultDirectoryPath);
        await prefs.setStringList('vault_paths', vaultPaths);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置保存成功 (Configuration saved)')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _generateRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }

  Widget _buildKDFParams() {
    if (_selectedKDF == 'PBKDF2') {
      return TextFormField(
        initialValue: _pbkdf2Iterations.toString(),
        decoration: const InputDecoration(labelText: 'Iterations'),
        keyboardType: TextInputType.number,
        onChanged: (v) => _pbkdf2Iterations = int.tryParse(v) ?? _pbkdf2Iterations,
      );
    } else if (_selectedKDF == 'Argon2id') {
      return Column(
        children: [
          TextFormField(
            initialValue: _argon2Iterations.toString(),
            decoration: const InputDecoration(labelText: 'Iterations'),
            keyboardType: TextInputType.number,
            onChanged: (v) => _argon2Iterations = int.tryParse(v) ?? _argon2Iterations,
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _argon2Memory.toString(),
            decoration: const InputDecoration(labelText: 'Memory (KB)'),
            keyboardType: TextInputType.number,
            onChanged: (v) => _argon2Memory = int.tryParse(v) ?? _argon2Memory,
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _argon2Parallelism.toString(),
            decoration: const InputDecoration(labelText: 'Parallelism'),
            keyboardType: TextInputType.number,
            onChanged: (v) => _argon2Parallelism = int.tryParse(v) ?? _argon2Parallelism,
          ),
        ],
      );
    } else if (_selectedKDF == 'Scrypt') {
      return Column(
        children: [
          TextFormField(
            initialValue: _scryptN.toString(),
            decoration: const InputDecoration(labelText: 'N (Cost factor)'),
            keyboardType: TextInputType.number,
            onChanged: (v) => _scryptN = int.tryParse(v) ?? _scryptN,
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _scryptR.toString(),
            decoration: const InputDecoration(labelText: 'r (Block size)'),
            keyboardType: TextInputType.number,
            onChanged: (v) => _scryptR = int.tryParse(v) ?? _scryptR,
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _scryptP.toString(),
            decoration: const InputDecoration(labelText: 'p (Parallelization)'),
            keyboardType: TextInputType.number,
            onChanged: (v) => _scryptP = int.tryParse(v) ?? _scryptP,
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  void _showBenchmarkDialog() {
    showDialog(
      context: context,
      builder: (context) => const BenchmarkDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('配置保险箱'),
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: 'Benchmark',
            onPressed: _showBenchmarkDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '保险箱名称 (Vault Name)'),
                validator: (v) => v == null || v.isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: '密码 (Password)'),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(labelText: '确认密码 (Confirm Password)'),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? '请再次输入密码' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedAlgorithm,
                decoration: const InputDecoration(labelText: '加密算法 (Algorithm)'),
                items: _algorithms.map((algo) {
                  return DropdownMenuItem(value: algo, child: Text(algo));
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedAlgorithm = v);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedKDF,
                decoration: const InputDecoration(labelText: '密钥派生函数 (KDF)'),
                items: _kdfs.map((kdf) {
                  return DropdownMenuItem(value: kdf, child: Text(kdf));
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedKDF = v);
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('KDF 参数 (KDF Parameters)', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _buildKDFParams(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('加密文件名 (Encrypt Filenames)'),
                value: _encryptFilename,
                onChanged: (v) => setState(() => _encryptFilename = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveConfig,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator()
                    : const Text('创建并保存 (Create and Save)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BenchmarkDialog extends StatefulWidget {
  const BenchmarkDialog({super.key});

  @override
  State<BenchmarkDialog> createState() => _BenchmarkDialogState();
}

class _BenchmarkDialogState extends State<BenchmarkDialog> {
  String _selectedAlgorithm = 'AES-256-GCM';
  final List<String> _algorithms = ['AES-256-GCM', 'ChaCha20-Poly1305'];
  
  bool _isRunning = false;
  double _progress = 0.0;
  String _result = '';

  Future<void> _runBenchmark() async {
    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _result = '';
    });

    File? inputFile;
    File? outputFile;
    IOSink? inputSink;
    IOSink? outputSink;

    try {
      final tempDir = Directory.systemTemp;
      final suffix = DateTime.now().millisecondsSinceEpoch.toString();
      inputFile = File('${tempDir.path}/benchmark_in_$suffix.tmp');
      outputFile = File('${tempDir.path}/benchmark_out_$suffix.tmp');

      const chunkSize = 1024 * 1024; // 1MB
      const totalChunks = 500; // 500MB

      final random = Random.secure();
      final chunkData = Uint8List(chunkSize);
      for (int i = 0; i < chunkSize; i++) {
        chunkData[i] = random.nextInt(256);
      }

      // 1. Write dummy data
      inputSink = inputFile.openWrite();
      for (int i = 0; i < totalChunks; i++) {
        inputSink.add(chunkData);
        if (i % 50 == 0) {
          setState(() => _progress = (i / totalChunks) * 0.2);
          await Future.delayed(Duration.zero);
        }
      }
      await inputSink.close();
      inputSink = null;

      setState(() => _progress = 0.2);

      // 2. Setup cipher
      final key = Uint8List(32);
      for (int i = 0; i < 32; i++) key[i] = i;
      final nonce = Uint8List(12);
      for (int i = 0; i < 12; i++) nonce[i] = i;

      dynamic cipher;
      if (_selectedAlgorithm == 'AES-256-GCM') {
        cipher = pc.GCMBlockCipher(pc.AESEngine());
      } else {
        cipher = pc.ChaCha20Poly1305(pc.ChaCha7539Engine(), pc.Poly1305());
      }

      final params = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));

      final inputStream = inputFile.openRead();
      outputSink = outputFile.openWrite();

      Uint8List processChunk(Uint8List input) {
        final out = Uint8List(cipher.getOutputSize(input.length));
        var outLen = cipher.processBytes(input, 0, input.length, out, 0);
        outLen += cipher.doFinal(out, outLen);
        return out.sublist(0, outLen);
      }

      final stopwatch = Stopwatch()..start();

      int chunksProcessed = 0;

      await for (final chunk in inputStream) {
        final uint8Chunk = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        
        cipher.reset();
        cipher.init(true, params);
        final encryptedChunk = processChunk(uint8Chunk);
        outputSink.add(encryptedChunk);

        chunksProcessed++;

        if (chunksProcessed % 10 == 0) {
          setState(() {
            _progress = 0.2 + (chunksProcessed / totalChunks) * 0.8;
          });
          await Future.delayed(Duration.zero);
        }
      }

      await outputSink.close();
      outputSink = null;
      stopwatch.stop();

      final seconds = stopwatch.elapsedMilliseconds / 1000.0;
      final speed = 500.0 / seconds;

      setState(() {
        _progress = 1.0;
        _result = '速度 (Speed): ${speed.toStringAsFixed(2)} MB/s\n耗时 (Time): ${seconds.toStringAsFixed(2)} s';
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    } finally {
      try {
        await inputSink?.close();
      } catch (_) {}
      try {
        await outputSink?.close();
      } catch (_) {}
      try {
        if (inputFile != null && await inputFile.exists()) {
          await inputFile.delete();
        }
      } catch (_) {}
      try {
        if (outputFile != null && await outputFile.exists()) {
          await outputFile.delete();
        }
      } catch (_) {}
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('性能测试 (Benchmark)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('测试加密 500MB 数据的速度'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedAlgorithm,
              decoration: const InputDecoration(labelText: '加密算法 (Algorithm)'),
              items: _algorithms.map((algo) {
                return DropdownMenuItem(value: algo, child: Text(algo));
              }).toList(),
              onChanged: _isRunning
                  ? null
                  : (v) {
                      if (v != null) setState(() => _selectedAlgorithm = v);
                    },
            ),
            const SizedBox(height: 16),
            if (_isRunning) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(1)}%'),
            ],
            if (_result.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(_result, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭 (Close)'),
        ),
        ElevatedButton(
          onPressed: _isRunning ? null : _runBenchmark,
          child: const Text('开始 (Start)'),
        ),
      ],
    );
  }
}
