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
    buffer.writeln('DioException: [${err.type}] ${err.message}');
    buffer.writeln('URL: ${err.requestOptions.uri}');
    
    if (err.response != null) {
      buffer.writeln('Status Code: ${err.response?.statusCode}');
      buffer.writeln('Response Data: ${err.response?.data}');
    }

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
    }
    
    buffer.writeln('--------------------------------------------------');
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
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    // Basic Auth Interceptor
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final credentials = base64Encode(utf8.encode('$username:$password'));
        options.headers['Authorization'] = 'Basic $credentials';
        return handler.next(options);
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
