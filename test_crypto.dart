import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

void main() {
  final masterKey = Uint8List(32); // Assuming all zeros for test, or just random
  final fixedNonce = Uint8List(12);
  final plaintext = utf8.encode('tf');
  
  final cipher = pc.GCMBlockCipher(pc.AESEngine());
  final params = pc.AEADParameters(pc.KeyParameter(masterKey), 128, fixedNonce, Uint8List(0));
  cipher.init(true, params);
  
  final out = Uint8List(cipher.getOutputSize(plaintext.length));
  var outLen = cipher.processBytes(Uint8List.fromList(plaintext), 0, plaintext.length, out, 0);
  outLen += cipher.doFinal(out, outLen);
  final ciphertext = out.sublist(0, outLen);
  
  final b64 = base64Url.encode(ciphertext).replaceAll('=', '');
  print('Encrypted tf: $b64');
}
