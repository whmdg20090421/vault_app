import '../../encryption/vault_explorer_page.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../services/stats_service.dart';
import '../models/encryption_node.dart';
import 'local_index_service.dart';
import 'vault_manifest_service.dart';
import '../utils/aead_string.dart';
import '../../vfs/local_vfs.dart';
import '../../vfs/encrypted_vfs.dart';

class EncryptionTaskManager extends ChangeNotifier {
  static final EncryptionTaskManager _instance = EncryptionTaskManager._internal();

  factory EncryptionTaskManager() => _instance;

  int _activeWorkers = 0;
  int _maxWorkers = 2;
  final ReceivePort _globalReceivePort = ReceivePort();
  
  final List<EncryptionNode> _tasks = [];
  final List<EncryptionNode> _historyTasks = [];
  final Map<String, Isolate> _isolates = {};
  
  final Set<String> _archivingTasks = {};

  List<EncryptionNode> get tasks => List.unmodifiable(_tasks);
  List<EncryptionNode> get historyTasks => List.unmodifiable(_historyTasks);

  EncryptionTaskManager._internal() {
    _loadQueue();
    _loadHistory();
    _globalReceivePort.listen(_handleMessage);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _maxWorkers = prefs.getInt('encryption_cores') ?? (Platform.numberOfProcessors ~/ 2).clamp(1, 999);
  }

  /// 创建一个新的加密任务树（SubTask 1.2）
  Future<void> createEncryptionTask(String absolutePath, {Map<String, dynamic>? taskArgs}) async {
    final fileEntity = FileSystemEntity.typeSync(absolutePath);
    if (fileEntity == FileSystemEntityType.notFound) return;

    final taskId = const Uuid().v4();
    EncryptionNode rootNode;

    if (fileEntity == FileSystemEntityType.directory) {
      rootNode = _buildFolderNode(Directory(absolutePath), taskId);
    } else {
      rootNode = _buildFileNode(File(absolutePath), taskId);
    }
    
    rootNode.taskArgs = taskArgs;

    _tasks.add(rootNode);

    if (taskArgs != null &&
        taskArgs['vaultDirectoryPath'] is String &&
        taskArgs['masterKey'] != null) {
      try {
        final vaultDirectoryPath = taskArgs['vaultDirectoryPath'] as String;
        final encryptFilename = taskArgs['encryptFilename'] as bool? ?? false;
        final currentPath = taskArgs['currentPath'] as String? ?? '/';

        List<int> masterKeyList;
        if (taskArgs['masterKey'] is Uint8List) {
          masterKeyList = (taskArgs['masterKey'] as Uint8List).toList();
        } else if (taskArgs['masterKey'] is List<int>) {
          masterKeyList = (taskArgs['masterKey'] as List<int>).toList();
        } else {
          masterKeyList = (taskArgs['masterKey'] as List<dynamic>).cast<int>();
        }
        final masterKey = Uint8List.fromList(masterKeyList);

        final manifestService = VaultManifestService();
        final manifest = await manifestService.load(
          vaultDirectoryPath: vaultDirectoryPath,
          masterKey: masterKey,
          encryptFilename: encryptFilename,
        );
        final entries = Map<String, dynamic>.from(manifest['entries'] as Map);

        String basePath = currentPath;
        if (basePath.endsWith('/') && basePath.length > 1) {
          basePath = basePath.substring(0, basePath.length - 1);
        }

        void addNode(EncryptionNode node, String remotePath) {
          String absolutePath;
          if (node is FileNode) {
            absolutePath = node.absolutePath;
          } else if (node is FolderNode) {
            absolutePath = node.absolutePath;
          } else {
            absolutePath = '';
          }

          DateTime modified;
          try {
            modified = FileStat.statSync(absolutePath).modified;
          } catch (_) {
            modified = DateTime.fromMillisecondsSinceEpoch(0);
          }

          entries[remotePath] = {
            'type': node is FolderNode ? 'folder' : 'file',
            'plainSize': node.rawSize,
            'plainUpdatedAt': modified.toIso8601String(),
            'sourceAbsolutePathEnc': AeadString.encryptUtf8(
              key: masterKey,
              plaintext: absolutePath,
            ),
          };

          if (node is FolderNode) {
            for (final child in node.children) {
              final childRemote = remotePath == '/' ? '/${child.name}' : '$remotePath/${child.name}';
              addNode(child, childRemote);
            }
          }
        }

        final rootRemote = basePath == '/' ? '/${rootNode.name}' : '$basePath/${rootNode.name}';
        addNode(rootNode, rootRemote);

        manifest['entries'] = entries;
        await manifestService.save(
          vaultDirectoryPath: vaultDirectoryPath,
          masterKey: masterKey,
          encryptFilename: encryptFilename,
          manifest: manifest,
        );
      } catch (_) {}
    }

    await _saveQueue(); // 持久化（SubTask 1.3）
    notifyListeners();
    
    // TODO: 启动动态刷新机制（Task 3）
    pumpQueue();
  }

