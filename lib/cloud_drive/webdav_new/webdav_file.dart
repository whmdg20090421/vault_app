class WebDavFile {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;
  final String? eTag;

  WebDavFile({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    this.lastModified,
    this.eTag,
  });

  @override
  String toString() {
    return 'WebDavFile(path: $path, name: $name, isDirectory: $isDirectory, size: $size, lastModified: $lastModified, eTag: $eTag)';
  }
}
