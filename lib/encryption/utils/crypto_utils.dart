import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

String _computeValidationCiphertext(Map<String, dynamic> args) {
  final password = args['password'] as String;
  final saltBase64 = args['saltBase64'] as String;
  final kdfType = args['kdfType'] as String;
  final kdfParams = Map<String, dynamic>.from(args['kdfParams'] as Map);
  final nonceBase64 = args['nonceBase64'] as String;
  final algorithm = args['algorithm'] as String;

  final derivedKey = CryptoUtils.deriveKey(
    password: password,
    saltBase64: saltBase64,
    kdfType: kdfType,
    kdfParams: kdfParams,
  );

  final nonceBytes = base64Url.decode(nonceBase64);
  final magicPlaintext = Uint8List.fromList(utf8.encode('vault_magic_encrypted'));
  final encryptedMagic = CryptoUtils.encrypt(
    key: derivedKey,
    nonce: nonceBytes,
    plaintext: magicPlaintext,
    algorithm: algorithm,
  );

  return base64Encode(encryptedMagic);
}

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
        desiredKeyLength: keyLength,
        version: pc.Argon2Parameters.ARGON2_VERSION_13,
        iterations: iterations,
        memory: memory,
        lanes: parallelism,
      );
      final derivator = pc.Argon2BytesGenerator()
        ..init(parameters);
      
      final out = Uint8List(keyLength);
      derivator.deriveKey(passwordBytes, 0, out, 0);
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
    return _processAead(cipher, plaintext);
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
    return _processAead(cipher, ciphertext);
  }

  static dynamic _getAEADCipher(String algorithm) {
    if (algorithm == 'AES-256-GCM') {
      return pc.GCMBlockCipher(pc.AESEngine());
    } else if (algorithm == 'ChaCha20-Poly1305') {
      return pc.ChaCha20Poly1305(pc.ChaCha7539Engine(), pc.Poly1305());
    } else {
      throw Exception('Unsupported algorithm: $algorithm');
    }
  }

  static Uint8List _processAead(dynamic cipher, Uint8List input) {
    final out = Uint8List(cipher.getOutputSize(input.length));
    var outLen = cipher.processBytes(input, 0, input.length, out, 0);
    outLen += cipher.doFinal(out, outLen);
    return out.sublist(0, outLen);
  }

  static Future<Uint8List> deriveKeyAsync({
    required String password,
    required String saltBase64,
    required String kdfType,
    required Map<String, dynamic> kdfParams,
  }) {
    return Isolate.run(
      () => deriveKey(
        password: password,
        saltBase64: saltBase64,
        kdfType: kdfType,
        kdfParams: kdfParams,
      ),
    );
  }

  static Future<String> computeValidationCiphertextAsync({
    required String password,
    required String saltBase64,
    required String kdfType,
    required Map<String, dynamic> kdfParams,
    required String nonceBase64,
    required String algorithm,
  }) {
    return Isolate.run(
      () => _computeValidationCiphertext({
        'password': password,
        'saltBase64': saltBase64,
        'kdfType': kdfType,
        'kdfParams': kdfParams,
        'nonceBase64': nonceBase64,
        'algorithm': algorithm,
      }),
    );
  }
}
