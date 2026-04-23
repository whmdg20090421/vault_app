import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../encryption/utils/base64url_utils.dart';
import '../encryption/utils/crypto_utils.dart';
import '../encryption/utils/chunk_crypto.dart';
import '../utils/dfs_format_utils.dart';
import 'virtual_file_system.dart';

/// 加密版 VFS 实现
/// 包装基础的 VFS，实现文件/目录名透明加解密与加密状态的拦截
class EncryptedVfs implements VirtualFileSystem {
  static const String _markerFileName = '.vault_marker';
  static const String _algorithm = 'AES-256-GCM';

  // Chunking constants for file content encryption
  static const int _defaultChunkSize = 65536; // 64KB plaintext chunk
  static const int _chunkMacLength = 16;
  static const int _fileIdLength = 16;
  static final Uint8List _magicHeader = Uint8List.fromList([0x56, 0x41, 0x55, 0x4C, 0x54, 0x01]); // VAULT\x01
  static const int _magicHeaderLength = 6;
  static const int _v2HeaderLength = _magicHeaderLength + 4 + _fileIdLength; // 26 bytes

  final VirtualFileSystem baseVfs;
  final Uint8List masterKey;
  final bool encryptFilename;
  late final ChunkCrypto _chunkCrypto;

  // 缓存虚拟（解密）路径到真实（加密）路径的映射
  final Map<String, String> _virtualToReal = {'/': '/'};
  final Map<String, String> _realToVirtual = {'/': '/'};

  // 缓存处于加密域中的虚拟路径
  final Set<String> _encryptedDomains = {};
  
  // Manifest cache for storing chunk sizes and plaintext sizes
  Map<String, dynamic> _manifestEntries = {};
  bool _manifestLoaded = false;
  static const String _manifestPath = '/.vault_manifest';

  EncryptedVfs({
    required this.baseVfs,
    required this.masterKey,
    this.encryptFilename = true,
  }) {
    if (masterKey.length != 32) {
      throw ArgumentError('MasterKey must be 32 bytes for AES-256-GCM');
    }
    _chunkCrypto = ChunkCrypto(masterKey: masterKey);
  }

  /// 规范化路径，确保以 '/' 开头且除了根目录外不以 '/' 结尾
  String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    String normalized = path.replaceAll(RegExp(r'/+'), '/');
    if (normalized != '/' && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    return normalized;
  }

  /// 获取路径的父目录
  String _getParentPath(String normalizedPath) {
    if (normalizedPath == '/') return '/';
    int lastSlash = normalizedPath.lastIndexOf('/');
    if (lastSlash == 0) return '/';
    return normalizedPath.substring(0, lastSlash);
  }

  /// 检查给定虚拟路径是否处于加密域中
  bool _isEncryptedDomain(String virtualPath) {
    String current = _normalizePath(virtualPath);
    while (true) {
      if (_encryptedDomains.contains(current)) {
        return true;
      }
      if (current == '/') break;
      current = _getParentPath(current);
    }
    return false;
  }

  Future<void> _loadManifest() async {
    if (_manifestLoaded) return;
    _manifestLoaded = true;
    try {
      final realManifestPath = getRealPath(_manifestPath);
      final rawStream = await baseVfs.open(realManifestPath, start: 0, end: 25);
      final headerBytes = <int>[];
      await for (final chunk in rawStream) {
        headerBytes.addAll(chunk);
      }
      
      bool isEncrypted = false;
      if (headerBytes.length >= 6) {
        bool magicMatch = true;
        for (int i = 0; i < 6; i++) {
          if (headerBytes[i] != _magicHeader[i]) magicMatch = false;
        }
        isEncrypted = magicMatch;
      }
      
      Stream<List<int>> stream;
      if (isEncrypted) {
        stream = await this.open(_manifestPath);
      } else {
        stream = await baseVfs.open(realManifestPath);
      }
      
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      if (chunks.isNotEmpty) {
        final jsonMap = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
        
        // 兼容新旧格式
        Map? entriesRaw;
        if (jsonMap.containsKey('目录')) {
           entriesRaw = jsonMap['目录'];
        } else if (jsonMap.containsKey('entries')) {
           entriesRaw = jsonMap['entries'];
        }
        
        if (entriesRaw is Map) {
          _manifestEntries = Map<String, dynamic>.from(entriesRaw);
        }
        
        // 如果读取成功且是明文旧版，且当前是在加密域，则触发保存以转换为加密新版
        if (!isEncrypted && _isEncryptedDomain('/')) {
           // 延迟执行避免阻塞
           Future.microtask(() => _saveManifest());
        }
      }
    } catch (_) {
      // Ignored if manifest doesn't exist
    }
  }

