import 'dart:typed_data';

/// 虚拟文件系统节点模型
class VfsNode {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;

  VfsNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.lastModified,
  });
}

/// 虚拟文件系统接口
abstract class VirtualFileSystem {
  /// 列出目录下的文件和文件夹
  Future<List<VfsNode>> list(String path);

  /// 读取文件内容 (流式下载)
  Future<Stream<List<int>>> open(String path, {int? start, int? end});

  /// 获取文件/目录信息
  Future<VfsNode> stat(String path);

  /// 上传文件，可以是本地文件路径，也可以是二进制数据流
  /// 为了通用，这里使用流式或分段上传 (可以由具体实现决定)
  Future<void> upload(String localFilePath, String remotePath);

  /// 上传数据流
  Future<void> uploadStream(Stream<List<int>> stream, int length, String remotePath);

  /// 删除文件或目录
  Future<void> delete(String path);

  /// 重命名或移动文件/目录
  Future<void> rename(String oldPath, String newPath);

  /// 创建目录
  Future<void> mkdir(String path);
}
