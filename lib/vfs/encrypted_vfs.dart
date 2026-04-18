import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../encryption/utils/base64url_utils.dart';
import '../encryption/utils/crypto_utils.dart';
import '../encryption/utils/chunk_crypto.dart';
import 'virtual_file_system.dart';

/// 加密版 VFS 实现
/// 包装基础的 VFS，实现文件/目录名透明加解密与加密状态的拦截
class EncryptedVfs implements VirtualFileSystem {
  static const String _markerFileName = '.vault_marker';
  static const String _algorithm = 'AES-256-GCM';

  // Chunking constants for file content encryption
  static const int _chunkSize = 65536; // 64KB plaintext chunk
  static const int _chunkMacLength = 16;
  static const int _chunkCipherSize = _chunkSize + _chunkMacLength; // 65552
  static const int _fileIdLength = 16;

  final VirtualFileSystem baseVfs;
  final Uint8List masterKey;
  final bool encryptFilename;
  late final ChunkCrypto _chunkCrypto;

  // 缓存虚拟（解密）路径到真实（加密）路径的映射
  final Map<String, String> _virtualToReal = {'/': '/'};
  final Map<String, String> _realToVirtual = {'/': '/'};

  // 缓存处于加密域中的虚拟路径
  final Set<String> _encryptedDomains = {};

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

    return Base64UrlUtils.encode(ciphertext);
  }

  /// 确定性解密文件名：Base64Url -> AES-GCM Ciphertext -> Plaintext
  String _decryptName(String cipherName) {
    try {
      final ciphertext = Base64UrlUtils.decode(cipherName);
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

  int _getPlaintextSize(int ciphertextSize) {
    if (ciphertextSize <= _fileIdLength) return 0;
    int dataSize = ciphertextSize - _fileIdLength;
    int fullChunks = dataSize ~/ _chunkCipherSize;
    int remainder = dataSize % _chunkCipherSize;
    int size = fullChunks * _chunkSize;
    if (remainder > 0) {
      if (remainder <= _chunkMacLength) {
        return size;
      }
      size += remainder - _chunkMacLength;
    }
    return size;
  }

  int _getCiphertextSize(int plaintextSize) {
    if (plaintextSize == 0) return _fileIdLength;
    int fullChunks = plaintextSize ~/ _chunkSize;
    int remainder = plaintextSize % _chunkSize;
    int size = _fileIdLength + fullChunks * _chunkCipherSize;
    if (remainder > 0) {
      size += remainder + _chunkMacLength;
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
      if (isEncrypted && encryptFilename) {
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
    throw UnimplementedError('TODO: Refactor encryption flow');
  }

  Future<Uint8List> _readHeader(Stream<List<int>> stream) async {
    final buffer = <int>[];
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      if (buffer.length >= _fileIdLength) break;
    }
    if (buffer.length < _fileIdLength) {
      throw Exception('Encrypted file is too short to contain a File ID');
    }
    return Uint8List.fromList(buffer.sublist(0, _fileIdLength));
  }

  Stream<List<int>> _decryptStream(Stream<List<int>> cipherStream, Uint8List fileId, int startChunkIndex, int plainStart, int? plainEnd) async* {
    throw UnimplementedError('TODO: Refactor encryption flow');
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
      if (encryptFilename) {
        decryptedName = _decryptName(realNode.name);
      }
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

    final fileId = _generateRandomBytes(_fileIdLength);
    final stream = _encryptStream(file.openRead(), fileId);
    return baseVfs.uploadStream(stream, cipherSize, realPath);
  }

  @override
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    throw UnimplementedError('TODO: Refactor encryption flow');
  }

  Stream<List<int>> _encryptStream(Stream<List<int>> plainStream, Uint8List fileId) async* {
    throw UnimplementedError('TODO: Refactor encryption flow');
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
