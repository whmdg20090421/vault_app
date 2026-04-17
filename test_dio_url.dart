import 'package:dio/dio.dart';

void main() {
  var dio = Dio(BaseOptions(baseUrl: 'https://webdav.123pan.cn/webdav'));
  var req1 = dio.options.compose(dio.options, '/', method: 'GET');
  print('Request 1: ${req1.uri}');
  
  var req2 = dio.options.compose(dio.options, '', method: 'GET');
  print('Request 2: ${req2.uri}');

  var req3 = dio.options.compose(dio.options, '/folder/', method: 'GET');
  print('Request 3: ${req3.uri}');
}