  FolderNode _buildFolderNode(Directory dir, [String? taskId]) {
    final folderName = dir.path.split(Platform.pathSeparator).last;
    final folderNode = FolderNode(
      taskId: taskId,
      name: folderName,
      absolutePath: dir.path,
    );

    try {
      final entities = dir.listSync();
      for (var entity in entities) {
        if (entity is Directory) {
          folderNode.children.add(_buildFolderNode(entity));
        } else if (entity is File) {
          folderNode.children.add(_buildFileNode(entity));
        }
      }
    } catch (e) {
      debugPrint('Error reading directory: $e');
    }

    folderNode.recalculateRawSize();
    return folderNode;
  }

  FileNode _buildFileNode(File file, [String? taskId]) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    int fileSize = 0;
    try {
      fileSize = file.lengthSync();
    } catch (e) {
      debugPrint('Error reading file size: $e');
    }

    return FileNode(
      taskId: taskId,
      name: fileName,
      absolutePath: file.path,
      rawSize: fileSize,
    );
  }

  /// 获取持久化文件路径（SubTask 1.3）
  Future<File> _getQueueFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/encryption_tasks.json');
  }

  Future<File> _getHistoryFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/encryption_history.json');
  }

  Future<void> _saveHistory() async {
    try {
      final file = await _getHistoryFile();
      final List<Map<String, dynamic>> jsonList = _historyTasks.map((t) => t.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving encryption history: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final file = await _getHistoryFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _historyTasks.clear();
        _historyTasks.addAll(jsonList.map((j) => EncryptionNode.fromJson(j as Map<String, dynamic>)));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading encryption history: $e');
    }
  }

  /// 保存全局任务列表到私有数据目录（SubTask 1.3）
  Future<void> _saveQueue() async {
    try {
      final file = await _getQueueFile();
      final List<Map<String, dynamic>> jsonList = _tasks.map((t) => t.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving encryption tasks: $e');
    }
  }

  /// 从私有数据目录读取全局任务列表（SubTask 1.3）
  Future<void> _loadQueue() async {
    try {
      final file = await _getQueueFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _tasks.clear();
        _tasks.addAll(jsonList.map((j) => EncryptionNode.fromJson(j as Map<String, dynamic>)));
        
        // 重启中断恢复，重置 pending_waiting（SubTask 2.3）
        _resetEncryptingToPending();
        
        notifyListeners();
        pumpQueue();
      }
    } catch (e) {
      debugPrint('Error loading encryption tasks: $e');
    }
  }

  void _resetEncryptingToPending() {
    bool changed = false;
    void resetNode(EncryptionNode node) {
      if (node.status == NodeStatus.encrypting) {
        node.status = NodeStatus.pending_waiting;
        changed = true;
      }
      if (node is FolderNode) {
        for (var child in node.children) {
          resetNode(child);
        }
      }
    }
    for (var task in _tasks) {
      resetNode(task);
    }
    if (changed) {
      _saveQueue();
    }
  }

  EncryptionNode? _findRootByNodeId(String nodeId) {
    for (final root in _tasks) {
      if (_findNodeById(root, nodeId) != null) return root;
    }
    return null;
  }

  EncryptionNode? _findNodeById(EncryptionNode current, String nodeId) {
    if (current is FileNode && current.absolutePath == nodeId) {
      return current;
    }
    if (current is FolderNode) {
      for (final child in current.children) {
        final found = _findNodeById(child, nodeId);
        if (found != null) return found;
      }
    }
    return null;
  }

  void _updateRootStatus(EncryptionNode root) {
    void updateNode(EncryptionNode node) {
      if (node is! FolderNode) return;
      
      bool hasError = false;
      bool hasPending = false;
      bool hasEncrypting = false;
      bool hasPaused = false;
      String? firstError;
      
      for (var child in node.children) {
        updateNode(child); // bottom up
        if (child.status == NodeStatus.error) {
          hasError = true;
          firstError ??= child.errorMessage;
        }
        if (child.status == NodeStatus.pending_waiting) hasPending = true;
        if (child.status == NodeStatus.encrypting) hasEncrypting = true;
        if (child.status == NodeStatus.pending_paused) hasPaused = true;
      }
      
      if (hasError) {
        node.status = NodeStatus.error;
        node.errorMessage = firstError;
      } else if (hasEncrypting) {
        node.status = NodeStatus.encrypting;
        node.errorMessage = null;
      } else if (hasPending) {
        node.status = NodeStatus.pending_waiting;
        node.errorMessage = null;
      } else if (hasPaused) {
        node.status = NodeStatus.pending_paused;
        node.errorMessage = null;
      } else {
        node.status = NodeStatus.completed;
        node.errorMessage = null;
      }
    }
    
    updateNode(root);

    if (root.status == NodeStatus.completed) {
      _checkAndArchiveRoot(root);
    }
  }

  Future<void> _checkAndArchiveRoot(EncryptionNode root) async {
    if (!_tasks.contains(root) || root.taskId == null) return;
    
    if (_archivingTasks.contains(root.taskId!)) return;
    _archivingTasks.add(root.taskId!);
    
    Future<bool> checkNode(EncryptionNode node) async {
      bool exists = false;
      if (node is FileNode) {
        exists = await File(node.absolutePath).exists();
      } else if (node is FolderNode) {
        exists = await Directory(node.absolutePath).exists();
        if (exists) {
          bool childrenExist = true;
          for (var child in node.children) {
            if (!await checkNode(child)) {
              childrenExist = false;
            }
          }
          if (!childrenExist) return false;
        }
      }
      if (!exists) {
        node.status = NodeStatus.error;
      }
      return exists;
    }
    
    bool allExist = await checkNode(root);
    
    if (allExist) {
      _tasks.remove(root);
      _historyTasks.insert(0, root);
      await _saveQueue();
      await _saveHistory();
    } else {
      _updateRootStatus(root); // 更新父节点状态为 error
      await _saveQueue();
    }
    
    _archivingTasks.remove(root.taskId!);
    notifyListeners();
  }

  Future<void> _handleMessage(dynamic message) async {
    if (message is Map<String, dynamic>) {
      final type = message['type'];
      final nodeId = message['nodeId'] as String;

      final root = _findRootByNodeId(nodeId);
      if (root == null) return;
      
      final node = _findNodeById(root, nodeId);
      if (node == null) return;

      if (type == 'done') {
        node.status = NodeStatus.completed;
        _activeWorkers--;
        _isolates.remove(nodeId);

        final vaultDirectoryPath = message['vaultDirectoryPath'] as String;
        final remotePath = message['remotePath'] as String;

        List<int> masterKeyList;
        if (root.taskArgs?['masterKey'] is Uint8List) {
          masterKeyList = (root.taskArgs!['masterKey'] as Uint8List).toList();
        } else if (root.taskArgs?['masterKey'] is List<int>) {
          masterKeyList = (root.taskArgs!['masterKey'] as List<int>).toList();
        } else {
          masterKeyList = (root.taskArgs?['masterKey'] as List<dynamic>? ?? const []).cast<int>();
        }
        final masterKey = Uint8List.fromList(masterKeyList);
        final encryptFilename = (root.taskArgs?['encryptFilename'] as bool?) ?? false;

        await LocalIndexService().updateFileIndex(
          vaultDirectoryPath: vaultDirectoryPath,
          remotePath: remotePath,
          cipherHashSha256: message['cipherHashSha256'] as String,
          cipherSize: message['cipherSize'] as int,
          cipherUpdatedAt: DateTime.parse(message['cipherUpdatedAt'] as String),
          plainHashSha256: message['plainHashSha256'] as String,
          plainSize: message['plainSize'] as int,
          plainUpdatedAt: DateTime.parse(message['plainUpdatedAt'] as String),
          sourceAbsolutePathEnc: Map<String, String>.from(message['sourceAbsolutePathEnc'] as Map),
        );

        final manifestService = VaultManifestService();
        final manifest = await manifestService.load(
          vaultDirectoryPath: vaultDirectoryPath,
          masterKey: masterKey,
          encryptFilename: encryptFilename,
        );
        final entries = Map<String, dynamic>.from(manifest['entries'] as Map);
        final normalizedRemotePath = remotePath.startsWith('/') ? remotePath : '/$remotePath';
        entries[normalizedRemotePath] = {
          'type': 'file',
          'plainSize': message['plainSize'],
          'plainUpdatedAt': message['plainUpdatedAt'],
          'plainHashSha256': message['plainHashSha256'],
          'cipherSize': message['cipherSize'],
          'cipherUpdatedAt': message['cipherUpdatedAt'],
          'cipherHashSha256': message['cipherHashSha256'],
          'sourceAbsolutePathEnc': message['sourceAbsolutePathEnc'],
        };
        manifest['entries'] = entries;
        await manifestService.save(
          vaultDirectoryPath: vaultDirectoryPath,
          masterKey: masterKey,
          encryptFilename: encryptFilename,
          manifest: manifest,
        );

        _updateRootStatus(root);
        _saveQueue();
        notifyListeners();
        pumpQueue();
      } else if (type == 'error') {
        node.status = NodeStatus.error;
        node.errorMessage = message['error'] as String?;
        _activeWorkers--;
        _isolates.remove(nodeId);
        
        _updateRootStatus(root);
        _saveQueue();
        notifyListeners();
        pumpQueue();
      }
    }
  }

  /// 暂停任务（父节点覆盖子节点）
  void pauseTask(EncryptionNode node) {
    void pauseRecursively(EncryptionNode n) {
      n.isPaused = true;
      if (n.status == NodeStatus.pending_waiting) {
        n.status = NodeStatus.pending_paused;
      }
      if (n is FolderNode) {
        for (var child in n.children) {
          pauseRecursively(child);
        }
      }
    }
    
    pauseRecursively(node);
    
    // 如果是根节点，更新根节点状态
    if (_tasks.contains(node)) {
      _updateRootStatus(node);
    } else {
      final root = _findRootOfNode(node);
      if (root != null) _updateRootStatus(root);
    }
    
    _saveQueue();
    notifyListeners();
  }

  /// 继续任务（父节点覆盖子节点）
  void resumeTask(EncryptionNode node) {
    void resumeRecursively(EncryptionNode n) {
      n.isPaused = false;
      if (n.status == NodeStatus.pending_paused) {
        n.status = NodeStatus.pending_waiting;
      }
      if (n is FolderNode) {
        for (var child in n.children) {
          resumeRecursively(child);
        }
      }
    }
    
    resumeRecursively(node);
    
    // 如果是根节点，更新根节点状态
    if (_tasks.contains(node)) {
      _updateRootStatus(node);
    } else {
      final root = _findRootOfNode(node);
      if (root != null) _updateRootStatus(root);
    }
    
    _saveQueue();
    notifyListeners();
    pumpQueue();
  }

  /// 移除任务
  void removeTask(EncryptionNode node) {
    if (_tasks.contains(node)) {
      // 如果有正在执行的子任务，可以考虑终止对应 Isolate，但这里简化处理，只从队列移除
      // 正在执行的 Isolate 会因为找不到 node 而在完成后忽略
      _tasks.remove(node);
      _saveQueue();
      notifyListeners();
      pumpQueue();
    } else {
      final root = _findRootOfNode(node);
      if (root != null) {
        final parent = _findParentOfNode(root, node);
        if (parent is FolderNode) {
          parent.children.remove(node);
          parent.recalculateRawSize();
          
          // 更新祖先的 size
          var p = _findParentOfNode(root, parent);
          while (p is FolderNode) {
            p.recalculateRawSize();
            p = _findParentOfNode(root, p);
          }
          if (root is FolderNode) {
            root.recalculateRawSize();
          }

          _updateRootStatus(root);
          _saveQueue();
          notifyListeners();
          pumpQueue();
        }
      }
    }
  }

  /// 移除历史记录（仅清除数据）
  void removeHistoryTask(EncryptionNode node) {
    if (_historyTasks.contains(node)) {
      _historyTasks.remove(node);
      _saveHistory();
      notifyListeners();
    } else {
      // 在历史记录中查找父节点并移除
      for (final root in _historyTasks) {
        if (_containsNode(root, node)) {
          final parent = _findParentOfNode(root, node);
          if (parent is FolderNode) {
            parent.children.remove(node);
            parent.recalculateRawSize();
            
            var p = _findParentOfNode(root, parent);
            while (p is FolderNode) {
              p.recalculateRawSize();
              p = _findParentOfNode(root, p);
            }
            if (root is FolderNode) {
              root.recalculateRawSize();
            }
            
            _saveHistory();
            notifyListeners();
          }
          break;
        }
      }
    }
  }

  /// 标记已修复：将该节点及其子节点下的 error 状态重置为 pending_waiting，并重试
  void markTaskAsFixed(EncryptionNode node) {
    void fixRecursively(EncryptionNode n) {
      if (n.status == NodeStatus.error) {
        n.status = NodeStatus.pending_waiting;
        n.errorMessage = null;
        n.isPaused = false;
      }
      if (n is FolderNode) {
        for (var child in n.children) {
          fixRecursively(child);
        }
      }
    }
    
    fixRecursively(node);
    
    if (_tasks.contains(node)) {
      _updateRootStatus(node);
    } else {
      final root = _findRootOfNode(node);
      if (root != null) _updateRootStatus(root);
    }
    
    _saveQueue();
    notifyListeners();
    pumpQueue();
  }

  FileNode? _findNextPendingNode(List<EncryptionNode> list) {
    for (final node in list) {
      if (node.isPaused) continue;

      if (node is FolderNode) {
        if (node.status == NodeStatus.pending_paused) continue;
        final found = _findNextPendingNode(node.children);
        if (found != null) return found;
      } else if (node is FileNode) {
        if (node.status == NodeStatus.pending_waiting) return node;
      }
    }
    return null;
  }

  EncryptionNode? _findRootOfNode(EncryptionNode targetNode) {
    for (final root in _tasks) {
      if (_containsNode(root, targetNode)) return root;
    }
    return null;
  }

  EncryptionNode? _findParentOfNode(EncryptionNode root, EncryptionNode targetNode) {
    if (root is FolderNode) {
      for (final child in root.children) {
        if (child == targetNode) return root;
        final found = _findParentOfNode(child, targetNode);
        if (found != null) return found;
      }
    }
    return null;
  }

  bool _containsNode(EncryptionNode root, EncryptionNode targetNode) {
    if (root == targetNode) return true;
    if (root is FolderNode) {
      for (final child in root.children) {
        if (_containsNode(child, targetNode)) return true;
      }
    }
    return false;
  }

  void pumpQueue() async {
    await _loadSettings();
    while (_activeWorkers < _maxWorkers) {
      final node = _findNextPendingNode(_tasks);
      if (node == null) break;

      // 立即标记为 encrypting 避免被其他 pumpQueue 调用重复获取
      node.status = NodeStatus.encrypting;
      _activeWorkers++;
      notifyListeners();

      final root = _findRootOfNode(node);
      if (root == null || root.taskArgs == null || root.taskArgs!['masterKey'] == null || root.taskArgs!['vaultDirectoryPath'] == null) {
        node.status = NodeStatus.error;
        node.errorMessage = 'Missing task arguments or root node';
        _activeWorkers--;
        await _saveQueue();
        notifyListeners();
        continue;
      }

      final file = File(node.absolutePath);
      if (!await file.exists()) {
        node.status = NodeStatus.error;
        node.errorMessage = 'File not found';
        _activeWorkers--;
        await _saveQueue();
        notifyListeners();
        continue;
      }

      // 构建目标相对路径（针对 Vault 根目录）
      // SubTask 2.2 计算 remotePath。如果 root 是文件，remotePath 就是 '/${node.name}'
      // 如果 root 是文件夹，remotePath 就是 '/${root.name}/.../${node.name}'
      String remotePath = _buildRemotePath(root, node);
      
      List<int> masterKeyList;
      if (root.taskArgs!['masterKey'] is Uint8List) {
        masterKeyList = root.taskArgs!['masterKey'] as Uint8List;
      } else if (root.taskArgs!['masterKey'] is List<int>) {
        masterKeyList = root.taskArgs!['masterKey'] as List<int>;
      } else {
        masterKeyList = (root.taskArgs!['masterKey'] as List<dynamic>).cast<int>();
      }
      
      final args = {
        'sendPort': _globalReceivePort.sendPort,
        'taskId': root.taskId,
        'nodeId': node.absolutePath, // unique enough for file inside the same tree
        'absolutePath': node.absolutePath,
        'vaultDirectoryPath': root.taskArgs!['vaultDirectoryPath'],
        'masterKey': Uint8List.fromList(masterKeyList),
        'encryptFilename': root.taskArgs!['encryptFilename'] ?? false,
        'remotePath': remotePath,
      };

      Isolate.spawn(_encryptionWorker, args).then((isolate) {
        _isolates[node.absolutePath] = isolate;
      });
    }
  }

  String _buildRemotePath(EncryptionNode root, FileNode targetNode) {
    String basePath = root.taskArgs?['currentPath'] as String? ?? '/';
    if (basePath.endsWith('/')) {
      basePath = basePath.substring(0, basePath.length - 1);
    }

    if (root == targetNode) {
      return '$basePath/${root.name}';
    }
    
    String? searchPath(EncryptionNode current, String currentPath) {
      if (current == targetNode) return currentPath;
      if (current is FolderNode) {
        for (final child in current.children) {
          final found = searchPath(child, '$currentPath/${child.name}');
          if (found != null) return found;
        }
      }
      return null;
    }
    
    return searchPath(root, '$basePath/${root.name}') ?? '$basePath/${targetNode.name}';
  }
}

