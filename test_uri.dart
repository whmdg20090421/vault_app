import 'dart:core';

void main() {
  try {
    var uri = Uri.parse('/My Documents/Folder/');
    print('Parsed: \${uri.pathSegments}');
  } catch (e) {
    print('Error: \$e');
  }
}
