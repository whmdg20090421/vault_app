import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';

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
  });

  final String url;
  final String username;
  final String password;

  /// Custom HttpClient for streaming and range requests
  Future<HttpClientRequest> createRequest(String method, String path) async {
    final client = HttpClient();
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true; // Ignore SSL errors
    
    String fullUrl = url;
    if (fullUrl.endsWith('/')) {
      fullUrl = fullUrl.substring(0, fullUrl.length - 1);
    }
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    // Encode path segments to handle spaces and special characters
    final segments = path.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/');
    final uri = Uri.parse(fullUrl + segments);
    final request = await client.openUrl(method, uri);
    final auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    request.headers.add('Authorization', auth);
    return request;
  }

  /// PROPFIND: Get list of files in a directory
  Future<List<WebDavFile>> readDir(String path) async {
    final req = await createRequest('PROPFIND', path);
    req.headers.set('Depth', '1');
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to read directory: ${resp.statusCode}');
    }
    
    final body = await resp.transform(utf8.decoder).join();
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
    final req = await createRequest('MKCOL', path);
    final resp = await req.close();
    if (resp.statusCode >= 400 && resp.statusCode != 405) { // 405 means already exists in WebDAV
      throw Exception('Failed to create directory: ${resp.statusCode}');
    }
  }

  /// DELETE: Remove a file or directory
  Future<void> remove(String path) async {
    final req = await createRequest('DELETE', path);
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to delete: ${resp.statusCode}');
    }
  }

  /// PUT: Upload a file
  Future<void> upload(String localFilePath, String remotePath) async {
    final file = File(localFilePath);
    final req = await createRequest('PUT', remotePath);
    req.contentLength = await file.length();
    await req.addStream(file.openRead());
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to upload file: ${resp.statusCode}');
    }
  }
  
  /// PUT: Upload raw bytes
  Future<void> uploadData(List<int> data, String remotePath) async {
    final req = await createRequest('PUT', remotePath);
    req.contentLength = data.length;
    req.add(data);
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to upload data: ${resp.statusCode}');
    }
  }

  /// GET: Download a file to local path
  Future<void> download(String remotePath, String localFilePath) async {
    final req = await createRequest('GET', remotePath);
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to download: ${resp.statusCode}');
    }

    final file = File(localFilePath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    await resp.pipe(sink);
  }
  
  /// GET: Read raw bytes
  Future<List<int>> readData(String remotePath) async {
    final req = await createRequest('GET', remotePath);
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to read data: ${resp.statusCode}');
    }
    final builder = BytesBuilder();
    await for (final chunk in resp) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// MOVE: Rename or move a file/directory
  Future<void> rename(String oldPath, String newPath) async {
    String fullUrl = url;
    if (fullUrl.endsWith('/')) {
      fullUrl = fullUrl.substring(0, fullUrl.length - 1);
    }
    if (!newPath.startsWith('/')) {
      newPath = '/$newPath';
    }
    final segments = newPath.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/');
    final destination = fullUrl + segments;

    final req = await createRequest('MOVE', oldPath);
    req.headers.set('Destination', destination);
    req.headers.set('Overwrite', 'F');
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to move: ${resp.statusCode}');
    }
  }
  
  /// Get specific file info
  Future<WebDavFile> stat(String path) async {
    final req = await createRequest('PROPFIND', path);
    req.headers.set('Depth', '0');
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      throw Exception('Failed to get file info: ${resp.statusCode}');
    }
    
    final body = await resp.transform(utf8.decoder).join();
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
