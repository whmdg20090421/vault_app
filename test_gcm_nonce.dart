import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

void main() {
  final key = Uint8List(32);
  final nonce = Uint8List(12);
  
  final cipher = pc.GCMBlockCipher(pc.AESEngine());
  final params = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));
  cipher.init(true, params);
  
  final pt = utf8.encode('TF图');
  final out = Uint8List(cipher.getOutputSize(pt.length));
  var outLen = cipher.processBytes(Uint8List.fromList(pt), 0, pt.length, out, 0);
  outLen += cipher.doFinal(out, outLen);
  
  print('Nonce after encryption: $nonce');
}
