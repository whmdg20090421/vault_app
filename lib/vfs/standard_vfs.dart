import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../cloud_drive/webdav_new/webdav_service.dart';
import '../cloud_drive/webdav_new/webdav_parser.dart';
import 'virtual_file_system.dart';

class StandardVfs implements VirtualFileSystem {
  final WebDavService service;

  StandardVfs(this.service);

  @override
  Future<List<VfsNode>> list(String path) async {
    final files = await service.readDir(path);
    return files.map((f) => VfsNode(
      name: f.name,
      path: f.path,
      isDirectory: f.isDirectory,
      size: f.size,
      lastModified: f.lastModified,
    )).toList();
  }

  @override
  Future<Stream<List<int>>> open(String path, {int? start, int? end}) async {
    final headers = <String, String>{};
    if (start != null || end != null) {
      headers['Range'] = 'bytes=${start ?? 0}-${end ?? ''}';
    }

    final response = await service.client.request<ResponseBody>(
      path,
      method: 'GET',
      headers: headers,
      responseType: ResponseType.stream,
    );

    if (response.statusCode == 200 || response.statusCode == 206) {
      if (response.data != null) {
        return response.data!.stream;
      }
    }
    throw Exception('Failed to open file: ${response.statusCode}');
  }

  @override
  Future<VfsNode> stat(String path) async {
    final response = await service.client.request<String>(
      path,
      method: 'PROPFIND',
      headers: {'Depth': '0'},
    );

    if (response.statusCode == 207 && response.data != null) {
      // Pass empty string for requestedPath to avoid filtering out the root node itself
      final files = WebDavParser.parseMultiStatus(response.data!, '');
      if (files.isNotEmpty) {
        final f = files.first;
        return VfsNode(
          name: f.name,
          path: f.path,
          isDirectory: f.isDirectory,
          size: f.size,
          lastModified: f.lastModified,
        );
      }
    }
    throw Exception('Failed to stat file: $path');
  }

  @override
  Future<void> upload(String localFilePath, String remotePath) async {
    await service.upload(localFilePath, remotePath);
  }

  @override
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    final response = await service.client.request(
      remotePath,
      method: 'PUT',
      data: stream,
      headers: {
        HttpHeaders.contentLengthHeader: length.toString(),
        HttpHeaders.contentTypeHeader: 'application/octet-stream',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to upload stream: ${response.statusCode}');
    }
  }

  @override
  Future<void> delete(String path) async {
    await service.remove(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await service.move(oldPath, newPath);
  }

  @override
  Future<void> mkdir(String path) async {
    await service.mkdir(path);
  }
}
