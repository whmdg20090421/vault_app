import 'dart:io';
import 'package:dio/dio.dart';
import 'lib/cloud_drive/webdav_new/webdav_client.dart';
import 'lib/cloud_drive/webdav_new/webdav_service.dart';
import 'lib/vfs/standard_vfs.dart';

void main() async {
  try {
    print('Initializing WebDAV Client...');
    final client = WebDavClient(
      baseUrl: 'https://webdav.123pan.cn/webdav',
      username: '18302339198',
      password: 'd1fa16lh',
    );
    final service = WebDavService(client);
    final vfs = StandardVfs(service);

    print('Fetching directory list for / ...');
    final list = await vfs.list('/');

    print('\n=== Directory Contents ===');
    if (list.isEmpty) {
      print('(Empty Directory)');
    } else {
      for (final item in list) {
        print('- [${item.isDirectory ? "Folder" : "File"}] ${item.name} (size: ${item.size})');
      }
    }
    print('==========================\n');
    print('Test Successful.');
    exit(0);
  } catch (e) {
    print('\n=== Error ===');
    print(e.toString());
    if (e is DioException) {
      print('Response: ${e.response?.data}');
    }
    exit(1);
  }
}