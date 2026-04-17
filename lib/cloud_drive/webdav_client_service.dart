import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

String _redactSensitive(String input) {
  return input
      .replaceAll(RegExp(r'Authorization:\s*Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false), 'Authorization: Basic <redacted>')
      .replaceAll(RegExp(r'Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false), 'Basic <redacted>');
}

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
  final errStr = _redactSensitive(error.toString());
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
    return '上传失败：请检查服务器空间是否已满或权限设置';
  }
  if (errStr.contains('Failed to download') || errStr.contains('Failed to read data')) {
    return '下载失败：资源可能不存在或无法访问';
  }
  if (errStr.contains('Failed to move')) {
    return '移动/重命名失败：可能是目标路径已存在或没有权限';
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
    required String password,
  }) {
    _client = webdav.newClient(
      url,
      user: username,
      password: password,
      debug: false,
    );
    _client.setConnectTimeout(30000);
    _client.setSendTimeout(30000);
    _client.setReceiveTimeout(30000);

    _client.c.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, handler) async {
        await _logError(e);
        handler.next(e);
      },
    ));
    _authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  final String url;
  final String username;
  late final webdav.Client _client;
  late final String _authHeader;

  static String _redact(String input) {
    return input
        .replaceAll(RegExp(r'Authorization:\s*Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false), 'Authorization: Basic <redacted>')
        .replaceAll(RegExp(r'Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false), 'Basic <redacted>');
  }

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
        final uri = e.requestOptions.uri.toString();
        final method = e.requestOptions.method;
        final status = e.response?.statusCode;
        final safeMessage = _redact(e.message ?? '');
        await logFile.writeAsString(
          '[$time] $method $uri status=$status type=${e.type} message=$safeMessage\n${e.stackTrace}\n\n',
          mode: FileMode.append,
          flush: true,
        );
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

  WebDavFile _mapFile(webdav.File f) {
    return WebDavFile(
      name: f.name ?? f.path?.split('/').lastWhere((e) => e.isNotEmpty, orElse: () => 'unknown') ?? 'unknown',
      path: f.path ?? '',
      isDirectory: f.isDir ?? false,
      size: f.size ?? 0,
      lastModified: f.mTime,
    );
  }

  /// PROPFIND: Get list of files in a directory
  Future<List<WebDavFile>> readDir(String path) async {
    final list = await _client.readDir(path);
    // Remove the directory itself if returned
    return list
        .where((f) => f.path != path && f.path != '$path/')
        .map(_mapFile)
        .toList();
  }

  /// MKCOL: Create a new directory
  Future<void> mkdir(String path) async {
    await _client.mkdir(path);
  }

  /// DELETE: Remove a file or directory
  Future<void> remove(String path) async {
    await _client.removeAll(path);
  }

  /// PUT: Upload a file
  Future<void> upload(String localFilePath, String remotePath) async {
    await _client.writeFromFile(localFilePath, remotePath);
  }

  /// PUT: Upload raw bytes
  Future<void> uploadData(List<int> data, String remotePath) async {
    await _client.write(remotePath, Uint8List.fromList(data));
  }

  /// PUT: Upload stream with known length
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    await _client.c.wdWriteWithStream(
      _client,
      remotePath,
      stream,
      length,
    );
  }

  /// GET: Download a file to local path
  Future<void> download(String remotePath, String localFilePath) async {
    await _client.read2File(remotePath, localFilePath);
  }

  /// GET: Read raw bytes
  Future<List<int>> readData(String remotePath) async {
    return await _client.read(remotePath);
  }

  Future<List<int>> readDataWithRange(String remotePath, {int? start, int? end}) async {
    String rangeHeader = 'bytes=';
    if (start != null) rangeHeader += '$start';
    rangeHeader += '-';
    if (end != null) rangeHeader += '$end';

    final uri = Uri.parse(url);
    final hostHeader = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    final response = await _client.c.get<List<int>>(
      _buildUrl(remotePath),
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Host': hostHeader,
          'Range': rangeHeader,
          'Authorization': _authHeader,
        },
      ),
    );
    return response.data ?? [];
  }

  /// MOVE: Rename or move a file/directory
  Future<void> rename(String oldPath, String newPath) async {
    await _client.rename(oldPath, newPath, false);
  }

  /// Get specific file info
  Future<WebDavFile> stat(String path) async {
    final f = await _client.readProps(path);
    return _mapFile(f);
  }
}
