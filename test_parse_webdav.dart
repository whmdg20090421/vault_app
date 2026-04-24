import 'dart:convert';
import 'package:xml/xml.dart';

void main() {
  const xmlString = '''<?xml version="1.0" encoding="UTF-8"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>/webdav/</D:href><D:propstat><D:prop><D:displayname>加密</D:displayname><D:getlastmodified>Thu, 23 Apr 2026 11:07:25 GMT</D:getlastmodified><D:supportedlock><D:lockentry xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock><D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype><D:creationdate>Thu, 23 Apr 2026 11:07:25 GMT</D:creationdate></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response><D:response><D:href>/webdav/TF%E5%9B%BE/</D:href><D:propstat><D:prop><D:displayname>TF图</D:displayname><D:getlastmodified>Fri, 17 Apr 2026 15:47:26 GMT</D:getlastmodified><D:supportedlock><D:lockentry xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock><D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype><D:creationdate>Fri, 17 Apr 2026 15:47:26 GMT</D:creationdate></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>''';
  
  try {
    final document = XmlDocument.parse(xmlString);
    final responses = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'response');

    final baseUrlPath = '/webdav';
    final requestedPath = '/';

    for (final response in responses) {
      final hrefElement = response.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'href')
          .firstOrNull;
          
      if (hrefElement == null) continue;

      String href = hrefElement.innerText;
      href = Uri.decodeFull(href);

      String b = baseUrlPath;
      if (b.endsWith('/')) b = b.substring(0, b.length - 1);
      
      String relativePath = href;
      if (b.isNotEmpty) {
        if (relativePath == b || relativePath == b + '/') {
          relativePath = '/';
        } else if (relativePath.startsWith(b + '/')) {
          relativePath = relativePath.substring(b.length);
        }
      }
      
      if (!relativePath.startsWith('/')) {
        relativePath = '/' + relativePath;
      }

      print('Href: \$href -> Relative: \$relativePath');
      
      final resourceTypeElement = response.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'resourcetype')
          .firstOrNull;
          
      final isCollection = resourceTypeElement?.descendants
              .whereType<XmlElement>()
              .any((e) => e.name.local == 'collection') ?? false;
      final isDirectory = isCollection || relativePath.endsWith('/');

      String name = '';
      final pathSegments = relativePath.split('/').where((s) => s.isNotEmpty).toList();
      if (pathSegments.isNotEmpty) {
        name = pathSegments.last;
      }

      print('  Name: \$name, isDir: \$isDirectory');
    }
  } catch (e) {
    print('Failed: \$e');
  }
}
