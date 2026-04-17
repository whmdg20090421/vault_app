export 'webdav/webdav_client.dart';
export 'webdav/webdav_service.dart';

import 'dart:io';

String _redactSensitive(String input) {
  return input
      .replaceAll(RegExp(r'Authorization:\s*Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false), 'Authorization: Basic <redacted>')
      .replaceAll(RegExp(r'Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false), 'Basic <redacted>');
}

String translateWebDavError(Object error) {
  final errStr = _redactSensitive(error.toString());
  if (error is SocketException) {
    return '网络连接失败：请检查网络设置或服务器地址是否正确 (${error.message})';
  }
  if (errStr.contains('DioException') || errStr.contains('DioError')) {
    if (errStr.contains('connection timeout') || errStr.contains('connectTimeout')) {
      return '连接服务器超时：服务器无响应或网络不佳';
    }
    if (errStr.contains('receive timeout')) {
      return '接收数据超时：服务器响应缓慢';
    }
    if (errStr.contains('401') || errStr.contains('Unauthorized')) {
      return '认证失败：用户名或密码错误 (401)';
    }
    if (errStr.contains('403') || errStr.contains('Forbidden')) {
      return '拒绝访问：没有权限访问该资源 (403)';
    }
    if (errStr.contains('404') || errStr.contains('Not Found')) {
      return '资源未找到：请求的路径不存在 (404)';
    }
    if (errStr.contains('Failed host lookup')) {
      return 'DNS解析失败：无法找到服务器地址，请检查域名是否正确';
    }
    if (errStr.contains('Connection refused')) {
      return '连接被拒绝：服务器拒绝了连接请求，可能端口错误或服务未启动';
    }
    return '网络请求异常：请检查网络状态或服务器配置';
  }
  if (errStr.contains('401')) return '认证失败：用户名或密码错误 (401)';
  if (errStr.contains('403')) return '拒绝访问：没有权限访问该资源 (403)';
  if (errStr.contains('404')) return '资源未找到：请求的路径不存在 (404)';
  if (errStr.contains('Failed host lookup')) return 'DNS解析失败：无法找到服务器地址';
  if (errStr.contains('Connection refused')) return '连接被拒绝：可能端口错误或服务未启动';
  if (errStr.contains('Failed to upload file') || errStr.contains('Failed to upload data')) {
    return '上传失败：请检查服务器空间是否已满或权限设置';
  }
  if (errStr.contains('Failed to download') || errStr.contains('Failed to read data')) {
    return '下载失败：资源可能不存在或无法访问';
  }
  if (errStr.contains('Failed to move')) {
    return '移动/重命名失败：可能是目标路径已存在或没有权限';
  }
  if (errStr.contains('File not found')) {
    return '文件不存在或已被删除';
  }
  
  return '操作失败：$errStr';
}
