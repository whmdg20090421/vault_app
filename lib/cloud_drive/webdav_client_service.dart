import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:path_provider/path_provider.dart';

class WebDavFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;

  WebDavFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.lastModified,
  });
}

String translateWebDavError(Object error) {
  final errStr = error.toString();
  if (error is SocketException) {
    return '网络连接失败：请检查网络设置或服务器地址是否正确 (${error.message})';
  }
  if (errStr.contains('DioException') || errStr.contains('DioError')) {
    if (errStr.contains('connection timeout') || errStr.contains('connectTimeout')) {
      return '连接服务器超时：服务器无响应或网络不佳';
    }
    if (errStr.contains('receive timeout')) {
      return '接收数据超时：服务器响应缓慢';
    }
    if (errStr.contains('401') || errStr.contains('Unauthorized')) {
      return '认证失败：用户名或密码错误 (401)';
    }
    if (errStr.contains('403') || errStr.contains('Forbidden')) {
      return '拒绝访问：没有权限访问该资源 (403)';
    }
    if (errStr.contains('404') || errStr.contains('Not Found')) {
      return '资源未找到：请求的路径不存在 (404)';
    }
    if (errStr.contains('Failed host lookup')) {
      return 'DNS解析失败：无法找到服务器地址，请检查域名是否正确';
    }
    if (errStr.contains('Connection refused')) {
      return '连接被拒绝：服务器拒绝了连接请求，可能端口错误或服务未启动';
    }
    return '网络请求异常：请检查网络状态或服务器配置';
  }
  if (errStr.contains('401')) return '认证失败：用户名或密码错误 (401)';
  if (errStr.contains('403')) return '拒绝访问：没有权限访问该资源 (403)';
  if (errStr.contains('404')) return '资源未找到：请求的路径不存在 (404)';
  if (errStr.contains('Failed host lookup')) return 'DNS解析失败：无法找到服务器地址';
  if (errStr.contains('Connection refused')) return '连接被拒绝：可能端口错误或服务未启动';
  if (errStr.contains('Failed to upload file') || errStr.contains('Failed to upload data')) {
    return '上传失败：请检查服务器空间是否已满或权限设置 (原错误：$errStr)';
  }
  if (errStr.contains('Failed to download') || errStr.contains('Failed to read data')) {
    return '下载失败：资源可能不存在或无法访问 (原错误：$errStr)';
  }
  if (errStr.contains('Failed to move')) {
    return '移动/重命名失败：可能是目标路径已存在或没有权限 (原错误：$errStr)';
  }
  if (errStr.contains('File not found')) {
    return '文件不存在或已被删除';
  }
  
  return '操作失败：$errStr';
}

