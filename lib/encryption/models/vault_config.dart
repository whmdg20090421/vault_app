class VaultConfig {
  final String name;
  final String algorithm;
  final String kdf;
  final Map<String, dynamic> kdfParams;
  final bool encryptFilename;
  final String salt;
  final String nonce;
  final String validationCiphertext;

  VaultConfig({
    required this.name,
    required this.algorithm,
    required this.kdf,
    required this.kdfParams,
    required this.encryptFilename,
    required this.salt,
    required this.nonce,
    required this.validationCiphertext,
  });

  factory VaultConfig.fromJson(Map<String, dynamic> json) {
    return VaultConfig(
      name: json['name'] as String,
      algorithm: json['algorithm'] as String,
      kdf: json['kdf'] as String,
      kdfParams: Map<String, dynamic>.from(json['kdfParams'] as Map),
      encryptFilename: json['encryptFilename'] as bool? ?? false,
      salt: json['salt'] as String,
      nonce: json['nonce'] as String? ?? '',
      validationCiphertext: json['validationCiphertext'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'algorithm': algorithm,
      'kdf': kdf,
      'kdfParams': kdfParams,
      'encryptFilename': encryptFilename,
      'salt': salt,
      'nonce': nonce,
      'validationCiphertext': validationCiphertext,
    };
  }
}
