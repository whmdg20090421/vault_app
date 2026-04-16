import 'dart:convert';
import 'dart:io';
import 'package:webdav_client/webdav_client.dart' as webdav;

class WebDavClientService {
  WebDavClientService({
    required this.url,
    required this.username,
    required this.password,
  }) : _client = webdav.newClient(
          url,
          user: username,
          password: password,
          debug: false,
        );

  final String url;
  final String username;
  final String password;
  final webdav.Client _client;

  /// PROPFIND: Get list of files in a directory
  Future<List<webdav.File>> readDir(String path) async {
    return _client.readDir(path);
  }

  /// MKCOL: Create a new directory
  Future<void> mkdir(String path) async {
    return _client.mkdir(path);
  }

  /// DELETE: Remove a file or directory
  Future<void> remove(String path) async {
    return _client.removeAll(path);
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

  /// Custom HttpClient for streaming and range requests
  Future<HttpClientRequest> createRequest(String method, String path) async {
    final client = HttpClient();
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
  Future<webdav.File> stat(String path) async {
    final list = await _client.readDir(path);
    if (list.isEmpty) throw Exception('File not found');
    return list.first;
  }
}