Future<void> _encryptionWorker(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final nodeId = args['nodeId'] as String;
  
  try {
    final absolutePath = args['absolutePath'] as String;
    final vaultDirectoryPath = args['vaultDirectoryPath'] as String;
    final masterKey = args['masterKey'] as Uint8List;
    final encryptFilename = args['encryptFilename'] as bool;
    final remotePath = args['remotePath'] as String;

    final file = File(absolutePath);
    if (!await file.exists()) {
      throw Exception('File not found');
    }

    final size = await file.length();
    final plainUpdatedAt = await file.lastModified();
    final plainHashSha256 = (await sha256.bind(file.openRead()).first).toString();

    final localVfs = LocalVfs(rootPath: vaultDirectoryPath);
    final encryptedVfs = EncryptedVfs(
      baseVfs: localVfs,
      masterKey: masterKey,
      encryptFilename: encryptFilename,
    );
    await encryptedVfs.initEncryptedDomain('/');

    final indexFile = File('$vaultDirectoryPath/local_index.json');
    Map<String, dynamic> indexData = {};
    if (await indexFile.exists()) {
      try {
        final content = await indexFile.readAsString();
        if (content.isNotEmpty) {
          indexData = jsonDecode(content) as Map<String, dynamic>;
        }
      } catch (_) {}
    }

    bool skipEncryption = false;
    String? copyFromRemotePath;

    for (final entry in indexData.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final map = Map<String, dynamic>.from(value as Map);
      if (map['plainHashSha256'] != plainHashSha256) continue;
      final sourceEnc = map['sourceAbsolutePathEnc'];
      if (sourceEnc is Map) {
        try {
          final decryptedPath = AeadString.decryptUtf8(
            key: masterKey,
            payload: Map<String, dynamic>.from(sourceEnc as Map),
          );
          if (decryptedPath == absolutePath) {
            skipEncryption = true;
            copyFromRemotePath = entry.key;
            break;
          } else {
            skipEncryption = true;
            copyFromRemotePath = entry.key;
          }
        } catch (_) {}
      } else {
        skipEncryption = true;
        copyFromRemotePath = entry.key;
      }
    }

    if (skipEncryption && copyFromRemotePath != null && copyFromRemotePath != remotePath) {
      final oldReal = encryptedVfs.getRealPath(copyFromRemotePath);
      final newReal = encryptedVfs.getRealPath(remotePath);
      final oldFile = File(localVfs.getRealPath(oldReal));
      final newFile = File(localVfs.getRealPath(newReal));
      if (await oldFile.exists()) {
        if (!await newFile.parent.exists()) {
          await newFile.parent.create(recursive: true);
        }
        await oldFile.copy(newFile.path);
      } else {
        skipEncryption = false;
      }
    }

    if (!skipEncryption) {
      final stream = file.openRead();
      await encryptedVfs.uploadStream(stream, size, remotePath);
    }

    final encryptedRemotePath = encryptedVfs.getRealPath(remotePath);
    final encryptedLocalPath = localVfs.getRealPath(encryptedRemotePath);
    final encryptedFile = File(encryptedLocalPath);
    final cipherUpdatedAt = await encryptedFile.lastModified();
    final cipherSize = await encryptedFile.length();
    final cipherHashSha256 = (await sha256.bind(encryptedFile.openRead()).first).toString();

    final sourceAbsolutePathEnc = AeadString.encryptUtf8(
      key: masterKey,
      plaintext: absolutePath,
    );

    sendPort.send({
      'type': 'done',
      'nodeId': nodeId,
      'vaultDirectoryPath': vaultDirectoryPath,
      'remotePath': remotePath,
      'cipherHashSha256': cipherHashSha256,
      'cipherSize': cipherSize,
      'cipherUpdatedAt': cipherUpdatedAt.toIso8601String(),
      'plainHashSha256': plainHashSha256,
      'plainSize': size,
      'plainUpdatedAt': plainUpdatedAt.toIso8601String(),
      'sourceAbsolutePathEnc': sourceAbsolutePathEnc,
    });
  } catch (e) {
    sendPort.send({
      'type': 'error',
      'nodeId': nodeId,
      'error': e.toString(),
    });
  }
}
