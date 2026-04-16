import 'package:flutter/services.dart';

import 'security_level.dart';

class SecurityDetector {
  static const MethodChannel _channel = MethodChannel('vault/security');

  Future<SecurityLevel> detect() async {
    try {
      final result = await _channel.invokeMethod<String>('detectSecurityLevel');
      final parsed = SecurityLevelJson.fromJson(result);
      return parsed ?? SecurityLevel.level2;
    } catch (_) {
      return SecurityLevel.level2;
    }
  }
}

