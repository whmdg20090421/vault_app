import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

void main() async {
  print('Testing AES-GCM-256...');
  final aes = AesGcm.with256bits();
  final keyBytes = Uint8List.fromList(List.generate(32, (i) => i));
  final secretKey = SecretKey(keyBytes);
  final nonce = Uint8List.fromList(List.generate(12, (i) => i));
  final data = Uint8List.fromList([1, 2, 3, 4, 5]);

  try {
    final secretBox = await aes.encrypt(data, secretKey: secretKey, nonce: nonce);
    print('AES Encrypt Success. CipherText len: ${secretBox.cipherText.length}');
    final decrypted = await aes.decrypt(secretBox, secretKey: secretKey);
    print('AES Decrypt Success. Match: ${decrypted.toString() == data.toString()}');
  } catch (e) {
    print('AES Error: $e');
  }

  print('\nTesting ChaCha20-Poly1305...');
  final chacha = Chacha20.poly1305Aead();
  try {
    final secretBox2 = await chacha.encrypt(data, secretKey: secretKey, nonce: nonce);
    print('ChaCha Encrypt Success. CipherText len: ${secretBox2.cipherText.length}');
    final decrypted2 = await chacha.decrypt(secretBox2, secretKey: secretKey);
    print('ChaCha Decrypt Success. Match: ${decrypted2.toString() == data.toString()}');
  } catch (e) {
    print('ChaCha Error: $e');
  }
}
