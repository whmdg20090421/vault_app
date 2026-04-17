import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

      // 诊断式故障转移逻辑：当发现 DioException 且底层错误为 SocketException (Failed host lookup) 时触发
      if (e.error is SocketException) {
        final socketException = e.error as SocketException;
        if (socketException.message.contains('Failed host lookup')) {
          _runDnsDiagnosis(dio.options.baseUrl, socketException);
        }
      }

      throw WebDavException(msg, e.response?.statusCode);
    } catch (e) {
      _logError('Exception in request [$method $path]: $e');
      throw WebDavException(e.toString());
    }
  }

  /// 诊断式故障排查机制
  void _runDnsDiagnosis(String targetUrl, SocketException originalException) async {
    try {
      final uri = Uri.tryParse(targetUrl);
      if (uri == null) return;
      final targetDomain = uri.host;

      String stepA = '';
      String stepB = '';
      String stepC = '';
      String stepD = '';
      String proxyInfo = '';

      // 环节 B (OS Error Code)
      final osError = originalException.osError;
      if (osError != null) {
        stepB = '${osError.errorCode} (${osError.message})';
      } else {
        stepB = 'None';
      }

      // 环节 A (System Lookup)
      try {
        final addresses = await InternetAddress.lookup(targetDomain);
        stepA = '[Success] -> ${addresses.map((e) => e.address).join(', ')}';
      } catch (e) {
        stepA = '[Fail] -> ${e.toString().replaceAll('\n', ' ')}';
      }

      // 环节 C (Network Status) - 使用 baidu.com 来验证国内网络连通性
      try {
        final addresses = await InternetAddress.lookup('baidu.com');
        if (addresses.isNotEmpty) {
          stepC = '[Online]';
        } else {
          stepC = '[Offline]';
        }
      } catch (e) {
        stepC = '[Offline]';
      }

      // 环节 D 的前置检查 (代理检测)
      try {
        proxyInfo = HttpClient.findProxyFromEnvironment(uri, environment: Platform.environment);
      } catch (_) {
        proxyInfo = 'Unknown';
      }

      // 推测可能的 Root Cause (环节 D)
      if (stepA.startsWith('[Success]')) {
        stepD = '系统DNS解析正常，但 Dio 请求失败。可能是 Dio 配置异常、拦截器错误或代理 (Proxy: $proxyInfo) 仅拦截了 Dio。';
      } else if (stepC == '[Online]') {
        stepD = '系统网络在线 (可访问外部域名)，但目标域名无法解析。可能是域名失效、被运营商劫持、或设备所处网络环境限制了该域名。Proxy: $proxyInfo';
      } else if (stepC == '[Offline]') {
        stepD = '目标域名和公共域名均无法解析。设备当前可能已断网，或未授予应用 INTERNET 权限，也可能是全局 VPN/代理 ($proxyInfo) 导致所有 DNS 解析失败。';
      } else {
        stepD = '未知的网络异常情况。Proxy: $proxyInfo';
      }

      final logOutput = '''
[DNS_DIAGNOSIS_START]
- Target Domain: $targetDomain
- Step A (System Lookup): $stepA
- Step B (OS Error Code): $stepB
- Step C (Network Status): $stepC
- Step D (Possible Root Cause): $stepD
[DNS_DIAGNOSIS_END]
''';
      
      developer.log(logOutput, name: 'WebDavClient_Diagnosis');
      if (kDebugMode) {
        debugPrint(logOutput);
      }
      
      // 同时也写入到本应用的文件日志中，以便于直接查看
      _logError(logOutput);

    } catch (e) {
      developer.log('Diagnosis failed: $e', name: 'WebDavClient_Diagnosis');
    }
  }
}
