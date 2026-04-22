import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

void main() {
  final masterKey = Uint8List(32);
  final chunkData = Uint8List(65536);
  final fileId = Uint8List(16);
  
  final sw = Stopwatch()..start();
  for (int i = 0; i < 500; i++) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final nonce = Uint8List(12);
    final params = pc.AEADParameters(pc.KeyParameter(masterKey), 128, nonce, Uint8List(0));
    cipher.init(true, params);
    final out = Uint8List(cipher.getOutputSize(chunkData.length));
    var outLen = cipher.processBytes(chunkData, 0, chunkData.length, out, 0);
    outLen += cipher.doFinal(out, outLen);
  }
  sw.stop();
  print('Recreating cipher: ${sw.elapsedMilliseconds} ms');
  
  sw.reset();
  sw.start();
  final cipher = pc.GCMBlockCipher(pc.AESEngine());
  for (int i = 0; i < 500; i++) {
    final nonce = Uint8List(12);
    final params = pc.AEADParameters(pc.KeyParameter(masterKey), 128, nonce, Uint8List(0));
    cipher.init(true, params);
    final out = Uint8List(cipher.getOutputSize(chunkData.length));
    var outLen = cipher.processBytes(chunkData, 0, chunkData.length, out, 0);
    outLen += cipher.doFinal(out, outLen);
  }
  sw.stop();
  print('Reusing cipher: ${sw.elapsedMilliseconds} ms');
}
