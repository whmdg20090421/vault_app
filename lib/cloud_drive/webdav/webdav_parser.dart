import 'dart:io';
import 'package:xml/xml.dart';

class WebDavResource {
  final String href;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;
  final String? eTag;

  WebDavResource({
    required this.href,
    required this.isDirectory,
    required this.size,
    this.lastModified,
    this.eTag,
  });
}

class WebDavParser {
  static List<WebDavResource> parseMultiStatus(String xmlString) {
    final resources = <WebDavResource>[];
    if (xmlString.isEmpty) return resources;

    try {
      final document = XmlDocument.parse(xmlString);
      final responses = document.findAllElements('response', namespace: '*');
      if (responses.isEmpty) {
        // Some servers don't use namespaces correctly or we might need to fallback
        final fallbackResponses = document.findAllElements('d:response');
        if (fallbackResponses.isNotEmpty) {
          return _parseResponses(fallbackResponses);
        }
        final fallbackResponses2 = document.findAllElements('response');
        if (fallbackResponses2.isNotEmpty) {
          return _parseResponses(fallbackResponses2);
        }
      } else {
        return _parseResponses(responses);
      }
    } catch (e) {
      // Return empty list on parse error
    }
    return resources;
  }

  static List<WebDavResource> _parseResponses(Iterable<XmlElement> responses) {
    final resources = <WebDavResource>[];
    for (final response in responses) {
      final hrefElement = _findFirstElement(response, 'href');
      if (hrefElement == null) continue;

      String href = hrefElement.innerText;
      
      final propstat = _findFirstElement(response, 'propstat');
      if (propstat == null) {
        resources.add(WebDavResource(href: href, isDirectory: false, size: 0));
        continue;
      }

      final prop = _findFirstElement(propstat, 'prop');
      if (prop == null) {
        resources.add(WebDavResource(href: href, isDirectory: false, size: 0));
        continue;
      }

      final resourcetype = _findFirstElement(prop, 'resourcetype');
      bool isDirectory = false;
      if (resourcetype != null) {
        final collection = _findFirstElement(resourcetype, 'collection');
        if (collection != null) {
          isDirectory = true;
        }
      }

      final getcontentlength = _findFirstElement(prop, 'getcontentlength');
      int size = 0;
      if (getcontentlength != null) {
        size = int.tryParse(getcontentlength.innerText) ?? 0;
      }

      final getlastmodified = _findFirstElement(prop, 'getlastmodified');
      DateTime? lastModified;
      if (getlastmodified != null) {
        try {
          lastModified = HttpDate.parse(getlastmodified.innerText);
        } catch (_) {
          try {
            lastModified = DateTime.parse(getlastmodified.innerText);
          } catch (_) {}
        }
      }

      final getetag = _findFirstElement(prop, 'getetag');
      String? eTag;
      if (getetag != null) {
        eTag = getetag.innerText;
      }

      resources.add(WebDavResource(
        href: href,
        isDirectory: isDirectory,
        size: size,
        lastModified: lastModified,
        eTag: eTag,
      ));
    }
    return resources;
  }

  static XmlElement? _findFirstElement(XmlElement parent, String localName) {
    for (final child in parent.children) {
      if (child is XmlElement) {
        if (child.name.local == localName) {
          return child;
        }
      }
    }
    // Fallback to searching all descendants if direct child not found
    final descendants = parent.findAllElements(localName, namespace: '*');
    if (descendants.isNotEmpty) {
      return descendants.first;
    }
    
    // Final fallback to exact match without namespace consideration
    for (final element in parent.descendantElements) {
      if (element.name.local == localName) {
        return element;
      }
    }
    return null;
  }
}
