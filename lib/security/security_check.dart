import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityCheck {
  static const MethodChannel _channel = MethodChannel('vault/security');

  // Hardcoded expected hashes (you can update these before release)
  // Example: 'your_expected_apk_hash_here'
  static const String expectedApkHash = ''; 
  static const String expectedSignatureHash = '';

  static Future<void> performCheck(BuildContext context) async {
    if (!Platform.isAndroid) return;

    try {
      final apkHash = await _channel.invokeMethod<String>('getApkHash') ?? '';
      final signatureHash = await _channel.invokeMethod<String>('getSignatureHash') ?? '';

      print('Current APK Hash: $apkHash');
      print('Current Signature Hash: $signatureHash');

      // 现在的校验逻辑要求必须提供签名或APK的哈希（二者选一或都填），
      // 否则代表应用未经正确配置就发布，视为不安全。
      // 但如果你是在自己开发时运行，可以将这两个预期哈希暂时置空。
      // 为满足“未修改时不触发”的需求，我们需要检查计算出的当前哈希。
      
      // 如果预期哈希不为空，则进行严格比对
      bool isMatch = true;
      if (expectedApkHash.isNotEmpty && apkHash != expectedApkHash) {
        isMatch = false;
      }
      if (expectedSignatureHash.isNotEmpty && signatureHash != expectedSignatureHash) {
        isMatch = false;
      }
      
      // 注意：如果预期哈希都为空，我们需要获取系统自身当前的签名哈希
      // 并保存到本地，下次启动时与第一次记录的哈希对比（Trust On First Use 机制）。
      if (signatureHash.isEmpty) {
        _showErrorScreen(context, "无法读取应用签名信息，安装包可能损坏");
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final storedSignatureHash = prefs.getString('stored_signature_hash');

      if (expectedSignatureHash.isEmpty && storedSignatureHash == null) {
        // 第一次运行，将当前有效签名哈希存起来
        await prefs.setString('stored_signature_hash', signatureHash);
      } else if (expectedSignatureHash.isEmpty && storedSignatureHash != null) {
        // 已经运行过，检查当前签名是否和首次记录的签名哈希一致
        if (signatureHash != storedSignatureHash) {
          _showErrorScreen(context, "应用签名已被篡改");
          return;
        }
      }

      if (!isMatch) {
        _showErrorScreen(context, "环境校验失败或哈希不匹配");
      }
    } catch (e) {
      _showErrorScreen(context, "环境检测异常: $e");
    }
  }

  static void _showErrorScreen(BuildContext context, String errorDetails) {
    // Show a full screen dialog that cannot be dismissed
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) {
        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: Colors.red.shade900,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _SecurityPasswordWidget(errorDetails: errorDetails),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SecurityPasswordWidget extends StatefulWidget {
  final String errorDetails;
  
  const _SecurityPasswordWidget({required this.errorDetails});

  @override
  State<_SecurityPasswordWidget> createState() => _SecurityPasswordWidgetState();
}

class _SecurityPasswordWidgetState extends State<_SecurityPasswordWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _hasError = false;

  void _verify() {
    final input = _controller.text;
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    
    // Obfuscated password hash validation
    if (digest.toString() == '3d959cdcef27a62da201457b3f872b874e5b950e14f8b189f7625934327629db') {
      Navigator.of(context).pop(); // Dismiss the full screen error
    } else {
      setState(() {
        _hasError = true;
      });
      // Optionally terminate process on wrong password after some attempts
      // SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 80),
        const SizedBox(height: 24),
        const Text(
          '环境异常',
          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          widget.errorDetails,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        const Text(
          '请输入安全密码',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          obscureText: true,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            errorText: _hasError ? '密码错误' : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _verify,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red.shade900,
            ),
            child: const Text('验证并继续', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            SystemNavigator.pop();
          },
          child: const Text('退出应用', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
