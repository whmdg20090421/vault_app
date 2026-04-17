import 'dart:async';

import '../cloud_drive/webdav_client_service.dart';
import 'virtual_file_system.dart';

class StandardVfs implements VirtualFileSystem {
  final WebDavClientService client;

  StandardVfs({required this.client});

  VfsNode _mapWebDavFile(WebDavFile file) {
    return VfsNode(
      name: file.name,
      path: file.path,
      isDirectory: file.isDirectory,
      size: file.size,
      lastModified: file.lastModified,
    );
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    final list = await client.readDir(path);
    // Remove the directory itself from the listing if present
    list.removeWhere((file) => file.path == path || file.path == '$path/');
    return list.map((f) => _mapWebDavFile(f)).toList();
  }

  @override
  Future<Stream<List<int>>> open(String path, {int? start, int? end}) async {
    if (start != null || end != null) {
      final data = await client.readDataWithRange(path, start: start, end: end);
      return Stream.value(data);
    }

    final data = await client.readData(path);
    return Stream.value(data);
  }

  @override
  Future<VfsNode> stat(String path) async {
    final file = await client.stat(path);
    return _mapWebDavFile(file);
  }

  @override
  Future<void> upload(String localFilePath, String remotePath) async {
    return client.upload(localFilePath, remotePath);
  }

  @override
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    await client.uploadStream(stream, length, remotePath);
  }

  @override
  Future<void> delete(String path) async {
    return client.remove(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    return client.rename(oldPath, newPath);
  }

  @override
  Future<void> mkdir(String path) async {
    return client.mkdir(path);
  }
}
