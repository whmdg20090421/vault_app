import 'dart:collection';
import 'dart:convert';

class DfsFormatUtils {
  /// 将平铺的 Map 解析为内存树，然后进行 DFS 遍历
  /// 返回一个 LinkedHashMap，保证按严格的 DFS 顺序（同级文件夹优先，然后是文件）插入键值对
  static LinkedHashMap<String, dynamic> sortAndFillDFS(Map<String, dynamic> flatMap) {
    final tree = <String, dynamic>{};
    
    for (final entry in flatMap.entries) {
      final path = entry.key;
      final parts = path.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) continue;
      
      Map<String, dynamic> current = tree;
      for (int i = 0; i < parts.length - 1; i++) {
        final part = parts[i];
        if (!current.containsKey(part)) {
          current[part] = <String, dynamic>{};
        }
        current = current[part] as Map<String, dynamic>;
      }
      
      final lastPart = parts.last;
      if (!current.containsKey(lastPart)) {
        current[lastPart] = <String, dynamic>{};
      }
      (current[lastPart] as Map<String, dynamic>)['__data__'] = entry.value;
    }
    
    final result = LinkedHashMap<String, dynamic>();
    
    void traverse(Map<String, dynamic> node, String currentPath) {
      final dirs = <String>[];
      final files = <String>[];
      
      for (final key in node.keys) {
        if (key == '__data__') continue;
        
        final childNode = node[key] as Map<String, dynamic>;
        bool isDir = false;
        
        if (childNode.keys.any((k) => k != '__data__')) {
          isDir = true;
        } else {
          final data = childNode['__data__'];
          if (data is Map && data['isDirectory'] == true) {
            isDir = true;
          }
        }
        
        if (isDir) {
          dirs.add(key);
        } else {
          files.add(key);
        }
      }
      
      dirs.sort();
      files.sort();
      
      for (final dir in dirs) {
        final path = currentPath.isEmpty ? '/$dir' : '$currentPath/$dir';
        final childNode = node[dir] as Map<String, dynamic>;
        
        if (childNode.containsKey('__data__')) {
          result[path] = childNode['__data__'];
        } else {
          result[path] = {'isDirectory': true};
        }
        traverse(childNode, path);
      }
      
      for (final file in files) {
        final path = currentPath.isEmpty ? '/$file' : '$currentPath/$file';
        final childNode = node[file] as Map<String, dynamic>;
        result[path] = childNode['__data__'];
      }
    }
    
    traverse(tree, '');
    return result;
  }

  /// 手动拼接 JSON 字符串，确保每个文件/文件夹独占一行
  static String customJsonEncode(Map<String, dynamic> otherContent, Map<String, dynamic> directoryContent) {
    final buffer = StringBuffer();
    buffer.writeln('{');
    
    final otherKeys = otherContent.keys.toList();
    for (int i = 0; i < otherKeys.length; i++) {
      final key = otherKeys[i];
      final value = otherContent[key];
      final encodedValue = jsonEncode(value);
      buffer.writeln('  ${jsonEncode(key)}: $encodedValue,');
    }
    
    buffer.writeln('  "目录": {');
    
    final dirKeys = directoryContent.keys.toList();
    for (int i = 0; i < dirKeys.length; i++) {
      final key = dirKeys[i];
      final value = directoryContent[key];
      final encodedValue = jsonEncode(value);
      final comma = i < dirKeys.length - 1 ? ',' : '';
      buffer.writeln('    ${jsonEncode(key)}: $encodedValue$comma');
    }
    
    buffer.writeln('  }');
    buffer.writeln('}');
    
    return buffer.toString();
  }
}
