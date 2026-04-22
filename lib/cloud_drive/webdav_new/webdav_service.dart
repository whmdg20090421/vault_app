import 'dart:io';
import 'package:dio/dio.dart';
import 'webdav_client.dart';
import 'webdav_parser.dart';
import 'webdav_file.dart';

/// 提供高层 WebDAV 操作的业务服务类
class WebDavService {
  final WebDavClient client;

  WebDavService(this.client);

  /// 读取指定路径下的目录内容
  /// [path] 目标目录路径
  /// [depth] 请求深度，默认为 1，可传 'infinity'
  Future<List<WebDavFile>> readDir(String path, {String depth = '1'}) async {
    final response = await client.request<String>(
      path,
      method: 'PROPFIND',
      headers: {'Depth': depth},
    );

    if (response.statusCode == 207 && response.data != null) {
      final baseUrlPath = Uri.parse(client.dio.options.baseUrl).path;
      return WebDavParser.parseMultiStatus(response.data!, path, baseUrlPath);
    } else {
      throw Exception('Failed to read directory: ${response.statusCode}');
    }
  }

  /// 创建目录 (MKCOL)
  /// [path] 要创建的目录路径
  Future<void> mkdir(String path) async {
    final response = await client.request(
      path,
      method: 'MKCOL',
    );

    // 201 Created 表示成功
    // 405 Method Not Allowed 通常表示该目录已经存在
    if (response.statusCode != 201 && response.statusCode != 405) {
      throw Exception('Failed to create directory: ${response.statusCode}');
    }
  }

  /// 上传本地文件到远端 (PUT)
  /// [localPath] 本地文件路径
  /// [remotePath] 远端目标路径
  Future<void> upload(String localPath, String remotePath) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Local file does not exist: $localPath');
    }

    final length = await file.length();

    final response = await client.request(
      remotePath,
      method: 'PUT',
      data: file.openRead(),
      headers: {
        HttpHeaders.contentLengthHeader: length.toString(),
        HttpHeaders.contentTypeHeader: 'application/octet-stream',
      },
    );

    // 200 OK, 201 Created, 204 No Content 都表示上传成功
    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to upload file: ${response.statusCode}');
    }
  }

  /// 从远端下载文件到本地 (GET)
  /// [remotePath] 远端文件路径
  /// [localPath] 本地目标路径
  Future<void> download(String remotePath, String localPath) async {
    final response = await client.request<ResponseBody>(
      remotePath,
      method: 'GET',
      responseType: ResponseType.stream,
    );

    if (response.statusCode == 200 && response.data != null) {
      final file = File(localPath);
      // 确保父目录存在
      await file.parent.create(recursive: true);

      final sink = file.openWrite();
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } else {
      throw Exception('Failed to download file: ${response.statusCode}');
    }
  }

  /// 删除远端文件或目录 (DELETE)
  /// [path] 要删除的路径
  Future<void> remove(String path) async {
    final response = await client.request(
      path,
      method: 'DELETE',
    );

    // 200 OK, 204 No Content 表示删除成功
    // 404 Not Found 也可视为已删除
    if (response.statusCode != 200 && response.statusCode != 204 && response.statusCode != 404) {
      throw Exception('Failed to delete path: ${response.statusCode}');
    }
  }

  /// 移动或重命名远端文件/目录 (MOVE)
  /// [oldPath] 原路径
  /// [newPath] 新路径
  Future<void> move(String oldPath, String newPath) async {
    String baseUrl = client.dio.options.baseUrl;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    String destPath = newPath.startsWith('/') ? newPath : '/$newPath';
    final encodedNewPath = Uri.encodeFull(baseUrl + destPath);

    final response = await client.request(
      oldPath,
      method: 'MOVE',
      headers: {
        'Destination': encodedNewPath,
        'Overwrite': 'T',
      },
    );

    // 201 Created (如果目标不存在并被创建) 或 204 No Content (如果目标被覆盖)
    if (response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to move path: ${response.statusCode}');
    }
  }

  /// 复制远端文件/目录 (COPY)
  /// [sourcePath] 源路径
  /// [destinationPath] 目标路径
  Future<void> copy(String sourcePath, String destinationPath) async {
    String baseUrl = client.dio.options.baseUrl;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    String destPath = destinationPath.startsWith('/') ? destinationPath : '/$destinationPath';
    final encodedDestPath = Uri.encodeFull(baseUrl + destPath);

    final response = await client.request(
      sourcePath,
      method: 'COPY',
      headers: {
        'Destination': encodedDestPath,
        'Overwrite': 'T',
      },
    );

    if (response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to copy path: ${response.statusCode}');
    }
  }
}
