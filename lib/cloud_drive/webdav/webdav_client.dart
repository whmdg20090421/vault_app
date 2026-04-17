import 'dart:convert';
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
        onError: (DioException e, handler) {
          throw WebDavException(
            e.message ?? 'Unknown Dio error',
            e.response?.statusCode,
          );
        },
      ),
    );
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
      throw WebDavException(e.message ?? 'Unknown Dio error', e.response?.statusCode);
    } catch (e) {
      throw WebDavException(e.toString());
    }
  }
}
