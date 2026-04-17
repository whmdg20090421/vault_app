void main() {
  String stripBaseUrlPath(String href, String baseUrlPath) {
    String b = baseUrlPath;
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    
    String relativePath = href;
    if (b.isNotEmpty && relativePath.startsWith(b)) {
      relativePath = relativePath.substring(b.length);
    }
    
    if (!relativePath.startsWith('/')) {
      relativePath = '/' + relativePath;
    }
    return relativePath;
  }

  print(stripBaseUrlPath('/webdav/folder1/', '/webdav')); // should be /folder1/
  print(stripBaseUrlPath('/webdav/', '/webdav')); // should be /
  print(stripBaseUrlPath('/folder1/', '')); // should be /folder1/
  print(stripBaseUrlPath('/folder1/', '/')); // should be /folder1/
}