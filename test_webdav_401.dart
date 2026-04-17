import 'package:dio/dio.dart';

class WebDavException implements Exception {
  final String message;
  final int? statusCode;

  WebDavException(this.message, [this.statusCode]);

  @override
  String toString() => 'WebDavException: $message (Status: $statusCode)';
}

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'http://127.0.0.1:8080',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    validateStatus: (status) {
      return status != null && status < 500;
    },
  ));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Basic dummy';
        return handler.next(options);
      },
      // Simulating the original bug
      onError: (DioException e, handler) {
        throw WebDavException(
          e.message ?? 'Unknown Dio error',
          e.response?.statusCode,
        );
      },
    ),
  );

  try {
    final response = await dio.request(
      '/',
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1'},
        responseType: ResponseType.plain,
      ),
    );
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw WebDavException('Request failed', response.statusCode);
    }
    print('Success: ${response.statusCode}');
  } on DioException catch (e) {
    print('Caught DioException: ${e.message}');
  } catch (e) {
    print('Caught generic Exception: $e');
  }
}
