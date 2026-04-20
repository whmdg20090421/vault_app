class VaultConfig {
  final int version;
  final String name;
  final String algorithm;
  final String kdf;
  final Map<String, dynamic> kdfParams;
  final bool encryptFilename;
  final String salt;
  final String nonce;
  final String validationCiphertext;
  final String? wrappedDekNonce;
  final String? wrappedDekCiphertext;

  VaultConfig({
    this.version = 1,
    required this.name,
    required this.algorithm,
    required this.kdf,
    required this.kdfParams,
    required this.encryptFilename,
    required this.salt,
    required this.nonce,
    required this.validationCiphertext,
    this.wrappedDekNonce,
    this.wrappedDekCiphertext,
  });

  factory VaultConfig.fromJson(Map<String, dynamic> json) {
    return VaultConfig(
      version: json['version'] as int? ?? 1,
      name: json['name'] as String,
      algorithm: json['algorithm'] as String,
      kdf: json['kdf'] as String,
      kdfParams: Map<String, dynamic>.from(json['kdfParams'] as Map),
      encryptFilename: json['encryptFilename'] as bool? ?? false,
      salt: json['salt'] as String,
      nonce: json['nonce'] as String? ?? '',
      validationCiphertext: json['validationCiphertext'] as String,
      wrappedDekNonce: json['wrappedDekNonce'] as String?,
      wrappedDekCiphertext: json['wrappedDekCiphertext'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'name': name,
      'algorithm': algorithm,
      'kdf': kdf,
      'kdfParams': kdfParams,
      'encryptFilename': encryptFilename,
      'salt': salt,
      'nonce': nonce,
      'validationCiphertext': validationCiphertext,
      if (wrappedDekNonce != null) 'wrappedDekNonce': wrappedDekNonce,
      if (wrappedDekCiphertext != null) 'wrappedDekCiphertext': wrappedDekCiphertext,
    };
  }
}
