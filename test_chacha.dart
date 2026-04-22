import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

void main() {
  final key = Uint8List(32);
  final nonce = Uint8List(12);
  final data = Uint8List(1024);
  
  try {
    final cipher = pc.ChaCha20Poly1305(pc.ChaCha7539Engine(), pc.Poly1305());
    final params = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));
    cipher.init(true, params);
    final out = Uint8List(cipher.getOutputSize(data.length));
    var outLen = cipher.processBytes(data, 0, data.length, out, 0);
    outLen += cipher.doFinal(out, outLen);
    print('Success, outLen: $outLen');
  } catch (e, stack) {
    print('Error: $e');
    print(stack);
  }
}
