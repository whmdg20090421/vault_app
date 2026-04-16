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
          debug: true,
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

  /// PUT: Upload a file (can be a local path or byte data, webdav_client supports upload and uploadFile)
  Future<void> upload(String localFilePath, String remotePath) async {
    return _client.uploadFile(localFilePath, remotePath);
  }
  
  /// PUT: Upload raw bytes
  Future<void> uploadData(List<int> data, String remotePath) async {
    return _client.upload(data, remotePath);
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
    return _client.download(remotePath, localFilePath);
  }
  
  /// GET: Read raw bytes
  Future<List<int>> readData(String remotePath) async {
    return _client.read(remotePath);
  }

  /// MOVE: Rename or move a file/directory
  Future<void> rename(String oldPath, String newPath) async {
    // webdav_client move method
    // In webdav_client, the signature is move(String source, String destination, {bool overwrite = false})
    return _client.move(oldPath, newPath, overwrite: false);
  }
  
  /// Get specific file info
  Future<webdav.File> stat(String path) async {
    final list = await _client.readDir(path);
    if (list.isEmpty) throw Exception('File not found');
    return list.first;
  }
}
