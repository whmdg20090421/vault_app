import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

void main() {
  final masterKey = Uint8List(32);
  final fixedNonce = Uint8List(12);
  final plainName = 'TF图';
  
  final cipher = pc.GCMBlockCipher(pc.AESEngine());
  final params = pc.AEADParameters(pc.KeyParameter(masterKey), 128, fixedNonce, Uint8List(0));
  cipher.init(true, params);
  
  final plaintext = utf8.encode(plainName);
  final out = Uint8List(cipher.getOutputSize(plaintext.length));
  var outLen = cipher.processBytes(Uint8List.fromList(plaintext), 0, plaintext.length, out, 0);
  outLen += cipher.doFinal(out, outLen);
  
  final ciphertext = out.sublist(0, outLen);
  final b64 = base64Url.encode(ciphertext).replaceAll('=', '');
  print('Encrypted: $b64');
  
  // Decrypt
  var padded = b64;
  while (padded.length % 4 != 0) {
    padded += '=';
  }
  final decoded = base64Url.decode(padded);
  
  final cipher2 = pc.GCMBlockCipher(pc.AESEngine());
  cipher2.init(false, params);
  final out2 = Uint8List(cipher2.getOutputSize(decoded.length));
  var outLen2 = cipher2.processBytes(decoded, 0, decoded.length, out2, 0);
  outLen2 += cipher2.doFinal(out2, outLen2);
  
  print('Decrypted: ${utf8.decode(out2.sublist(0, outLen2))}');
}
