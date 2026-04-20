import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/export.dart' as pc;
import '../theme/app_theme.dart';

import 'models/vault_config.dart';
import 'performance_settings_page.dart';
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
  int _pbkdf2Iterations = 100000;
  
  int _argon2Iterations = 3;
  int _argon2Memory = 4096; // 4 MB
  int _argon2Parallelism = 4;

  int _scryptN = 16384; // 2^14
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
    
    // 强制让出执行权，让 UI 渲染出 CircularProgressIndicator
    await Future.delayed(Duration.zero);

    try {
      final name = _nameController.text.trim();
      final password = _passwordController.text;
      final salt = _generateRandomString(16);
      final nonce = _generateRandomString(12);
      final wrappedDekNonce = _generateRandomString(12);
      
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

      final validationCiphertext = await CryptoUtils.computeValidationCiphertextAsync(
        password: password,
        saltBase64: salt,
        kdfType: _selectedKDF,
        kdfParams: kdfParams,
        nonceBase64: nonce,
        algorithm: _selectedAlgorithm,
      );

      final kek = await CryptoUtils.deriveKeyAsync(
        password: password,
        saltBase64: salt,
        kdfType: _selectedKDF,
        kdfParams: kdfParams,
      );

      final random = Random.secure();
      final dek = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));

      final wrappedDekCipher = CryptoUtils.encrypt(
        key: kek,
        nonce: base64Url.decode(wrappedDekNonce),
        plaintext: dek,
        algorithm: _selectedAlgorithm,
      );

      final config = VaultConfig(
        version: 2,
        name: name,
        algorithm: _selectedAlgorithm,
        kdf: _selectedKDF,
        kdfParams: kdfParams,
        encryptFilename: _encryptFilename,
        salt: salt,
        nonce: nonce,
        validationCiphertext: validationCiphertext,
        wrappedDekNonce: wrappedDekNonce,
        wrappedDekCiphertext: base64Encode(wrappedDekCipher),
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
      builder: (context) => BenchmarkDialog(vaultDirectoryPath: widget.vaultDirectoryPath),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('配置保险箱'.toUpperCase()),
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: 'Benchmark',
            onPressed: _showBenchmarkDialog,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Performance Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PerformanceSettingsPage()),
              );
            },
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
                  border: Border.all(color: Theme.of(context).isCyberpunk ? const Color(0xFF00E5FF) : Colors.white24),
                  borderRadius: Theme.of(context).isCyberpunk ? BorderRadius.zero : BorderRadius.circular(8),
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
  final String vaultDirectoryPath;

  const BenchmarkDialog({super.key, required this.vaultDirectoryPath});

  @override
  State<BenchmarkDialog> createState() => _BenchmarkDialogState();
}

class _BenchmarkDialogState extends State<BenchmarkDialog> {
  String _selectedAlgorithm = 'AES-256-GCM';
  final List<String> _algorithms = ['AES-256-GCM', 'ChaCha20-Poly1305'];
  
  bool _isRunning = false;
  double _progress = 0.0;
  String _result = '';
  String _status = '';
  String _filePath = '';
  int _doneBytes = 0;
  int _totalBytes = 0;
  bool _isCancelled = false;

  File? _benchmarkFile;
  BenchmarkTask? _currentTask;

