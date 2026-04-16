import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../encryption/utils/base64url_utils.dart';
import '../encryption/utils/crypto_utils.dart';
import 'virtual_file_system.dart';

/// 加密版 VFS 实现
/// 包装基础的 VFS，实现文件/目录名透明加解密与加密状态的拦截
class EncryptedVfs implements VirtualFileSystem {
  static const String _markerFileName = '.vault_marker';
  static const int _nonceLength = 12; // AES-GCM nonce length
  static const String _algorithm = 'AES-256-GCM';

  // Chunking constants for file content encryption
  static const int _chunkSize = 65536; // 64KB plaintext chunk
  static const int _chunkNonceLength = 12;
  static const int _chunkMacLength = 16;
  static const int _chunkCipherSize = _chunkSize + _chunkNonceLength + _chunkMacLength; // 65564

  final VirtualFileSystem baseVfs;
  final Uint8List masterKey;

  // 缓存虚拟（解密）路径到真实（加密）路径的映射
  final Map<String, String> _virtualToReal = {'/': '/'};
  final Map<String, String> _realToVirtual = {'/': '/'};

  // 缓存处于加密域中的虚拟路径
  final Set<String> _encryptedDomains = {};

  EncryptedVfs({
    required this.baseVfs,
    required this.masterKey,
  }) {
    if (masterKey.length != 32) {
      throw ArgumentError('MasterKey must be 32 bytes for AES-256-GCM');
    }
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

  /// 获取路径最后一段的名称
  String _getBaseName(String normalizedPath) {
    if (normalizedPath == '/') return '/';
    int lastSlash = normalizedPath.lastIndexOf('/');
    return normalizedPath.substring(lastSlash + 1);
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

  /// 将虚拟（解密后）的路径转换为真实（加密的）路径
  String _getRealPath(String virtualPath) {
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
        String realSegment = isEncrypted ? _encryptName(segment) : segment;
        
        currentReal = currentReal == '/' ? '/$realSegment' : '$currentReal/$realSegment';

        // 缓存这个新映射
        _virtualToReal[nextVirtual] = currentReal;
        _realToVirtual[currentReal] = nextVirtual;
      }
      currentVirtual = nextVirtual;
    }

    return currentReal;
  }

