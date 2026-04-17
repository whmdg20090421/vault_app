import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

class WebDavException implements Exception {
  final String message;
  final int? statusCode;

  WebDavException(this.message, [this.statusCode]);

  @override
  String toString() => 'WebDavException: $message (Status: $statusCode)';
}

class WebDavClient {
  late final Dio dio;

  WebDavClient({
    required String url,
    required String user,
    required String password,
  }) {
    dio = Dio(BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) {
        return status != null && status < 500; // Allow custom error handling for 4xx
      },
    ));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final credentials = base64Encode(utf8.encode('$user:$password'));
          options.headers['Authorization'] = 'Basic $credentials';
          return handler.next(options);
        },
      ),
    );
  }

  void _logError(String message) {
    try {
      final file = File('/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt');
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
      final timestamp = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
    } catch (_) {
      // Ignore if cannot write
    }
  }

  Future<Response> request(
    String path, {
    required String method,
    dynamic data,
    Map<String, dynamic>? headers,
    ResponseType? responseType,
  }) async {
    try {
      final response = await dio.request(
        path,
        data: data,
        options: Options(
          method: method,
          headers: headers,
          responseType: responseType,
        ),
      );
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw WebDavException('Request failed', response.statusCode);
      }
      return response;
    } on DioException catch (e) {
      final msg = e.message ?? e.error?.toString() ?? 'Unknown Dio error';
      _logError('DioException in request [$method $path]: $msg, Status: ${e.response?.statusCode}');
      throw WebDavException(msg, e.response?.statusCode);
    } catch (e) {
      _logError('Exception in request [$method $path]: $e');
      throw WebDavException(e.toString());
    }
  }
}
