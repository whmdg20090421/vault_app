import 'dart:convert';
import 'dart:typed_data';

/// 仅用于密文二进制数据的字符串传输编码 (Base64Url, 无 padding)
class Base64UrlUtils {
  /// 将二进制流编码为 Base64Url 字符串
  static String encode(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// 将 Base64Url 字符串解码为二进制流
  static Uint8List decode(String base64UrlString) {
    // 补齐 padding
    var padded = base64UrlString;
    while (padded.length % 4 != 0) {
      padded += '=';
    }
    return base64Url.decode(padded);
  }
}
