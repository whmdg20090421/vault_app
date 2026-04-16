import 'dart:async';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../cloud_drive/webdav_client_service.dart';
import 'virtual_file_system.dart';

class StandardVfs implements VirtualFileSystem {
  final WebDavClientService client;

  StandardVfs({required this.client});

  VfsNode _mapWebDavFile(webdav.File file) {
    return VfsNode(
      name: file.name ?? 'unknown',
      path: file.path ?? '/',
      isDirectory: file.isDir ?? false,
      size: file.size ?? 0,
      lastModified: file.mTime,
    );
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    final list = await client.readDir(path);
    // Remove the directory itself from the listing if present
    list.removeWhere((file) => file == null || file.path == path || file.path == '$path/');
    return list.where((f) => f != null).map((f) => _mapWebDavFile(f!)).toList();
  }

  @override
  Future<Stream<List<int>>> open(String path, {int? start, int? end}) async {
    if (start != null || end != null) {
      final req = await client.createRequest('GET', path);
      String rangeHeader = 'bytes=';
      if (start != null) rangeHeader += '$start';
      rangeHeader += '-';
      if (end != null) rangeHeader += '$end';
      req.headers.add('Range', rangeHeader);
      final resp = await req.close();
      if (resp.statusCode >= 400) {
        throw Exception('Failed to fetch range: ${resp.statusCode}');
      }
      return resp;
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
    final req = await client.createRequest('PUT', remotePath);
    req.contentLength = length;
    await req.addStream(stream);
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to upload stream: ${resp.statusCode}');
    }
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
