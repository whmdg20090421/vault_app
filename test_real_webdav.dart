import 'dart:io';
import 'package:dio/dio.dart';
import 'lib/cloud_drive/webdav/webdav_service.dart';

void main() async {
  final url = 'https://webdav.123pan.cn/webdav';
  final username = '18302339198';
  final password = 'd1fa16lh';

  print('Testing WebDAV connection to $url');
  
  final service = WebDavService(
    url: url,
    username: username,
    password: password,
  );

  try {
    // 1. Check directory (PROPFIND)
    print('\nReading root directory...');
    final files = await service.readDir('/');
    print('Successfully read root directory. Found ${files.length} items.');
    for (var file in files) {
      print(' - ${file.name} (isDir: ${file.isDirectory}, size: ${file.size})');
    }

    // 2. Create a temporary file
    print('\nCreating temporary local file...');
    final tempFile = File('test_upload.txt');
    await tempFile.writeAsString('Hello from Trae! This is a test file to verify WebDAV upload functionality.');
    
    // 3. Upload the file
    final remotePath = '/test_upload.txt';
    print('\nUploading file to $remotePath ...');
    await service.upload(tempFile.path, remotePath);
    print('Upload completed successfully!');

    // 4. Verify file exists
    print('\nVerifying file exists...');
    final uploadedFile = await service.stat(remotePath);
    print('File verified on server: ${uploadedFile.name} (size: ${uploadedFile.size})');

    // Clean up local temp file
    if (await tempFile.exists()) {
      await tempFile.delete();
      print('\nLocal temporary file cleaned up.');
    }

  } catch (e) {
    print('\nError occurred during WebDAV operations:');
    print(e);
  }
}