  Future<void> _runBenchmark() async {
    if (!mounted) return;
    setState(() {
      _isRunning = true;
      _isCancelled = false;
      _progress = 0.0;
      _result = '';
      _status = '';
      _filePath = '';
      _doneBytes = 0;
      _totalBytes = 500 * 1024 * 1024;
    });

    IOSink? inputSink;

    try {
      final suffix = DateTime.now().millisecondsSinceEpoch.toString();
      final inputFile = File('${widget.vaultDirectoryPath}/benchmark_$suffix.bin');
      _benchmarkFile = inputFile;
      _filePath = inputFile.path;

      const chunkSize = 1024 * 1024;
      const totalChunks = 500;

      final random = Random.secure();
      final chunkData = Uint8List(chunkSize);
      for (int i = 0; i < chunkSize; i++) {
        chunkData[i] = random.nextInt(256);
      }

      setState(() {
        _status = '正在生成测试文件 (Generating): 0 / 500 MB';
        _progress = 0.0;
      });

      inputSink = inputFile.openWrite();
      var writtenBytes = 0;
      for (int i = 0; i < totalChunks; i++) {
        if (!mounted || _isCancelled) return;
        inputSink.add(chunkData);
        writtenBytes += chunkSize;
        if (i % 10 == 0) {
          final mbDone = writtenBytes / (1024 * 1024);
          setState(() {
            _status = '正在生成测试文件 (Generating): ${mbDone.toStringAsFixed(0)} / 500 MB';
            _progress = (writtenBytes / _totalBytes).clamp(0.0, 1.0) * 0.2;
          });
          await Future.delayed(Duration.zero);
        }
      }
      await inputSink.close();
      inputSink = null;

      if (!mounted || _isCancelled) return;
      setState(() {
        _status = '正在加密测试文件 (Encrypting): 0 / 500 MB';
        _progress = 0.2;
      });

      final key = Uint8List(32);
      for (int i = 0; i < 32; i++) key[i] = i;
      final baseNonce = Uint8List(12);
      for (int i = 0; i < 12; i++) baseNonce[i] = i;

      final prefs = await SharedPreferences.getInstance();
      final totalCores = Platform.numberOfProcessors;
      final maxUsableCores = (totalCores - 1).clamp(1, totalCores);
      final configuredCores = prefs.getInt('benchmark_cores') ?? maxUsableCores;
      final workerCount = configuredCores.clamp(1, maxUsableCores);

      _currentTask = BenchmarkTask();
      final stopwatch = Stopwatch()..start();
      await _currentTask!.runParallelEncryption(
        filePath: inputFile.path,
        totalBytes: _totalBytes,
        chunkSize: chunkSize,
        totalChunks: totalChunks,
        workerCount: workerCount,
        algorithm: _selectedAlgorithm,
        key: key,
        baseNonce: baseNonce,
        onProgress: (bytesDone) {
          if (!mounted) return;
          _doneBytes = bytesDone;
          final mbDone = _doneBytes / (1024 * 1024);
          setState(() {
            _status = '正在加密测试文件 (Encrypting): ${mbDone.toStringAsFixed(0)} / 500 MB';
            _progress = (0.2 + (_doneBytes / _totalBytes) * 0.8).clamp(0.0, 1.0);
          });
        },
      );
      stopwatch.stop();

      if (!mounted) return;
      
      if (_isCancelled || _currentTask?.isCancelled == true) {
        _currentTask = null;
        setState(() {
          _isRunning = false;
          _status = '已取消 (Cancelled)';
        });
        return;
      }
      
      _currentTask = null;

      final seconds = stopwatch.elapsedMilliseconds / 1000.0;
      final speed = 500.0 / seconds;

      setState(() {
        _progress = 1.0;
        _status = '完成 (Done)';
        _result = '速度 (Speed): ${speed.toStringAsFixed(2)} MB/s\n耗时 (Time): ${seconds.toStringAsFixed(2)} s';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = 'Error: $e';
      });
    } finally {
      try {
        await inputSink?.close();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _currentTask?.cancel();
    final file = _benchmarkFile;
    if (file != null) {
      file.exists().then((exists) {
        if (exists) file.delete();
      });
    }
    super.dispose();
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
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_status),
              ],
              if (_filePath.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _filePath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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
          onPressed: () {
            if (_isRunning) {
              _isCancelled = true;
              _currentTask?.cancel();
              setState(() {
                _isRunning = false;
                _status = '已取消 (Cancelled)';
              });
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Text(_isRunning ? '取消 (Cancel)' : '关闭 (Close)'),
        ),
        ElevatedButton(
          onPressed: _isRunning ? null : _runBenchmark,
          child: const Text('开始 (Start)'),
        ),
      ],
    );
  }
}

class BenchmarkTask {
  final List<Isolate> _isolates = [];
  bool isCancelled = false;
  final Completer<void> _completer = Completer<void>();

