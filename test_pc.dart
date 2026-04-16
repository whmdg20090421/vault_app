import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

void main() {
  final key = Uint8List(32);
  final nonce = Uint8List(12);
  pc.AEADCipher cipher = pc.GCMBlockCipher(pc.AESEngine());
  final params = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));
  cipher.init(true, params);
  final data = Uint8List(1024);
  final out = cipher.process(data);
  print(out.length);
}
