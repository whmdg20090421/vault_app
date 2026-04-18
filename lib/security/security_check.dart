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

      // Check if hashes are configured. If both are empty, we skip the strict check 
      // because the app is likely in development or unconfigured release state.
      if (expectedApkHash.isEmpty && expectedSignatureHash.isEmpty) {
        return; // No expected hashes configured, skip validation
      }

      bool isMatch = true;
      if (expectedApkHash.isNotEmpty && apkHash != expectedApkHash) {
        isMatch = false;
      }
      if (expectedSignatureHash.isNotEmpty && signatureHash != expectedSignatureHash) {
        isMatch = false;
      }
      
      // If there is any mismatch against configured hashes, we fail.
      if (!isMatch) {
        // Mismatch!
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