class WebDavClientService {
  WebDavClientService({
    required this.url,
    required this.username,
    required this.password,
  }) {
    _dio = Dio(BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      },
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, handler) async {
        await _logError(e);
        handler.next(e);
      },
    ));
  }

  final String url;
  final String username;
  final String password;
  late final Dio _dio;

  Future<void> _logError(DioException e) async {
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      if (dir != null) {
        final logFile = File('${dir.path}/webdav_error_log.txt');
        final time = DateTime.now().toIso8601String();
        await logFile.writeAsString('[$time] ${e.type}: ${e.message}\n${e.stackTrace}\n\n', mode: FileMode.append);
      }
    } catch (_) {}
  }

  String _buildUrl(String path) {
    String fullUrl = url;
    if (fullUrl.endsWith('/')) {
      fullUrl = fullUrl.substring(0, fullUrl.length - 1);
    }
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    final segments = path.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/');
    return fullUrl + segments;
  }

  /// PROPFIND: Get list of files in a directory
  Future<List<WebDavFile>> readDir(String path) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final hostHeader = '$host$port';

    final response = await _dio.request(
      _buildUrl(path),
      options: Options(
        method: 'PROPFIND',
        headers: {
          'Depth': '1',
          'Host': hostHeader,
        },
        responseType: ResponseType.plain,
      ),
    );

    if (response.statusCode != null && response.statusCode! >= 400) {
      throw Exception('Failed to read directory: ${response.statusCode}');
    }

    final body = response.data.toString();
    final document = XmlDocument.parse(body);
    final responses = document.findAllElements('d:response').toList();
    if (responses.isEmpty) {
      responses.addAll(document.findAllElements('response'));
    }

    List<WebDavFile> files = [];
    for (var r in responses) {
      var href = r.findElements('d:href').firstOrNull?.innerText ?? r.findElements('href').firstOrNull?.innerText ?? '';
      href = Uri.decodeComponent(href);

      final propstat = r.findElements('d:propstat').firstOrNull ?? r.findElements('propstat').firstOrNull;
      final prop = propstat?.findElements('d:prop').firstOrNull ?? propstat?.findElements('prop').firstOrNull;

      if (prop != null) {
        final resourcetype = prop.findElements('d:resourcetype').firstOrNull ?? prop.findElements('resourcetype').firstOrNull;
        final isCollection = (resourcetype?.findElements('d:collection').isNotEmpty ?? false) || (resourcetype?.findElements('collection').isNotEmpty ?? false);

        final getcontentlength = prop.findElements('d:getcontentlength').firstOrNull?.innerText ?? prop.findElements('getcontentlength').firstOrNull?.innerText ?? '0';
        final size = int.tryParse(getcontentlength) ?? 0;

        final getlastmodified = prop.findElements('d:getlastmodified').firstOrNull?.innerText ?? prop.findElements('getlastmodified').firstOrNull?.innerText;
        DateTime? lastModified;
        if (getlastmodified != null) {
          try {
            lastModified = HttpDate.parse(getlastmodified);
          } catch (e) {
            // Ignore parse error
          }
        }

        String name = href;
        if (name.endsWith('/')) {
          name = name.substring(0, name.length - 1);
        }
        name = name.split('/').last;

        files.add(WebDavFile(
          name: name,
          path: href,
          isDirectory: isCollection,
          size: size,
          lastModified: lastModified,
        ));
      }
    }
    return files;
  }

  /// MKCOL: Create a new directory
  Future<void> mkdir(String path) async {
    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    
    try {
      await _dio.request(
        _buildUrl(path),
        options: Options(
          method: 'MKCOL',
          headers: {'Host': hostHeader},
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != 405) {
        throw Exception('Failed to create directory: ${e.response?.statusCode ?? e.message}');
      }
    }
  }

  /// DELETE: Remove a file or directory
  Future<void> remove(String path) async {
    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    await _dio.request(
      _buildUrl(path),
      options: Options(
        method: 'DELETE',
        headers: {'Host': hostHeader},
      ),
    );
  }

  /// PUT: Upload a file
  Future<void> upload(String localFilePath, String remotePath) async {
    final file = File(localFilePath);
    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    await _dio.put(
      _buildUrl(remotePath),
      data: file.openRead(),
      options: Options(
        headers: {
          HttpHeaders.contentLengthHeader: await file.length(),
          'Host': hostHeader,
        },
      ),
    );
  }

  /// PUT: Upload raw bytes
  Future<void> uploadData(List<int> data, String remotePath) async {
    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    await _dio.put(
      _buildUrl(remotePath),
      data: Stream.fromIterable([data]),
      options: Options(
        headers: {
          HttpHeaders.contentLengthHeader: data.length,
          'Host': hostHeader,
        },
      ),
    );
  }

  /// GET: Download a file to local path
  Future<void> download(String remotePath, String localFilePath) async {
    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    await _dio.download(
      _buildUrl(remotePath),
      localFilePath,
      options: Options(
        headers: {'Host': hostHeader},
      ),
    );
  }

  /// GET: Read raw bytes
  Future<List<int>> readData(String remotePath) async {
    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    final response = await _dio.get<List<int>>(
      _buildUrl(remotePath),
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Host': hostHeader},
      ),
    );
    return response.data ?? [];
  }

  /// MOVE: Rename or move a file/directory
  Future<void> rename(String oldPath, String newPath) async {
    final destination = _buildUrl(newPath);
    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    await _dio.request(
      _buildUrl(oldPath),
      options: Options(
        method: 'MOVE',
        headers: {
          'Destination': destination,
          'Overwrite': 'F',
          'Host': hostHeader,
        },
      ),
    );
  }

  /// Get specific file info
  Future<WebDavFile> stat(String path) async {
    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    final response = await _dio.request(
      _buildUrl(path),
      options: Options(
        method: 'PROPFIND',
        headers: {
          'Depth': '0',
          'Host': hostHeader,
        },
        responseType: ResponseType.plain,
      ),
    );

    if (response.statusCode != null && response.statusCode! >= 400) {
      throw Exception('Failed to get file info: ${response.statusCode}');
    }

    final body = response.data.toString();
    final document = XmlDocument.parse(body);
    final responses = document.findAllElements('d:response').toList();
    if (responses.isEmpty) {
      responses.addAll(document.findAllElements('response'));
    }

    if (responses.isEmpty) throw Exception('File not found');

    var r = responses.first;
    var href = r.findElements('d:href').firstOrNull?.innerText ?? r.findElements('href').firstOrNull?.innerText ?? '';
    href = Uri.decodeComponent(href);

    final propstat = r.findElements('d:propstat').firstOrNull ?? r.findElements('propstat').firstOrNull;
    final prop = propstat?.findElements('d:prop').firstOrNull ?? propstat?.findElements('prop').firstOrNull;

    if (prop != null) {
      final resourcetype = prop.findElements('d:resourcetype').firstOrNull ?? prop.findElements('resourcetype').firstOrNull;
      final isCollection = (resourcetype?.findElements('d:collection').isNotEmpty ?? false) || (resourcetype?.findElements('collection').isNotEmpty ?? false);

      final getcontentlength = prop.findElements('d:getcontentlength').firstOrNull?.innerText ?? prop.findElements('getcontentlength').firstOrNull?.innerText ?? '0';
      final size = int.tryParse(getcontentlength) ?? 0;

      final getlastmodified = prop.findElements('d:getlastmodified').firstOrNull?.innerText ?? prop.findElements('getlastmodified').firstOrNull?.innerText;
      DateTime? lastModified;
      if (getlastmodified != null) {
        try {
          lastModified = HttpDate.parse(getlastmodified);
        } catch (e) {
          // Ignore parse error
        }
      }

      String name = href;
      if (name.endsWith('/')) {
        name = name.substring(0, name.length - 1);
      }
      name = name.split('/').last;

      return WebDavFile(
        name: name,
        path: href,
        isDirectory: isCollection,
        size: size,
        lastModified: lastModified,
      );
    }

    throw Exception('Failed to parse file info');
  }
}
