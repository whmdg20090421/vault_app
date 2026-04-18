import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

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

      // If expected hashes are empty, we might skip or fail. For security, we should fail if mismatch.
      // But since they are empty initially, we should only check if they are explicitly set, 
      // or we can hardcode them later. 
      // Wait, the requirement says "if these two have any mismatch, terminate all processes...".
      // Let's assume we need to fail if they don't match the expected ones.
      // Since we don't know the exact hashes before building the release APK, 
      // we will use the logic: if expected is not empty and doesn't match, or if it's empty (strict mode).
      // Let's just compare them to expectedApkHash and expectedSignatureHash.
      // If the expected hashes are empty in development, we'll trigger the alert so the user sees it works,
      // and they can use the security password to bypass it.
      
      bool isMatch = true;
      if (expectedApkHash.isNotEmpty && apkHash != expectedApkHash) {
        isMatch = false;
      }
      if (expectedSignatureHash.isNotEmpty && signatureHash != expectedSignatureHash) {
        isMatch = false;
      }
      
      // If both expected are empty, we assume it's a mismatch to enforce the check in dev, 
      // OR we can bypass. The prompt says "如果这两个有任意不匹配".
      if (expectedApkHash.isEmpty || expectedSignatureHash.isEmpty || !isMatch) {
        // Mismatch!
        _showErrorScreen(context, "环境校验失败或哈希未配置");
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
