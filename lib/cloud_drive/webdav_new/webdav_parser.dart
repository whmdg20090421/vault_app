import 'dart:io';
import 'package:xml/xml.dart';
import 'webdav_file.dart';

class WebDavParser {
  /// 解析 WebDAV 的 207 Multi-Status 响应
  /// [xmlString] 为响应体 XML 字符串
  /// [requestedPath] 为请求的路径，用于过滤掉当前目录自身的返回节点
  static List<WebDavFile> parseMultiStatus(String xmlString, String requestedPath, String baseUrlPath) {
    final List<WebDavFile> files = [];
    XmlDocument document;
    
    try {
      document = XmlDocument.parse(xmlString);
    } catch (e) {
      print('Failed to parse WebDAV XML: $e');
      return files;
    }

    // 查找所有 response 节点（忽略前缀差异，如 d:response 或 D:response）
    final responses = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'response');

    for (final response in responses) {
      // 解析 href 节点
      final hrefElement = response.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'href')
          .firstOrNull;
          
      if (hrefElement == null) continue;

      String href = hrefElement.innerText;
      // 处理 URL 编码的路径
      href = Uri.decodeFull(href);

      // 如果包含 host，提取 path 部分
      if (href.startsWith('http://') || href.startsWith('https://')) {
        try {
          href = Uri.parse(href).path;
        } catch (_) {}
      }

      // 剥离 baseUrlPath
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
      
      // 确保以 / 开头，符合 _currentPath 风格
      if (!relativePath.startsWith('/')) {
        relativePath = '/' + relativePath;
      }

      // 过滤掉请求的目录自身
      if (_isSamePath(relativePath, requestedPath)) {
        continue;
      }

      // 查找包含具体属性的 prop 节点
      // 一个 response 可能有多个 propstat，因此可能包含多个 prop
      // 直接在 response 的后代中查找相关属性节点更稳妥
      final contentLengthElement = response.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'getcontentlength')
          .firstOrNull;
          
      final lastModifiedElement = response.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'getlastmodified')
          .firstOrNull;
          
      final resourceTypeElement = response.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'resourcetype')
          .firstOrNull;
          
      final eTagElement = response.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'getetag')
          .firstOrNull;

      // 判断是否是文件夹 (含有 collection 节点或者以 '/' 结尾)
      final isCollection = resourceTypeElement?.descendants
              .whereType<XmlElement>()
              .any((e) => e.name.local == 'collection') ?? false;
      final isDirectory = isCollection || relativePath.endsWith('/');

      // 解析大小
      int size = 0;
      if (contentLengthElement != null && contentLengthElement.innerText.isNotEmpty) {
        size = int.tryParse(contentLengthElement.innerText) ?? 0;
      }

      // 解析最后修改时间 (通常是 RFC 1123 格式)
      DateTime? lastModified;
      if (lastModifiedElement != null && lastModifiedElement.innerText.isNotEmpty) {
        try {
          lastModified = HttpDate.parse(lastModifiedElement.innerText);
        } catch (_) {
          // 忽略解析失败
        }
      }

      // 获取 ETag
      final eTag = eTagElement?.innerText;

      // 从 relativePath 提取名称
      String name = '';
      final pathSegments = relativePath.split('/').where((s) => s.isNotEmpty).toList();
      if (pathSegments.isNotEmpty) {
        name = pathSegments.last;
      }

      files.add(WebDavFile(
        path: relativePath,
        name: name,
        isDirectory: isDirectory,
        size: size,
        lastModified: lastModified,
        eTag: eTag,
      ));
    }

    return files;
  }

  /// 比较两个路径是否指向相同的目录/文件
  static bool _isSamePath(String path1, String path2) {
    String normalize(String p) {
      // 替换多个斜杠为单个斜杠，并移除尾部斜杠以进行比较
      var normalized = p.replaceAll(RegExp(r'/+'), '/');
      if (normalized.length > 1 && normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    }
    
    // WebDAV 的 href 有时包含完整的 URL 协议和主机，此处进行容错处理
    String getPathOnly(String p) {
      if (p.startsWith('http://') || p.startsWith('https://')) {
        try {
          return Uri.parse(p).path;
        } catch (_) {
          return p;
        }
      }
      return p;
    }

    return normalize(getPathOnly(path1)) == normalize(getPathOnly(path2));
  }
}
