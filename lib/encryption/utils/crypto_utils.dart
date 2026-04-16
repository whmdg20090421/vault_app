import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

class CryptoUtils {
  static const int keyLength = 32; // 256 bits

  static Uint8List deriveKey({
    required String password,
    required String saltBase64,
    required String kdfType,
    required Map<String, dynamic> kdfParams,
  }) {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final saltBytes = base64Url.decode(saltBase64);

    if (kdfType == 'PBKDF2') {
      final iterations = kdfParams['iterations'] as int;
      final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
        ..init(pc.Pbkdf2Parameters(saltBytes, iterations, keyLength));
      return derivator.process(passwordBytes);
    } else if (kdfType == 'Argon2id') {
      final iterations = kdfParams['iterations'] as int;
      final memory = kdfParams['memory'] as int;
      final parallelism = kdfParams['parallelism'] as int;

      final parameters = pc.Argon2Parameters(
        pc.Argon2Parameters.ARGON2_id,
        saltBytes,
        version: pc.Argon2Parameters.ARGON2_VERSION_13,
        iterations: iterations,
        memory: memory,
        lanes: parallelism,
      );
      final derivator = pc.Argon2BytesGenerator()
        ..init(parameters);
      
      final out = Uint8List(keyLength);
      derivator.generateBytes(passwordBytes, out, 0, out.length);
      return out;
    } else if (kdfType == 'Scrypt') {
      final n = kdfParams['N'] as int;
      final r = kdfParams['r'] as int;
      final p = kdfParams['p'] as int;

      final derivator = pc.Scrypt()
        ..init(pc.ScryptParameters(n, r, p, keyLength, saltBytes));
      return derivator.process(passwordBytes);
    } else {
      throw Exception('Unsupported KDF type: $kdfType');
    }
  }

  static Uint8List encrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required String algorithm,
  }) {
    final cipher = _getAEADCipher(algorithm);
    final params = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));
    cipher.init(true, params);
    return cipher.process(plaintext);
  }

  static Uint8List decrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required String algorithm,
  }) {
    final cipher = _getAEADCipher(algorithm);
    final params = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));
    cipher.init(false, params);
    return cipher.process(ciphertext);
  }

  static pc.AEADCipher _getAEADCipher(String algorithm) {
    if (algorithm == 'AES-256-GCM') {
      return pc.GCMBlockCipher(pc.AESEngine());
    } else if (algorithm == 'ChaCha20-Poly1305') {
      return pc.ChaCha20Poly1305();
    } else {
      throw Exception('Unsupported algorithm: $algorithm');
    }
  }
}
