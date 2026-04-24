import 'dart:convert';
import 'package:xml/xml.dart';

void main() {
  const xmlString = '''<?xml version="1.0" encoding="UTF-8"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>/webdav/</D:href><D:propstat><D:prop><D:displayname>加密</D:displayname><D:getlastmodified>Thu, 23 Apr 2026 11:07:25 GMT</D:getlastmodified><D:supportedlock><D:lockentry xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock><D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype><D:creationdate>Thu, 23 Apr 2026 11:07:25 GMT</D:creationdate></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response><D:response><D:href>/webdav/TF%E5%9B%BE/</D:href><D:propstat><D:prop><D:displayname>TF图</D:displayname><D:getlastmodified>Fri, 17 Apr 2026 15:47:26 GMT</D:getlastmodified><D:supportedlock><D:lockentry xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock><D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype><D:creationdate>Fri, 17 Apr 2026 15:47:26 GMT</D:creationdate></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>''';
  
  final document = XmlDocument.parse(xmlString);
  final responses = document.findAllElements('D:response');
  
  for (var response in responses) {
    final href = Uri.decodeComponent(response.findElements('D:href').first.innerText);
    final propstat = response.findElements('D:propstat').first;
    final prop = propstat.findElements('D:prop').first;
    
    final displaynameElems = prop.findElements('D:displayname');
    final displayName = displaynameElems.isNotEmpty ? displaynameElems.first.innerText : href.split('/').lastWhere((e) => e.isNotEmpty);
    
    final resourcetype = prop.findElements('D:resourcetype').first;
    final isDirectory = resourcetype.findElements('D:collection').isNotEmpty;
    
    print('【\${isDirectory ? "目录" : "文件"}】 \$displayName (路径: \$href)');
  }
}
