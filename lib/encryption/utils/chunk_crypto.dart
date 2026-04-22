import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class ChunkCrypto {
  final Uint8List masterKey;
  late final SecretKey _secretKey;
  late final Cipher _aesGcm;
  late final Cipher _chacha20;

  ChunkCrypto({required this.masterKey}) {
    if (masterKey.length != 32) {
      throw ArgumentError('MasterKey must be 32 bytes (256 bits)');
    }
    _secretKey = SecretKey(masterKey);
    _aesGcm = AesGcm.with256bits();
    _chacha20 = Chacha20.poly1305Aead();
  }

  /// 派生 Nonce (12 bytes)
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

  /// 按 Chunk 加密 (异步)
  Future<Uint8List> encryptChunk({
    required Uint8List chunkData,
    required Uint8List fileId,
    required int chunkIndex,
    String algorithm = 'AES-256-GCM',
  }) async {
    final chunkNonce = deriveChunkNonce(fileId, chunkIndex);
    final cipher = algorithm == 'ChaCha20-Poly1305' ? _chacha20 : _aesGcm;
    
    final secretBox = await cipher.encrypt(
      chunkData,
      secretKey: _secretKey,
      nonce: chunkNonce,
    );
    
    final out = Uint8List(secretBox.cipherText.length + secretBox.mac.macBytes.length);
    out.setAll(0, secretBox.cipherText);
    out.setAll(secretBox.cipherText.length, secretBox.mac.macBytes);
    return out;
  }

  /// 按 Chunk 解密 (异步)
  Future<Uint8List> decryptChunk({
    required Uint8List chunkData,
    required Uint8List fileId,
    required int chunkIndex,
    String algorithm = 'AES-256-GCM',
  }) async {
    final chunkNonce = deriveChunkNonce(fileId, chunkIndex);
    final cipher = algorithm == 'ChaCha20-Poly1305' ? _chacha20 : _aesGcm;
    
    if (chunkData.length < 16) {
      throw ArgumentError('Encrypted chunk too small');
    }
    
    final macOffset = chunkData.length - 16;
    final cipherText = chunkData.sublist(0, macOffset);
    final macBytes = chunkData.sublist(macOffset);
    
    final secretBox = SecretBox(
      cipherText,
      nonce: chunkNonce,
      mac: Mac(macBytes),
    );
    
    final plainText = await cipher.decrypt(
      secretBox,
      secretKey: _secretKey,
    );
    return Uint8List.fromList(plainText);
  }
}
