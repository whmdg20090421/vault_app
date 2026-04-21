class WebDavConfig {
  const WebDavConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
    this.password,
    this.path,
    this.fileCount,
  });

  final String id;
  final String name;
  final String url;
  final String username;
  final String? password;
  final String? path;
  final int? fileCount;

  WebDavConfig copyWith({
    String? id,
    String? name,
    String? url,
    String? username,
    String? password,
    String? path,
    int? fileCount,
  }) {
    return WebDavConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      path: path ?? this.path,
      fileCount: fileCount ?? this.fileCount,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'username': username,
      'password': password,
      'path': path,
      'fileCount': fileCount,
    };
  }

  static WebDavConfig fromJson(Map<String, Object?> json) {
    return WebDavConfig(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      password: json['password'] as String?,
      path: json['path'] as String?,
      fileCount: json['fileCount'] as int?,
    );
  }
}

