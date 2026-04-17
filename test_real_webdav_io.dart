import 'dart:io';
import 'dart:convert';

void main() async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  
  final url = Uri.parse('https://webdav.123pan.cn/webdav/trae_dart_test_upload.txt');
  final req = await client.openUrl('PUT', url);
  
  final credentials = base64Encode(utf8.encode('18302339198:d1fa16lh'));
  req.headers.set('Authorization', 'Basic $credentials');
  
  final content = utf8.encode('Hello from Trae via Dart! This is another random text file to prove successful connection and upload functionality.');
  req.headers.set('Content-Length', content.length.toString());
  req.add(content);
  
  try {
    final response = await req.close();
    print('Status Code: ${response.statusCode}');
    if (response.statusCode == 201 || response.statusCode == 204) {
      print('Success: File uploaded successfully!');
    } else {
      print('Unexpected status code: ${response.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}