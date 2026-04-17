import 'dart:io';
import 'package:path_provider/path_provider.dart';

class NetworkDiagnostics {
  /// 运行网络诊断
  /// 
  /// 包含以下测试：
  /// 1. 获取并列出所有活跃的网络接口（如 WIFI, VPN, 蜂窝网络等）
  /// 2. 测试 DNS 解析（例如 baidu.com）
  /// 3. 测试直连公网 IP（例如 110.242.68.3 百度 IP）
  /// 
  /// 如果发生错误，会将格式化的日志写入到指定的本地文件。
  static Future<void> runDiagnostics() async {
    StringBuffer logBuffer = StringBuffer();
    bool hasError = false;

    logBuffer.writeln('=== Network Diagnostics Started at ${DateTime.now()} ===');

    // 1. 检查网络接口
    logBuffer.writeln('\n--- Network Interfaces ---');
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: true,
        type: InternetAddressType.any,
      );
      if (interfaces.isEmpty) {
        logBuffer.writeln('未找到任何活跃的网络接口。');
        hasError = true;
      }
      for (var interface in interfaces) {
        logBuffer.writeln('Interface: ${interface.name}');
        for (var addr in interface.addresses) {
          logBuffer.writeln('  - IP: ${addr.address} (Type: ${addr.type.name})');
        }
      }
    } catch (e, stackTrace) {
      logBuffer.writeln('获取网络接口失败 (OS Error): $e');
      logBuffer.writeln(stackTrace);
      hasError = true;
    }

    // 2. 测试 DNS 解析
    logBuffer.writeln('\n--- DNS Resolution Test ---');
    try {
      const targetHost = 'www.baidu.com';
      logBuffer.writeln('正在解析域名: $targetHost ...');
      final addresses = await InternetAddress.lookup(targetHost);
      if (addresses.isNotEmpty) {
        logBuffer.writeln('DNS 解析成功:');
        for (var addr in addresses) {
          logBuffer.writeln('  - ${addr.address}');
        }
      } else {
        logBuffer.writeln('DNS 解析未返回任何地址。');
        hasError = true;
      }
    } catch (e, stackTrace) {
      logBuffer.writeln('DNS 解析失败 (OS Error): $e');
      logBuffer.writeln(stackTrace);
      hasError = true;
    }

    // 3. 测试公网 IP 直连
    logBuffer.writeln('\n--- Public IP Connection Test ---');
    try {
      const targetIp = '110.242.68.3'; // 百度公网 IP
      const targetPort = 80;
      logBuffer.writeln('尝试连接到公网 IP: $targetIp:$targetPort ...');
      final socket = await Socket.connect(targetIp, targetPort, timeout: const Duration(seconds: 5));
      logBuffer.writeln('连接成功: 本地端口 ${socket.port} -> 远程地址 ${socket.remoteAddress.address}:${socket.remotePort}');
      socket.destroy();
    } catch (e, stackTrace) {
      logBuffer.writeln('公网 IP 连接失败 (OS Error): $e');
      logBuffer.writeln(stackTrace);
      hasError = true;
    }

    logBuffer.writeln('\n=== Network Diagnostics Completed ===\n');

    // 4. 如果发生错误，写入日志
    if (hasError) {
      await _writeErrorLog(logBuffer.toString());
    } else {
      print('网络诊断通过，未发现异常。');
      print(logBuffer.toString());
    }
  }

  /// 写入错误日志到本地
  /// 
  /// 优先尝试写入特定路径：/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt
  /// 若失败则回退到 App 本地目录。
  static Future<void> _writeErrorLog(String logData) async {
    try {
      const primaryPath = '/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt';
      File logFile = File(primaryPath);
      
      // 确保护录存在
      bool useFallback = false;
      try {
        if (!await logFile.parent.exists()) {
          await logFile.parent.create(recursive: true);
        }
      } catch (_) {
        useFallback = true;
      }

      // 如果无法创建主路径，或者没有权限，则回退
      if (useFallback) {
        try {
          final fallbackDir = await getApplicationDocumentsDirectory();
          logFile = File('${fallbackDir.path}/webdav_error_log.txt');
        } catch (e) {
          print('无法获取回退目录: $e');
          return;
        }
      }

      await logFile.writeAsString(logData, mode: FileMode.append);
      print('网络诊断发现异常，错误日志已写入至: ${logFile.path}');
    } catch (e) {
      print('写入网络诊断日志失败: $e');
    }
  }
}
