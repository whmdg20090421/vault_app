import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

class WebDavErrorLoggerInterceptor extends Interceptor {
  final String logFilePath = '/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt';

  void _writeLog(String message) {
    try {
      final file = File(logFilePath);
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
      final timestamp = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
    } catch (e) {
      print('Failed to write WebDAV error log: $e');
    }
  }

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
    _writeLog(buffer.toString());
    
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
  }) async {
    return await dio.request<T>(
      path,
      data: data,
      options: Options(
        method: method,
        headers: headers,
        responseType: responseType,
      ),
    );
  }
}