  Future<void> _saveManifest() async {
    try {
      final otherContent = {
        'version': 2,
        'description': 'Vault manifest',
      };
      
      final sortedDirectory = DfsFormatUtils.sortAndFillDFS(_manifestEntries);
      final jsonString = DfsFormatUtils.customJsonEncode(otherContent, sortedDirectory);
      final bytes = utf8.encode(jsonString);
      
      final realManifestPath = getRealPath(_manifestPath);
      
      bool isEncrypted = _isEncryptedDomain('/');
      if (isEncrypted) {
        final chunkSize = _determineChunkSize(bytes.length);
        final cipherSize = _getCiphertextSize(bytes.length, chunkSize);
        final fileId = _generateRandomBytes(_fileIdLength);
        
        final plainStream = Stream.value(bytes);
        final encStream = _encryptStream(plainStream, fileId, chunkSize);
        
        await baseVfs.uploadStream(encStream, cipherSize, realManifestPath);
      } else {
        await baseVfs.uploadStream(Stream.value(bytes), bytes.length, realManifestPath);
      }
    } catch (e) {
      print('Failed to save manifest: $e');
    }
  }

  /// 将虚拟（解密后）的路径转换为真实（加密的）路径
  String getRealPath(String virtualPath) {
    virtualPath = _normalizePath(virtualPath);
    
    // 如果已经缓存，直接返回
    if (_virtualToReal.containsKey(virtualPath)) {
      return _virtualToReal[virtualPath]!;
    }

    // 逐级解析路径，查找最长已知的父路径
    List<String> segments = virtualPath == '/' ? [] : virtualPath.split('/').skip(1).toList();
    String currentVirtual = '/';
    String currentReal = '/';

    for (int i = 0; i < segments.length; i++) {
      String segment = segments[i];
      String nextVirtual = currentVirtual == '/' ? '/$segment' : '$currentVirtual/$segment';

      if (_virtualToReal.containsKey(nextVirtual)) {
        currentReal = _virtualToReal[nextVirtual]!;
      } else {
        // 如果是未知路径段，说明是新建文件/目录或未缓存的路径
        // 我们需要判断当前层级是否在加密域，以决定是否加密新名称
        bool isEncrypted = _isEncryptedDomain(currentVirtual);
        String realSegment = (isEncrypted && encryptFilename) ? _encryptName(segment) : segment;
        
        currentReal = currentReal == '/' ? '/$realSegment' : '$currentReal/$realSegment';

        // 缓存这个新映射
        _virtualToReal[nextVirtual] = currentReal;
        _realToVirtual[currentReal] = nextVirtual;
      }
      currentVirtual = nextVirtual;
    }

    return currentReal;
  }

