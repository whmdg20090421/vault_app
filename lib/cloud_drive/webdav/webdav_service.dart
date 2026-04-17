import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'webdav_client.dart';
import 'webdav_parser.dart';

class WebDavFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;
  final String? eTag;

  WebDavFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.lastModified,
    this.eTag,
  });
}

class WebDavService {
  final String url;
  final String username;
  late final WebDavClient _client;
  late final String _authHeader;

  WebDavService({
    required this.url,
    required this.username,
    required String password,
  }) {
    _client = WebDavClient(
      url: url,
      user: username,
      password: password,
    );
    // Intercept errors for logging if needed
    _authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  String _buildUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    final uri = Uri.parse(url);
    final basePath = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;

    String normalizedPath = path;
    if (!normalizedPath.startsWith('/')) {
      normalizedPath = '/$normalizedPath';
    }

    // If the path already starts with the base path, we should attach it directly to the origin
    if (basePath.isNotEmpty && normalizedPath.startsWith(basePath)) {
      final segments = normalizedPath.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/');
      return uri.origin + segments;
    }

    // Otherwise, append the path to the full URL
    String fullUrl = url;
    if (fullUrl.endsWith('/')) {
      fullUrl = fullUrl.substring(0, fullUrl.length - 1);
    }
    final segments = normalizedPath.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/');
    return fullUrl + segments;
  }

  WebDavFile _mapResource(WebDavResource res) {
    String decodedHref = Uri.decodeFull(res.href);
    if (decodedHref.endsWith('/')) {
      decodedHref = decodedHref.substring(0, decodedHref.length - 1);
    }
    final name = decodedHref.split('/').lastWhere((e) => e.isNotEmpty, orElse: () => 'unknown');
    
    return WebDavFile(
      name: name.isEmpty ? 'unknown' : name,
      path: decodedHref,
      isDirectory: res.isDirectory,
      size: res.size,
      lastModified: res.lastModified,
      eTag: res.eTag,
    );
  }

  /// PROPFIND: Get list of files in a directory
  Future<List<WebDavFile>> readDir(String path) async {
    final response = await _client.request(
      _buildUrl(path),
      method: 'PROPFIND',
      headers: {
        'Depth': '1',
      },
      responseType: ResponseType.plain,
    );
    
    final resources = WebDavParser.parseMultiStatus(response.data.toString());
    
    String decodedPath = Uri.decodeFull(path);
    if (decodedPath.endsWith('/')) {
      decodedPath = decodedPath.substring(0, decodedPath.length - 1);
    }

    return resources
        .where((r) {
          String h = Uri.decodeFull(r.href);
          if (h.endsWith('/')) h = h.substring(0, h.length - 1);
          return h != decodedPath;
        })
        .map(_mapResource)
        .toList();
  }

  /// MKCOL: Create a new directory
  Future<void> mkdir(String path) async {
    await _client.request(
      _buildUrl(path),
      method: 'MKCOL',
    );
  }

  /// DELETE: Remove a file or directory
  Future<void> remove(String path) async {
    await _client.request(
      _buildUrl(path),
      method: 'DELETE',
    );
  }

  /// PUT: Upload a file
  Future<void> upload(String localFilePath, String remotePath) async {
    final file = File(localFilePath);
    await _client.request(
      _buildUrl(remotePath),
      method: 'PUT',
      data: file.openRead(),
      headers: {
        Headers.contentLengthHeader: file.lengthSync(),
      },
    );
  }

  /// PUT: Upload raw bytes
  Future<void> uploadData(List<int> data, String remotePath) async {
    await _client.request(
      _buildUrl(remotePath),
      method: 'PUT',
      data: Stream.fromIterable([data]),
      headers: {
        Headers.contentLengthHeader: data.length,
      },
    );
  }

  /// PUT: Upload stream with known length
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    await _client.request(
      _buildUrl(remotePath),
      method: 'PUT',
      data: stream,
      headers: {
        Headers.contentLengthHeader: length,
      },
    );
  }

  /// GET: Download a file to local path
  Future<void> download(String remotePath, String localFilePath) async {
    final response = await _client.request(
      _buildUrl(remotePath),
      method: 'GET',
      responseType: ResponseType.stream,
    );
    final file = File(localFilePath);
    final raf = file.openSync(mode: FileMode.write);
    await for (final chunk in response.data.stream) {
      raf.writeFromSync(chunk);
    }
    raf.closeSync();
  }

  /// GET: Read raw bytes
  Future<List<int>> readData(String remotePath) async {
    final response = await _client.request(
      _buildUrl(remotePath),
      method: 'GET',
      responseType: ResponseType.bytes,
    );
    return response.data;
  }

  Future<List<int>> readDataWithRange(String remotePath, {int? start, int? end}) async {
    String rangeHeader = 'bytes=';
    if (start != null) rangeHeader += '$start';
    rangeHeader += '-';
    if (end != null) rangeHeader += '$end';

    final response = await _client.request(
      _buildUrl(remotePath),
      method: 'GET',
      headers: {
        'Range': rangeHeader,
      },
      responseType: ResponseType.bytes,
    );
    return response.data ?? <int>[];
  }

  /// MOVE: Rename or move a file/directory
  Future<void> rename(String oldPath, String newPath) async {
    await _client.request(
      _buildUrl(oldPath),
      method: 'MOVE',
      headers: {
        'Destination': _buildUrl(newPath),
        'Overwrite': 'F',
      },
    );
  }

  /// PROPFIND: Get specific file info
  Future<WebDavFile> stat(String path) async {
    final response = await _client.request(
      _buildUrl(path),
      method: 'PROPFIND',
      headers: {
        'Depth': '0',
      },
      responseType: ResponseType.plain,
    );
    final resources = WebDavParser.parseMultiStatus(response.data.toString());
    if (resources.isEmpty) {
      throw WebDavException('File not found', 404);
    }
    return _mapResource(resources.first);
  }
}
