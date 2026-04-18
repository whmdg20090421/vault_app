import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'virtual_file_system.dart';

/// 加密版 VFS 实现 (Gutted to remove logic)
class EncryptedVfs implements VirtualFileSystem {
  final VirtualFileSystem baseVfs;
  final Uint8List masterKey;
  final bool encryptFilename;

  EncryptedVfs({
    required this.baseVfs,
    required this.masterKey,
    this.encryptFilename = true,
  });

  Future<void> initEncryptedDomain(String path) async {
    // No-op
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    return baseVfs.list(path);
  }

  @override
  Future<Stream<List<int>>> open(String path, {int? start, int? end}) async {
    return baseVfs.open(path, start: start, end: end);
  }

  @override
  Future<VfsNode> stat(String path) async {
    return baseVfs.stat(path);
  }

  @override
  Future<void> upload(String localFilePath, String remotePath) async {
    return baseVfs.upload(localFilePath, remotePath);
  }

  @override
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    return baseVfs.uploadStream(stream, length, remotePath);
  }

  @override
  Future<void> delete(String path) async {
    return baseVfs.delete(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    return baseVfs.rename(oldPath, newPath);
  }

  @override
  Future<void> mkdir(String path) async {
    return baseVfs.mkdir(path);
  }
}