  /// 生成随机字节
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  String _hexEncode(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  List<int> _hexDecode(String hex) {
    if (hex.length % 2 != 0) {
      throw FormatException('Invalid hex string');
    }
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// 确定性加密文件名：Fixed IV (12 bytes) + AES-GCM Ciphertext -> Base64Url
  String _encryptName(String plainName) {
    final fixedNonce = Uint8List(12); // Deterministic encryption
    final plaintext = utf8.encode(plainName);

    final ciphertext = CryptoUtils.encrypt(
      key: masterKey,
      nonce: fixedNonce,
      plaintext: Uint8List.fromList(plaintext),
      algorithm: _algorithm,
    );

    final b64 = _hexEncode(ciphertext);
    if (b64.length > 200) {
      final digest = sha256.convert(utf8.encode(b64)).bytes;
      return 'LFN_' + _hexEncode(digest).substring(0, 32);
    }
    return b64;
  }

  /// 确定性解密文件名：Base64Url -> AES-GCM Ciphertext -> Plaintext
  String _decryptName(String cipherName) {
    try {
      Uint8List ciphertext;
      try {
        ciphertext = Uint8List.fromList(_hexDecode(cipherName));
      } catch (_) {
        ciphertext = Base64UrlUtils.decode(cipherName);
      }
      final fixedNonce = Uint8List(12);

      final plaintext = CryptoUtils.decrypt(
        key: masterKey,
        nonce: fixedNonce,
        ciphertext: ciphertext,
        algorithm: _algorithm,
      );

      return utf8.decode(plaintext);
    } catch (e) {
      // 解密失败时返回原名
      return cipherName;
    }
  }

  int _getPlaintextSize(int ciphertextSize, String virtualPath) {
    if (_manifestEntries.containsKey(virtualPath)) {
      return _manifestEntries[virtualPath]['plaintextSize'] ?? 0;
    }
    // Fallback for old files
    if (ciphertextSize <= _fileIdLength) return 0;
    int dataSize = ciphertextSize - _fileIdLength;
    int chunkCipherSize = _defaultChunkSize + _chunkMacLength;
    int fullChunks = dataSize ~/ chunkCipherSize;
    int remainder = dataSize % chunkCipherSize;
    int size = fullChunks * _defaultChunkSize;
    if (remainder > 0) {
      if (remainder <= _chunkMacLength) {
        return size;
      }
      size += remainder - _chunkMacLength;
    }
    return size;
  }

  int _getCiphertextSize(int plaintextSize, int chunkSize) {
    if (plaintextSize == 0) return _v2HeaderLength;
    int fullChunks = plaintextSize ~/ chunkSize;
    int remainder = plaintextSize % chunkSize;
    int chunkCipherSize = chunkSize + _chunkMacLength;
    int size = _v2HeaderLength + fullChunks * chunkCipherSize;
    if (remainder > 0) {
      size += remainder + _chunkMacLength;
    }
    return size;
  }

  int _determineChunkSize(int fileSize) {
    if (fileSize < 1024 * 1024) {
      return 262144; // 256KB for small files
    } else if (fileSize <= 10 * 1024 * 1024) {
      return 1048576; // 1MB for medium files
    } else {
      return 4194304; // 4MB for large files
    }
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    await _loadManifest();
    String virtualPath = _normalizePath(path);
    String realPath = getRealPath(virtualPath);
    
    if (path.endsWith('/') && realPath != '/') {
      realPath += '/';
    }

    List<VfsNode> realNodes = await baseVfs.list(realPath);

    // 探测当前目录是否包含加密标记文件
    bool hasMarker = realNodes.any((n) => n.name == _markerFileName);
    if (hasMarker) {
      _encryptedDomains.add(virtualPath);
    }

    bool isEncrypted = _isEncryptedDomain(virtualPath);

    List<VfsNode> virtualNodes = [];

    for (var realNode in realNodes) {
      if (realNode.name == _markerFileName ||
          realNode.name == 'local_index.json' ||
          realNode.name == 'vault_config.json') {
        continue; // 过滤并隐藏标记文件和配置文件（取消对 .vault_manifest 的隐藏）
      }

      String decryptedName = realNode.name;
      if (isEncrypted && encryptFilename) {
        if (realNode.name.startsWith('LFN_')) {
          bool found = false;
          for (String entryPath in _manifestEntries.keys) {
            String entryParent = _getParentPath(entryPath);
            if (entryParent == virtualPath) {
              String possibleName = entryPath.substring(entryParent == '/' ? 1 : entryParent.length + 1);
              if (_encryptName(possibleName) == realNode.name) {
                decryptedName = possibleName;
                found = true;
                break;
              }
            }
          }
          if (!found) {
            decryptedName = _decryptName(realNode.name);
          }
        } else {
          decryptedName = _decryptName(realNode.name);
        }
      }

      // 处理明文根目录下的 .vault_manifest（如果它存在，且未加密，直接用原名）
      // 如果已加密，它本身也是以加密后的名字存在？
      // 不，根据代码，.vault_manifest 不会被加密名字！
      // Wait, getRealPath 会对新文件加密名字。
      // _saveManifest 中，上传的路径是 getRealPath(_manifestPath)
      // 如果它是加密域，getRealPath(_manifestPath) 会把 '.vault_manifest' 这个名字加密！
      // 那么我们在 list 的时候，解密出来会是 '.vault_manifest'。
      // 所以对于 list，如果它是 '.vault_manifest'，就不隐藏了，这已经解决了。
      
      String childVirtualPath = virtualPath == '/'
          ? '/$decryptedName'
          : '$virtualPath/$decryptedName';

      String childRealPath = _normalizePath(realNode.path);

      // 更新映射缓存
      _virtualToReal[childVirtualPath] = childRealPath;
      _realToVirtual[childRealPath] = childVirtualPath;

      int finalSize = realNode.size;
      if (isEncrypted && !realNode.isDirectory) {
        finalSize = _getPlaintextSize(realNode.size, childVirtualPath);
      }

      virtualNodes.add(VfsNode(
        name: decryptedName,
        path: childVirtualPath,
        isDirectory: realNode.isDirectory,
        size: finalSize,
        lastModified: realNode.lastModified,
      ));
    }

    return virtualNodes;
  }

  @override
  Future<Stream<List<int>>> open(String path, {int? start, int? end}) async {
    if (path != _manifestPath) {
      await _loadManifest();
    }
    String virtualPath = _normalizePath(path);
    String realPath = getRealPath(virtualPath);

    bool isEncrypted = _isEncryptedDomain(_getParentPath(virtualPath));
    if (!isEncrypted) {
      return baseVfs.open(realPath, start: start, end: end);
    }

    final headerStream = await baseVfs.open(realPath, start: 0, end: 25);
    final headerBytes = <int>[];
    await for (final chunk in headerStream) {
      headerBytes.addAll(chunk);
    }
    final headerData = Uint8List.fromList(headerBytes);

    int chunkSize = _defaultChunkSize;
    Uint8List fileId;
    bool isNewFormat = false;

    if (headerData.length >= 6) {
      final magic = headerData.sublist(0, 6);
      bool magicMatch = true;
      for (int i = 0; i < 6; i++) {
        if (magic[i] != _magicHeader[i]) magicMatch = false;
      }
      if (magicMatch && headerData.length >= _v2HeaderLength) {
        isNewFormat = true;
        final bd = ByteData.sublistView(headerData, 6, 10);
        chunkSize = bd.getUint32(0, Endian.big);
        fileId = headerData.sublist(10, 26);
      } else {
        fileId = headerData.sublist(0, min(16, headerData.length));
      }
    } else {
      fileId = headerData.sublist(0, min(16, headerData.length));
    }

    int headerLength = isNewFormat ? _v2HeaderLength : _fileIdLength;
    int chunkCipherSize = chunkSize + _chunkMacLength;

    int cipherStart = headerLength;
    int? cipherEnd;
    int startChunkIndex = 0;

    if (start != null) {
      startChunkIndex = start ~/ chunkSize;
      cipherStart = headerLength + startChunkIndex * chunkCipherSize;
    }
    if (end != null) {
      int endChunkIndex = end ~/ chunkSize;
      cipherEnd = headerLength + (endChunkIndex + 1) * chunkCipherSize - 1;
    }

    final cipherStream = await baseVfs.open(realPath, start: cipherStart, end: cipherEnd);

    return _decryptStream(cipherStream, fileId, startChunkIndex, start ?? 0, end, chunkSize);
  }

  Stream<List<int>> _decryptStream(Stream<List<int>> cipherStream, Uint8List fileId, int startChunkIndex, int plainStart, int? plainEnd, int chunkSize) async* {
    int chunkIndex = startChunkIndex;
    int currentOffset = startChunkIndex * chunkSize;
    int bufferOffset = 0;
    int chunkCipherSize = chunkSize + _chunkMacLength;
    Uint8List buffer = Uint8List(chunkCipherSize);

    final List<Future<Uint8List>> pendingTasks = [];
    const int maxConcurrency = 4;

    await for (final chunk in cipherStream) {
      int chunkOffset = 0;
      while (chunkOffset < chunk.length) {
        int remainingSpace = chunkCipherSize - bufferOffset;
        int bytesToCopy = min(remainingSpace, chunk.length - chunkOffset);
        buffer.setRange(bufferOffset, bufferOffset + bytesToCopy, chunk, chunkOffset);
        bufferOffset += bytesToCopy;
        chunkOffset += bytesToCopy;

        if (bufferOffset == chunkCipherSize) {
          final dataToDecrypt = buffer;
          buffer = Uint8List(chunkCipherSize);

          pendingTasks.add(_chunkCrypto.decryptChunk(
            chunkData: dataToDecrypt,
            fileId: fileId,
            chunkIndex: chunkIndex++,
          ));

          if (pendingTasks.length >= maxConcurrency) {
            final plainChunk = await pendingTasks.removeAt(0);
            yield* _sliceAndYield(plainChunk, currentOffset, plainStart, plainEnd);
            currentOffset += plainChunk.length;
          }
          bufferOffset = 0;
        }
      }
    }

    if (bufferOffset > 0) {
      pendingTasks.add(_chunkCrypto.decryptChunk(
        chunkData: Uint8List.sublistView(buffer, 0, bufferOffset),
        fileId: fileId,
        chunkIndex: chunkIndex++,
      ));
    }
    
    for (final task in pendingTasks) {
      final plainChunk = await task;
      yield* _sliceAndYield(plainChunk, currentOffset, plainStart, plainEnd);
      currentOffset += plainChunk.length;
    }
  }

  Stream<List<int>> _sliceAndYield(Uint8List plainChunk, int currentOffset, int plainStart, int? plainEnd) async* {
    int chunkStart = currentOffset;
    int chunkEnd = currentOffset + plainChunk.length - 1;

    if (chunkEnd < plainStart) return;
    if (plainEnd != null && chunkStart > plainEnd) return;

    int sliceStart = 0;
    if (plainStart > chunkStart) {
      sliceStart = plainStart - chunkStart;
    }

    int sliceEnd = plainChunk.length;
    if (plainEnd != null && plainEnd < chunkEnd) {
      sliceEnd = plainEnd - chunkStart + 1;
    }

    yield plainChunk.sublist(sliceStart, sliceEnd);
  }

  @override
  Future<VfsNode> stat(String path) async {
    await _loadManifest();
    String virtualPath = _normalizePath(path);
    String realPath = getRealPath(virtualPath);
    if (path.endsWith('/') && realPath != '/') {
      realPath += '/';
    }

    VfsNode realNode = await baseVfs.stat(realPath);

    bool isEncrypted = _isEncryptedDomain(_getParentPath(virtualPath));
    String decryptedName = realNode.name;
    int finalSize = realNode.size;

    if (isEncrypted && realNode.name != _markerFileName) {
      if (encryptFilename) {
        decryptedName = virtualPath == '/' ? '/' : virtualPath.substring(virtualPath.lastIndexOf('/') + 1);
      }
      if (!realNode.isDirectory) {
        finalSize = _getPlaintextSize(realNode.size, virtualPath);
      }
    }

    return VfsNode(
      name: decryptedName,
      path: virtualPath,
      isDirectory: realNode.isDirectory,
      size: finalSize,
      lastModified: realNode.lastModified,
    );
  }

  @override
  Future<void> upload(String localFilePath, String remotePath) async {
    await _loadManifest();
    String virtualPath = _normalizePath(remotePath);
    String realPath = getRealPath(virtualPath);
    if (remotePath.endsWith('/') && realPath != '/') {
      realPath += '/';
    }

    bool isEncrypted = _isEncryptedDomain(_getParentPath(virtualPath));
    if (!isEncrypted) {
      return baseVfs.upload(localFilePath, realPath);
    }

    final file = File(localFilePath);
    final fileSize = await file.length();
    
    final chunkSize = _determineChunkSize(fileSize);
    final cipherSize = _getCiphertextSize(fileSize, chunkSize);

    final fileId = _generateRandomBytes(_fileIdLength);
    final stream = _encryptStream(file.openRead(), fileId, chunkSize);
    
    await baseVfs.uploadStream(stream, cipherSize, realPath);
    
    _manifestEntries[virtualPath] = {
      'chunkSize': chunkSize,
      'plaintextSize': fileSize,
    };
    await _saveManifest();
  }

  @override
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    await _loadManifest();
    String virtualPath = _normalizePath(remotePath);
    String realPath = getRealPath(virtualPath);
    if (remotePath.endsWith('/') && realPath != '/') {
      realPath += '/';
    }

    bool isEncrypted = _isEncryptedDomain(_getParentPath(virtualPath));
    if (!isEncrypted) {
      return baseVfs.uploadStream(stream, length, realPath);
    }

    final chunkSize = _determineChunkSize(length);
    final cipherSize = _getCiphertextSize(length, chunkSize);
    final fileId = _generateRandomBytes(_fileIdLength);
    final encStream = _encryptStream(stream, fileId, chunkSize);

    await baseVfs.uploadStream(encStream, cipherSize, realPath);
    
    _manifestEntries[virtualPath] = {
      'chunkSize': chunkSize,
      'plaintextSize': length,
    };
    await _saveManifest();
  }

  Stream<List<int>> _encryptStream(Stream<List<int>> plainStream, Uint8List fileId, int chunkSize) async* {
    final headerBuilder = BytesBuilder(copy: false);
    headerBuilder.add(_magicHeader);
    
    final chunkSizeBytes = ByteData(4);
    chunkSizeBytes.setUint32(0, chunkSize, Endian.big);
    headerBuilder.add(chunkSizeBytes.buffer.asUint8List());
    
    headerBuilder.add(fileId);
    yield headerBuilder.takeBytes();

    int chunkIndex = 0;
    int bufferOffset = 0;
    Uint8List buffer = Uint8List(chunkSize);
    
    final List<Future<Uint8List>> pendingTasks = [];
    const int maxConcurrency = 4;

    await for (final chunk in plainStream) {
      int chunkOffset = 0;
      while (chunkOffset < chunk.length) {
        int remainingSpace = chunkSize - bufferOffset;
        int bytesToCopy = min(remainingSpace, chunk.length - chunkOffset);
        buffer.setRange(bufferOffset, bufferOffset + bytesToCopy, chunk, chunkOffset);
        bufferOffset += bytesToCopy;
        chunkOffset += bytesToCopy;

        if (bufferOffset == chunkSize) {
          final dataToEncrypt = buffer;
          buffer = Uint8List(chunkSize);

          pendingTasks.add(_chunkCrypto.encryptChunk(
            chunkData: dataToEncrypt,
            fileId: fileId,
            chunkIndex: chunkIndex++,
          ));

          if (pendingTasks.length >= maxConcurrency) {
            yield await pendingTasks.removeAt(0);
          }
          bufferOffset = 0;
        }
      }
    }

    if (bufferOffset > 0) {
      pendingTasks.add(_chunkCrypto.encryptChunk(
        chunkData: Uint8List.sublistView(buffer, 0, bufferOffset),
        fileId: fileId,
        chunkIndex: chunkIndex++,
      ));
    }
    
    for (final task in pendingTasks) {
      yield await task;
    }
  }

  @override
  Future<void> delete(String path) async {
    await _loadManifest();
    String virtualPath = _normalizePath(path);
    String realPath = getRealPath(virtualPath);
    if (path.endsWith('/') && realPath != '/') {
      realPath += '/';
    }
    await baseVfs.delete(realPath);
    
    // 从缓存中移除 (包括所有子路径)
    String vPrefix = virtualPath == '/' ? '/' : '$virtualPath/';
    String normRealPath = _normalizePath(realPath);
    String rPrefix = normRealPath == '/' ? '/' : '$normRealPath/';

    _virtualToReal.removeWhere((k, v) => k == virtualPath || k.startsWith(vPrefix));
    _realToVirtual.removeWhere((k, v) => k == normRealPath || k.startsWith(rPrefix));
    _encryptedDomains.removeWhere((k) => k == virtualPath || k.startsWith(vPrefix));
    
    bool manifestChanged = false;
    _manifestEntries.removeWhere((k, v) {
      if (k == virtualPath || k.startsWith(vPrefix)) {
        manifestChanged = true;
        return true;
      }
      return false;
    });

    if (manifestChanged) {
      await _saveManifest();
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await _loadManifest();
    String virtualOldPath = _normalizePath(oldPath);
    String realOldPath = getRealPath(virtualOldPath);
    if (oldPath.endsWith('/') && realOldPath != '/') {
      realOldPath += '/';
    }
    
    // 生成新的真实路径（可能会触发名字的加密并缓存）
    String virtualNewPath = _normalizePath(newPath);
    String realNewPath = getRealPath(virtualNewPath);
    if (newPath.endsWith('/') && realNewPath != '/') {
      realNewPath += '/';
    }

    await baseVfs.rename(realOldPath, realNewPath);

    String normRealOldPath = _normalizePath(realOldPath);
    String normRealNewPath = _normalizePath(realNewPath);

    String vOldPrefix = virtualOldPath == '/' ? '/' : '$virtualOldPath/';
    String vNewPrefix = virtualNewPath == '/' ? '/' : '$virtualNewPath/';
    String rOldPrefix = normRealOldPath == '/' ? '/' : '$normRealOldPath/';
    String rNewPrefix = normRealNewPath == '/' ? '/' : '$normRealNewPath/';

    // Update _virtualToReal
    final Map<String, String> newV2R = {};
    _virtualToReal.removeWhere((k, v) {
      if (k == virtualOldPath) {
        newV2R[virtualNewPath] = normRealNewPath;
        return true;
      }
      if (k.startsWith(vOldPrefix)) {
        String suffix = k.substring(vOldPrefix.length);
        String rSuffix = v.substring(rOldPrefix.length);
        newV2R['$vNewPrefix$suffix'] = '$rNewPrefix$rSuffix';
        return true;
      }
      return false;
    });
    _virtualToReal.addAll(newV2R);

    // Update _realToVirtual
    final Map<String, String> newR2V = {};
    _realToVirtual.removeWhere((k, v) {
      if (k == normRealOldPath) {
        newR2V[normRealNewPath] = virtualNewPath;
        return true;
      }
      if (k.startsWith(rOldPrefix)) {
        String suffix = k.substring(rOldPrefix.length);
        String vSuffix = v.substring(vOldPrefix.length);
        newR2V['$rNewPrefix$suffix'] = '$vNewPrefix$vSuffix';
        return true;
      }
      return false;
    });
    _realToVirtual.addAll(newR2V);

    // Update _encryptedDomains
    final Set<String> newDomains = {};
    _encryptedDomains.removeWhere((k) {
      if (k == virtualOldPath) {
        newDomains.add(virtualNewPath);
        return true;
      }
      if (k.startsWith(vOldPrefix)) {
        String suffix = k.substring(vOldPrefix.length);
        newDomains.add('$vNewPrefix$suffix');
        return true;
      }
      return false;
    });
    _encryptedDomains.addAll(newDomains);

    // Update manifest
    bool manifestChanged = false;
    final Map<String, dynamic> newManifest = {};
    _manifestEntries.removeWhere((k, v) {
      if (k == virtualOldPath) {
        newManifest[virtualNewPath] = v;
        manifestChanged = true;
        return true;
      }
      if (k.startsWith(vOldPrefix)) {
        String suffix = k.substring(vOldPrefix.length);
        newManifest['$vNewPrefix$suffix'] = v;
        manifestChanged = true;
        return true;
      }
      return false;
    });
    _manifestEntries.addAll(newManifest);

    if (manifestChanged) {
      await _saveManifest();
    }
  }

  @override
  Future<void> mkdir(String path) async {
    await _loadManifest();
    String virtualPath = _normalizePath(path);
    String realPath = getRealPath(virtualPath);
    if (path.endsWith('/') && realPath != '/') {
      realPath += '/';
    }
    await baseVfs.mkdir(realPath);
    if (encryptFilename) {
      _manifestEntries[virtualPath] = {'isDirectory': true};
      await _saveManifest();
    }
  }

  /// 初始化一个加密目录：即在目录下创建一个空标记文件
  Future<void> initEncryptedDomain(String path) async {
    String virtualPath = _normalizePath(path);
    String realPath = getRealPath(virtualPath);
    String markerPath = realPath == '/' ? '/$_markerFileName' : '$realPath/$_markerFileName';
    
    // Create an empty temporary file and upload it
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/$_markerFileName');
    if (!await tempFile.exists()) {
      await tempFile.create();
    }
    
    await baseVfs.upload(tempFile.path, markerPath);
    
    // Mark this domain as encrypted
    _encryptedDomains.add(virtualPath);
  }
}
