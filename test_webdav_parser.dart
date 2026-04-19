import 'dart:io';
import 'package:xml/xml.dart';
import 'lib/cloud_drive/webdav_new/webdav_parser.dart';

void main() {
  String xml = """<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
<D:response>
<D:href>/remote.php/webdav/</D:href>
<D:propstat>
<D:prop>
<D:getlastmodified>Mon, 05 Aug 2024 10:00:00 GMT</D:getlastmodified>
<D:resourcetype><D:collection/></D:resourcetype>
</D:prop>
<D:status>HTTP/1.1 200 OK</D:status>
</D:propstat>
</D:response>
<D:response>
<D:href>/remote.php/webdav/TestFolder</D:href>
<D:propstat>
<D:prop>
<D:getlastmodified>Mon, 05 Aug 2024 10:01:00 GMT</D:getlastmodified>
<D:resourcetype><D:collection/></D:resourcetype>
</D:prop>
<D:status>HTTP/1.1 200 OK</D:status>
</D:propstat>
</D:response>
</D:multistatus>
""";

  var files = WebDavParser.parseMultiStatus(xml, '/', '/remote.php/webdav');
  for (var f in files) {
    print('name: ${f.name}, isDirectory: ${f.isDirectory}, path: ${f.path}');
  }
}
