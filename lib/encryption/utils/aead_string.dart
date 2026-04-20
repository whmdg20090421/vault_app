import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'crypto_utils.dart';

class AeadString {
  static Map<String, String> encryptUtf8({
    required Uint8List key,
    required String plaintext,
    String algorithm = 'AES-256-GCM',
  }) {
    final random = Random.secure();
    final nonce = Uint8List.fromList(List<int>.generate(12, (_) => random.nextInt(256)));
    final cipher = CryptoUtils.encrypt(
      key: key,
      nonce: nonce,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
      algorithm: algorithm,
    );
    return {
      'nonce': base64UrlEncode(nonce),
      'ciphertext': base64Encode(cipher),
    };
  }

  static String decryptUtf8({
    required Uint8List key,
    required Map<String, dynamic> payload,
    String algorithm = 'AES-256-GCM',
  }) {
    final nonceStr = payload['nonce'] as String;
    final cipherStr = payload['ciphertext'] as String;
    final nonce = base64Url.decode(_padBase64Url(nonceStr));
    final cipher = base64Decode(cipherStr);
    final plain = CryptoUtils.decrypt(
      key: key,
      nonce: nonce,
      ciphertext: cipher,
      algorithm: algorithm,
    );
    return utf8.decode(plain);
  }

  static String _padBase64Url(String input) {
    final pad = (4 - input.length % 4) % 4;
    return input + List.filled(pad, '=').join();
  }
}

