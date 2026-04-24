import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'webdav_logger.dart';

class WebDavErrorLoggerInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final buffer = StringBuffer();
    buffer.writeln('=== [WebDAV Error] ===');
    buffer.writeln('DioException: [${err.type}] ${err.message}');
    
    // Request Details
    buffer.writeln('\n--- Request Details ---');
    buffer.writeln('Method: ${err.requestOptions.method}');
    buffer.writeln('URL: ${err.requestOptions.uri}');
    buffer.writeln('Headers:');
    err.requestOptions.headers.forEach((key, value) {
      // 遮离敏感信息如 Authorization
      if (key.toLowerCase() == 'authorization') {
        buffer.writeln('  $key: [HIDDEN]');
      } else {
        buffer.writeln('  $key: $value');
      }
    });
    if (err.requestOptions.data != null) {
      buffer.writeln('Request Data: ${err.requestOptions.data}');
    }

    // Response Details
    buffer.writeln('\n--- Response Details ---');
    if (err.response != null) {
      buffer.writeln('Status Code: ${err.response?.statusCode}');
      buffer.writeln('Status Message: ${err.response?.statusMessage}');
      buffer.writeln('Response Headers:');
      err.response?.headers.forEach((key, values) {
        buffer.writeln('  $key: ${values.join(', ')}');
      });
      buffer.writeln('Response Data: ${err.response?.data}');
    } else {
      buffer.writeln('No Response Received.');
    }

    // Underlying Error Details
    buffer.writeln('\n--- Underlying Error ---');
    if (err.error != null) {
      buffer.writeln('Error Details: ${err.error}');
      if (err.error is SocketException) {
        final se = err.error as SocketException;
        buffer.writeln('SocketException: ${se.message}, osError: ${se.osError}');
      } else if (err.error is TlsException) {
        final te = err.error as TlsException;
        buffer.writeln('TlsException: ${te.message}, osError: ${te.osError}');
      } else if (err.error is HttpException) {
        final he = err.error as HttpException;
        buffer.writeln('HttpException: ${he.message}, uri: ${he.uri}');
      }
    } else {
      buffer.writeln('None.');
    }
    
    buffer.writeln('==================================================');
    WebDavLogger.writeErrorLog(buffer.toString());
    
    super.onError(err, handler);
  }
}

class WebDavClient {
  late final Dio dio;

  WebDavClient({
    required String baseUrl,
    required String username,
    required String password,
  }) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Authorization': 'Basic $credentials',
      },
    ));

    // Error Logger Interceptor
    dio.interceptors.add(WebDavErrorLoggerInterceptor());
  }

  /// 统一的请求入口，支持 PROPFIND, MKCOL 等自定义 Method
  Future<Response<T>> request<T>(
    String path, {
    required String method,
    dynamic data,
    Map<String, dynamic>? headers,
    ResponseType responseType = ResponseType.plain,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return await dio.request<T>(
      path,
      data: data,
      options: Options(
        method: method,
        headers: headers,
        responseType: responseType,
      ),
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// 锁定文件或目录
  /// 返回 lockToken
  Future<String> lock(String path, {int timeout = 3600}) async {
    final lockBody = '''
<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D="DAV:">
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
  <D:owner>soloclouddrive</D:owner>
</D:lockinfo>
''';

    final response = await request(
      path,
      method: 'LOCK',
      data: lockBody,
      headers: {
        'Timeout': 'Second-$timeout',
        'Content-Type': 'application/xml; charset=utf-8',
      },
    );

    final lockTokenHeader = response.headers.value('lock-token');
    if (lockTokenHeader != null) {
      return lockTokenHeader.replaceAll('<', '').replaceAll('>', '');
    }
    
    // 如果 Header 中没有，尝试从 XML 响应中解析
    if (response.data != null && response.data.toString().isNotEmpty) {
      final dataStr = response.data.toString();
      final regex = RegExp(r'<[a-zA-Z0-9:]*href>([^<]+)</[a-zA-Z0-9:]*href>');
      final match = regex.firstMatch(dataStr);
      if (match != null) {
        final token = match.group(1);
        if (token != null && token.startsWith('opaquelocktoken:')) {
          return token;
        }
      }
    }

    throw Exception('Failed to acquire lock for $path');
  }

  /// 解锁文件或目录
  Future<void> unlock(String path, String token) async {
    await request(
      path,
      method: 'UNLOCK',
      headers: {
        'Lock-Token': '<$token>',
      },
    );
  }
}
