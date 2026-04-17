import 'dart:isolate';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

class ChunkEncryptArgs {
  final Uint8List masterKey;
  final Uint8List chunkData;
  final Uint8List fileId;
  final int chunkIndex;

  ChunkEncryptArgs({
    required this.masterKey,
    required this.chunkData,
    required this.fileId,
    required this.chunkIndex,
  });
}

class ChunkDecryptArgs {
  final Uint8List masterKey;
  final Uint8List chunkData;
  final Uint8List fileId;
  final int chunkIndex;

  ChunkDecryptArgs({
    required this.masterKey,
    required this.chunkData,
    required this.fileId,
    required this.chunkIndex,
  });
}

/// 统一的 AES-256-GCM 算法封装
/// 复用密码派生的 MasterKey，支持按 Chunk 加解密
class ChunkCrypto {
  final Uint8List masterKey;

  ChunkCrypto({required this.masterKey}) {
    if (masterKey.length != 32) {
      throw ArgumentError('MasterKey must be 32 bytes (256 bits) for AES-256-GCM');
    }
  }

  /// 派生 Nonce (12 bytes)
  /// 取 fileId 的前 12 字节，最后 4 字节与 chunkIndex 异或
  static Uint8List deriveChunkNonce(Uint8List fileId, int chunkIndex) {
    if (fileId.length < 16) {
      throw ArgumentError('File ID must be at least 16 bytes');
    }
    final nonce = Uint8List.fromList(fileId.sublist(0, 12));
    final byteData = ByteData(4);
    byteData.setUint32(0, chunkIndex, Endian.big);
    for (int i = 0; i < 4; i++) {
      nonce[8 + i] ^= byteData.getUint8(i);
    }
    return nonce;
  }

  static Uint8List _encryptChunkSync(ChunkEncryptArgs args) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final chunkNonce = deriveChunkNonce(args.fileId, args.chunkIndex);
    final params = pc.AEADParameters(pc.KeyParameter(args.masterKey), 128, chunkNonce, Uint8List(0));
    cipher.init(true, params);
    
    final out = Uint8List(cipher.getOutputSize(args.chunkData.length));
    var outLen = cipher.processBytes(args.chunkData, 0, args.chunkData.length, out, 0);
    outLen += cipher.doFinal(out, outLen);
    return out.sublist(0, outLen);
  }

  static Uint8List _decryptChunkSync(ChunkDecryptArgs args) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final chunkNonce = deriveChunkNonce(args.fileId, args.chunkIndex);
    final params = pc.AEADParameters(pc.KeyParameter(args.masterKey), 128, chunkNonce, Uint8List(0));
    cipher.init(false, params);
    
    final out = Uint8List(cipher.getOutputSize(args.chunkData.length));
    var outLen = cipher.processBytes(args.chunkData, 0, args.chunkData.length, out, 0);
    outLen += cipher.doFinal(out, outLen);
    return out.sublist(0, outLen);
  }

  /// 按 Chunk 加密 (同步)
  Uint8List encryptChunkSync({
    required Uint8List chunkData,
    required Uint8List fileId,
    required int chunkIndex,
  }) {
    return _encryptChunkSync(ChunkEncryptArgs(
      masterKey: masterKey,
      chunkData: chunkData,
      fileId: fileId,
      chunkIndex: chunkIndex,
    ));
  }

  /// 按 Chunk 解密 (同步)
  Uint8List decryptChunkSync({
    required Uint8List chunkData,
    required Uint8List fileId,
    required int chunkIndex,
  }) {
    return _decryptChunkSync(ChunkDecryptArgs(
      masterKey: masterKey,
      chunkData: chunkData,
      fileId: fileId,
      chunkIndex: chunkIndex,
    ));
  }
}
