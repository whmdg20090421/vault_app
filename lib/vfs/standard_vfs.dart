import 'dart:async';

import 'virtual_file_system.dart';

class StandardVfs implements VirtualFileSystem {
  StandardVfs();

  @override
  Future<List<VfsNode>> list(String path) async {
    throw UnimplementedError('Refactoring WebDAV service');
  }

  @override
  Future<Stream<List<int>>> open(String path, {int? start, int? end}) async {
    throw UnimplementedError('Refactoring WebDAV service');
  }

  @override
  Future<VfsNode> stat(String path) async {
    throw UnimplementedError('Refactoring WebDAV service');
  }

  @override
  Future<void> upload(String localFilePath, String remotePath) async {
    throw UnimplementedError('Refactoring WebDAV service');
  }

  @override
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    throw UnimplementedError('Refactoring WebDAV service');
  }

  @override
  Future<void> delete(String path) async {
    throw UnimplementedError('Refactoring WebDAV service');
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnimplementedError('Refactoring WebDAV service');
  }

  @override
  Future<void> mkdir(String path) async {
    throw UnimplementedError('Refactoring WebDAV service');
  }
}
