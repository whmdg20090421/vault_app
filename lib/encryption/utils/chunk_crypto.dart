import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

/// 统一的 AES-256-GCM 算法封装
/// 复用密码派生的 MasterKey，支持按 Chunk 加解密
class ChunkCrypto {
  final Uint8List masterKey;

  ChunkCrypto({required this.masterKey}) {
    if (masterKey.length != 32) {
      throw ArgumentError('MasterKey must be 32 bytes (256 bits) for AES-256-GCM');
    }
  }

  /// 按 Chunk 加密
  /// [chunkData] 待加密的明文数据块
  /// [chunkNonce] 用于当前块的 Nonce (必须保证对同一 Key 唯一，一般长度为 12 bytes)
  Uint8List encryptChunk({
    required Uint8List chunkData,
    required Uint8List chunkNonce,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final params = pc.AEADParameters(pc.KeyParameter(masterKey), 128, chunkNonce, Uint8List(0));
    cipher.init(true, params);
    
    final out = Uint8List(cipher.getOutputSize(chunkData.length));
    var outLen = cipher.processBytes(chunkData, 0, chunkData.length, out, 0);
    outLen += cipher.doFinal(out, outLen);
    return out.sublist(0, outLen);
  }

  /// 按 Chunk 解密
  /// [chunkData] 待解密的密文数据块 (包含 16 bytes 的 GCM tag)
  /// [chunkNonce] 加密时使用的同一 Nonce
  Uint8List decryptChunk({
    required Uint8List chunkData,
    required Uint8List chunkNonce,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final params = pc.AEADParameters(pc.KeyParameter(masterKey), 128, chunkNonce, Uint8List(0));
    cipher.init(false, params);
    
    final out = Uint8List(cipher.getOutputSize(chunkData.length));
    var outLen = cipher.processBytes(chunkData, 0, chunkData.length, out, 0);
    outLen += cipher.doFinal(out, outLen);
    return out.sublist(0, outLen);
  }
}