  void cancel() {
    isCancelled = true;
    for (var isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  Future<void> runParallelEncryption({
    required String filePath,
    required int totalBytes,
    required int chunkSize,
    required int totalChunks,
    required int workerCount,
    required String algorithm,
    required Uint8List key,
    required Uint8List baseNonce,
    required void Function(int bytesDone) onProgress,
  }) async {
    final receivePort = ReceivePort();

    final chunksPerWorker = (totalChunks / workerCount).ceil();
    var bytesDone = 0;
    var doneWorkers = 0;

    final subscription = receivePort.listen((message) {
      if (message is Map) {
        final type = message['type'];
        if (type == 'progress') {
          final bytes = message['bytes'] as int;
          bytesDone += bytes;
          if (bytesDone > totalBytes) bytesDone = totalBytes;
          onProgress(bytesDone);
        } else if (type == 'done') {
          doneWorkers += 1;
          if (doneWorkers >= workerCount && !_completer.isCompleted) {
            _completer.complete();
          }
        }
      }
    });

    for (int workerId = 0; workerId < workerCount; workerId++) {
      if (isCancelled) break;
      final startChunk = workerId * chunksPerWorker;
      if (startChunk >= totalChunks) {
        receivePort.sendPort.send({'type': 'done'});
        continue;
      }
      final endChunk = min(totalChunks, startChunk + chunksPerWorker);

      final args = <String, dynamic>{
        'sendPort': receivePort.sendPort,
        'filePath': filePath,
        'startChunk': startChunk,
        'endChunk': endChunk,
        'chunkSize': chunkSize,
        'algorithm': algorithm,
        'key': key,
        'baseNonce': baseNonce,
      };

      final isolate = await Isolate.spawn(_benchmarkEncryptWorker, args);
      if (isCancelled) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolates.add(isolate);
      }
    }

    await _completer.future;
    await subscription.cancel();
    receivePort.close();
  }
}

Uint8List _nonceWithCounter(Uint8List base, int counter) {
  final nonce = Uint8List.fromList(base);
  final bd = ByteData.sublistView(nonce);
  bd.setUint64(4, counter, Endian.big);
  return nonce;
}

dynamic _createCipher(String algorithm) {
  if (algorithm == 'AES-256-GCM') {
    return pc.GCMBlockCipher(pc.AESEngine());
  }
  if (algorithm == 'ChaCha20-Poly1305') {
    return pc.ChaCha20Poly1305(pc.ChaCha7539Engine(), pc.Poly1305());
  }
  throw Exception('Unsupported algorithm: $algorithm');
}

void _benchmarkEncryptWorker(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final filePath = args['filePath'] as String;
  final startChunk = args['startChunk'] as int;
  final endChunk = args['endChunk'] as int;
  final chunkSize = args['chunkSize'] as int;
  final algorithm = args['algorithm'] as String;
  final key = Uint8List.fromList(args['key'] as Uint8List);
  final baseNonce = Uint8List.fromList(args['baseNonce'] as Uint8List);

  RandomAccessFile? raf;
  try {
    raf = await File(filePath).open();
    await raf.setPosition(startChunk * chunkSize);

    final cipher = _createCipher(algorithm);
    var bytesSinceLastReport = 0;

    for (int chunkIndex = startChunk; chunkIndex < endChunk; chunkIndex++) {
      final data = await raf.read(chunkSize);
      if (data.isEmpty) break;

      final nonce = _nonceWithCounter(baseNonce, chunkIndex);
      final params = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));

      cipher.reset();
      cipher.init(true, params);
      final out = Uint8List(cipher.getOutputSize(data.length));
      var outLen = cipher.processBytes(data, 0, data.length, out, 0);
      outLen += cipher.doFinal(out, outLen);

      bytesSinceLastReport += data.length;
      if (bytesSinceLastReport >= 4 * 1024 * 1024) {
        sendPort.send({'type': 'progress', 'bytes': bytesSinceLastReport});
        bytesSinceLastReport = 0;
      }
    }

    if (bytesSinceLastReport > 0) {
      sendPort.send({'type': 'progress', 'bytes': bytesSinceLastReport});
    }
  } catch (e) {
    sendPort.send({'type': 'progress', 'bytes': 0});
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
    sendPort.send({'type': 'done'});
  }
}
