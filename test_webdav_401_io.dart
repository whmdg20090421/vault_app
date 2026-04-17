import 'dart:io';
import 'dart:convert';

void main() async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  
  // We can use any dummy WebDAV server, e.g., Nextcloud demo or a local dummy server
  // Actually, there's a WebDAV server on the internet or we can just try connecting to a generic domain.
  // Or we can try connecting to a non-existent endpoint or a dummy one.
  // A better way is to try connecting to https://webdav.yandex.com/ with dummy credentials.
  
  final url = Uri.parse('https://webdav.yandex.com/');
  final req = await client.openUrl('PROPFIND', url);
  
  req.headers.set('Depth', '1');
  final credentials = base64Encode(utf8.encode('dummy:dummy'));
  req.headers.set('Authorization', 'Basic $credentials');
  
  try {
    final response = await req.close();
    print('Status Code: ${response.statusCode}');
    if (response.statusCode == 401) {
      print('Success: Received 401 Unauthorized');
    } else {
      print('Unexpected status code: ${response.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
