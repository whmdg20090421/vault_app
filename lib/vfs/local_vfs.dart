import 'dart:io';
import 'package:path/path.dart' as p;
import 'virtual_file_system.dart';

class LocalVfs implements VirtualFileSystem {
  final String rootPath;

  LocalVfs({required this.rootPath});

  String _getRealPath(String path) {
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    return p.join(rootPath, path);
  }

  VfsNode _mapEntity(FileSystemEntity entity) {
    final stat = entity.statSync();
    return VfsNode(
      name: p.basename(entity.path),
      path: entity.path.substring(rootPath.length).replaceAll(r'\', '/'),
      isDirectory: stat.type == FileSystemEntityType.directory,
      size: stat.size,
      lastModified: stat.modified,
    );
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    final realPath = _getRealPath(path);
    final dir = Directory(realPath);
    if (!await dir.exists()) return [];

    final entities = await dir.list().toList();
    return entities.map(_mapEntity).toList();
  }

  @override
  Future<Stream<List<int>>> open(String path, {int? start, int? end}) async {
    final realPath = _getRealPath(path);
    final file = File(realPath);
    return file.openRead(start, end);
  }

  @override
  Future<VfsNode> stat(String path) async {
    final realPath = _getRealPath(path);
    final type = await FileSystemEntity.type(realPath);
    if (type == FileSystemEntityType.directory) {
      return _mapEntity(Directory(realPath));
    } else {
      return _mapEntity(File(realPath));
    }
  }

  @override
  Future<void> upload(String localFilePath, String remotePath) async {
    final realPath = _getRealPath(remotePath);
    final file = File(localFilePath);
    await file.copy(realPath);
  }

  @override
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath) async {
    final realPath = _getRealPath(remotePath);
    final file = File(realPath);
    final sink = file.openWrite();
    await stream.pipe(sink);
  }

  @override
  Future<void> delete(String path) async {
    final realPath = _getRealPath(path);
    final type = await FileSystemEntity.type(realPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(realPath).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(realPath).delete();
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    final realOldPath = _getRealPath(oldPath);
    final realNewPath = _getRealPath(newPath);
    final type = await FileSystemEntity.type(realOldPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(realOldPath).rename(realNewPath);
    } else if (type == FileSystemEntityType.file) {
      await File(realOldPath).rename(realNewPath);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final realPath = _getRealPath(path);
    await Directory(realPath).create(recursive: true);
  }
}