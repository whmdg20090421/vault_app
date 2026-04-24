import 'dart:io';
import 'package:dio/dio.dart';
import 'lib/cloud_drive/webdav_new/webdav_client.dart';
import 'lib/cloud_drive/webdav_new/webdav_service.dart';
import 'lib/vfs/standard_vfs.dart';

void main() async {
  try {
    final client = WebDavClient(
      baseUrl: 'https://webdav.123pan.cn/webdav',
      username: '18302339198',
      password: 'd1fa16lh',
    );
    final service = WebDavService(client);
    final vfs = StandardVfs(service);

    print('开始连接并获取文件列表...');
    final list = await vfs.list('/');
    
    print('\n获取成功！文件列表如下：');
    for (var node in list) {
      final type = node.isDirectory ? '[目录]' : '[文件]';
      print('\$type ${node.name} (大小: ${node.size} bytes)');
    }
  } catch (e) {
    print('\n[测试失败] 发生错误: \$e');
  }
}