  /// 生成随机 Nonce
  Uint8List _generateNonce(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// 加密文件名：Nonce + AES-GCM Ciphertext -> Base64Url
  String _encryptName(String plainName) {
    final nonce = _generateNonce(_nonceLength);
    final plaintext = utf8.encode(plainName);

    final ciphertext = CryptoUtils.encrypt(
      key: masterKey,
      nonce: nonce,
      plaintext: Uint8List.fromList(plaintext),
      algorithm: _algorithm,
    );

    final combined = Uint8List(_nonceLength + ciphertext.length);
    combined.setRange(0, _nonceLength, nonce);
    combined.setRange(_nonceLength, combined.length, ciphertext);

    return Base64UrlUtils.encode(combined);
  }

  /// 解密文件名：Base64Url -> Nonce + AES-GCM Ciphertext -> Plaintext
  String _decryptName(String cipherName) {
    try {
      final bytes = Base64UrlUtils.decode(cipherName);
      if (bytes.length <= _nonceLength) {
        throw Exception('Invalid ciphertext length');
      }
      final nonce = bytes.sublist(0, _nonceLength);
      final ciphertext = bytes.sublist(_nonceLength);

      final plaintext = CryptoUtils.decrypt(
        key: masterKey,
        nonce: nonce,
        ciphertext: ciphertext,
        algorithm: _algorithm,
      );

      return utf8.decode(plaintext);
    } catch (e) {
      // 解密失败时返回原名，可能是遗留明文文件或是其他不符合规则的文件名
      return cipherName;
    }
  }

  int _getPlaintextSize(int ciphertextSize) {
    if (ciphertextSize == 0) return 0;
    int fullChunks = ciphertextSize ~/ _chunkCipherSize;
    int remainder = ciphertextSize % _chunkCipherSize;
    int size = fullChunks * _chunkSize;
    if (remainder > 0) {
      if (remainder <= _chunkNonceLength + _chunkMacLength) {
        return size;
      }
      size += remainder - _chunkNonceLength - _chunkMacLength;
    }
    return size;
  }

  int _getCiphertextSize(int plaintextSize) {
    if (plaintextSize == 0) return 0;
    int fullChunks = plaintextSize ~/ _chunkSize;
    int remainder = plaintextSize % _chunkSize;
    int size = fullChunks * _chunkCipherSize;
    if (remainder > 0) {
      size += remainder + _chunkNonceLength + _chunkMacLength;
    }
    return size;
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    String virtualPath = _normalizePath(path);
    String realPath = _getRealPath(virtualPath);
    
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
      if (realNode.name == _markerFileName) {
        continue; // 过滤并隐藏标记文件
      }

      String decryptedName = realNode.name;
      if (isEncrypted) {
        decryptedName = _decryptName(realNode.name);
      }

      String childVirtualPath = virtualPath == '/'
          ? '/$decryptedName'
          : '$virtualPath/$decryptedName';

      String childRealPath = _normalizePath(realNode.path);

      // 更新映射缓存
      _virtualToReal[childVirtualPath] = childRealPath;
      _realToVirtual[childRealPath] = childVirtualPath;

      int finalSize = realNode.size;
      if (isEncrypted && !realNode.isDirectory) {
        finalSize = _getPlaintextSize(realNode.size);
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
    String virtualPath = _normalizePath(path);
    String realPath = _getRealPath(virtualPath);
    if (path.endsWith('/') && realPath != '/') {
      realPath += '/';
    }
    
    bool isEncrypted = _isEncryptedDomain(_getParentPath(virtualPath));
    if (!isEncrypted) {
      return baseVfs.open(realPath, start: start, end: end);
    }

    int? cipherStart;
    int? cipherEnd;

    if (start != null || end != null) {
      int safeStart = start ?? 0;
      int startChunk = safeStart ~/ _chunkSize;
      cipherStart = startChunk * _chunkCipherSize;

      if (end != null) {
        int endChunk = end ~/ _chunkSize;
        cipherEnd = (endChunk + 1) * _chunkCipherSize - 1;
      }
    }

    final cipherStream = await baseVfs.open(realPath, start: cipherStart, end: cipherEnd);
    return _decryptStream(cipherStream, start ?? 0, end);
  }

  Stream<List<int>> _decryptStream(Stream<List<int>> cipherStream, int plainStart, int? plainEnd) async* {
    int currentPlainOffset = (plainStart ~/ _chunkSize) * _chunkSize;
    final buffer = <int>[];

    await for (final chunk in cipherStream) {
      buffer.addAll(chunk);

      while (buffer.length >= _chunkCipherSize) {
        final cipherChunk = Uint8List.fromList(buffer.sublist(0, _chunkCipherSize));
        buffer.removeRange(0, _chunkCipherSize);

        final plainChunk = _decryptContentChunk(cipherChunk);
        yield* _sliceAndYield(plainChunk, currentPlainOffset, plainStart, plainEnd);
        currentPlainOffset += plainChunk.length;
        
        if (plainEnd != null && currentPlainOffset > plainEnd) {
          return;
        }
      }
    }

    if (buffer.isNotEmpty) {
      final plainChunk = _decryptContentChunk(Uint8List.fromList(buffer));
      yield* _sliceAndYield(plainChunk, currentPlainOffset, plainStart, plainEnd);
    }
  }

  Uint8List _decryptContentChunk(Uint8List cipherChunk) {
    if (cipherChunk.length <= _chunkNonceLength + _chunkMacLength) {
      throw Exception('Invalid content chunk size');
    }
    final nonce = cipherChunk.sublist(0, _chunkNonceLength);
    final ciphertext = cipherChunk.sublist(_chunkNonceLength);
    return CryptoUtils.decrypt(
      key: masterKey,
      nonce: nonce,
      ciphertext: ciphertext,
      algorithm: _algorithm,
    );
  }

  Iterable<List<int>> _sliceAndYield(Uint8List plainChunk, int currentOffset, int plainStart, int? plainEnd) sync* {
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
    String virtualPath = _normalizePath(path);
    String realPath = _getRealPath(virtualPath);
    if (path.endsWith('/') && realPath != '/') {
      realPath += '/';
    }

    VfsNode realNode = await baseVfs.stat(realPath);

    bool isEncrypted = _isEncryptedDomain(_getParentPath(virtualPath));
    String decryptedName = realNode.name;
    int finalSize = realNode.size;

    if (isEncrypted && realNode.name != _markerFileName) {
      decryptedName = _decryptName(realNode.name);
      if (!realNode.isDirectory) {
        finalSize = _getPlaintextSize(realNode.size);
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
    String virtualPath = _normalizePath(remotePath);
    String realPath = _getRealPath(virtualPath);
    if (remotePath.endsWith('/') && realPath != '/') {
      realPath += '/';
    }

    bool isEncrypted = _isEncryptedDomain(_getParentPath(virtualPath));
    if (!isEncrypted) {
      return baseVfs.upload(localFilePath, realPath);
    }

    final file = File(localFilePath);
    final fileSize = await file.length();
    final cipherSize = _getCiphertextSize(fileSize);

    final stream = _encryptStream(file.openRead());
    return baseVfs.uploadStream(stream, cipherSize, realPath);
  }

  @override
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    String virtualPath = _normalizePath(remotePath);
    String realPath = _getRealPath(virtualPath);
    if (remotePath.endsWith('/') && realPath != '/') {
      realPath += '/';
    }

    bool isEncrypted = _isEncryptedDomain(_getParentPath(virtualPath));
    if (!isEncrypted) {
      return baseVfs.uploadStream(stream, length, realPath);
    }

    final cipherSize = _getCiphertextSize(length);
    final cipherStream = _encryptStream(stream);
    return baseVfs.uploadStream(cipherStream, cipherSize, realPath);
  }

  Stream<List<int>> _encryptStream(Stream<List<int>> plainStream) async* {
    final buffer = <int>[];

    await for (final chunk in plainStream) {
      buffer.addAll(chunk);

      while (buffer.length >= _chunkSize) {
        final plainChunk = Uint8List.fromList(buffer.sublist(0, _chunkSize));
        buffer.removeRange(0, _chunkSize);
        yield _encryptContentChunk(plainChunk);
      }
    }

    if (buffer.isNotEmpty) {
      yield _encryptContentChunk(Uint8List.fromList(buffer));
    } else {
      // If the file is exactly 0 bytes, we might need to handle it.
      // But _getCiphertextSize(0) returns 0, and uploadStream with length 0
      // works without yielding any chunks.
    }
  }

  Uint8List _encryptContentChunk(Uint8List plainChunk) {
    final nonce = _generateNonce(_chunkNonceLength);
    final ciphertext = CryptoUtils.encrypt(
      key: masterKey,
      nonce: nonce,
      plaintext: plainChunk,
      algorithm: _algorithm,
    );

    final combined = Uint8List(_chunkNonceLength + ciphertext.length);
    combined.setRange(0, _chunkNonceLength, nonce);
    combined.setRange(_chunkNonceLength, combined.length, ciphertext);
    return combined;
  }

  @override
  Future<void> delete(String path) async {
    String virtualPath = _normalizePath(path);
    String realPath = _getRealPath(virtualPath);
    if (path.endsWith('/') && realPath != '/') {
      realPath += '/';
    }
    await baseVfs.delete(realPath);
    
    // 从缓存中移除
    _virtualToReal.remove(virtualPath);
    _realToVirtual.remove(_normalizePath(realPath));
    _encryptedDomains.remove(virtualPath);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    String virtualOldPath = _normalizePath(oldPath);
    String realOldPath = _getRealPath(virtualOldPath);
    if (oldPath.endsWith('/') && realOldPath != '/') {
      realOldPath += '/';
    }
    
    // 生成新的真实路径（可能会触发名字的加密并缓存）
    String virtualNewPath = _normalizePath(newPath);
    String realNewPath = _getRealPath(virtualNewPath);
    if (newPath.endsWith('/') && realNewPath != '/') {
      realNewPath += '/';
    }

    await baseVfs.rename(realOldPath, realNewPath);

    // 更新缓存
    _virtualToReal.remove(virtualOldPath);
    _realToVirtual.remove(_normalizePath(realOldPath));
    
    // _getRealPath 内部可能已经添加了新映射，但这里再确认一下
    _virtualToReal[virtualNewPath] = _normalizePath(realNewPath);
    _realToVirtual[_normalizePath(realNewPath)] = virtualNewPath;

    if (_encryptedDomains.contains(virtualOldPath)) {
      _encryptedDomains.remove(virtualOldPath);
      _encryptedDomains.add(virtualNewPath);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    String virtualPath = _normalizePath(path);
    String realPath = _getRealPath(virtualPath);
    if (path.endsWith('/') && realPath != '/') {
      realPath += '/';
    }
    await baseVfs.mkdir(realPath);
  }

  /// 初始化一个加密目录：即在目录下创建一个空标记文件
  Future<void> initEncryptedDomain(String path) async {
    String virtualPath = _normalizePath(path);
    String realPath = _getRealPath(virtualPath);
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
