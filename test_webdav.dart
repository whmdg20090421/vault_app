import 'dart:io';
import 'package:webdav_client/webdav_client.dart' as webdav;

void main() async {
  print('Testing WebDAV connection...');
  final client = webdav.newClient(
    'https://webdav.123pan.cn/webdav',
    user: '18302339198',
    password: 'd1fa16lh',
    debug: true,
  );

  try {
    print('1. Ping/Propfind root directory...');
    final files = await client.readDir('/');
    print('Success! Found ${files.length} items.');

    print('2. Uploading test file...');
    await client.writeFromString('/test_success.txt', 'This is a test from Dart script.');
    print('Upload success!');
  } catch (e, stack) {
    print('Error occurred: $e');
    print(stack);
  }
}
