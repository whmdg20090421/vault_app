class WebDavConfig {
  const WebDavConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
  });

  final String id;
  final String name;
  final String url;
  final String username;

  WebDavConfig copyWith({
    String? id,
    String? name,
    String? url,
    String? username,
  }) {
    return WebDavConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'username': username,
    };
  }

  static WebDavConfig fromJson(Map<String, Object?> json) {
    return WebDavConfig(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
    );
  }
}

