import 'dart:io';

/// 加密任务节点类型
enum NodeType {
  file,
  folder,
}

/// 节点加密状态
enum NodeStatus {
  pending_waiting,
  pending_paused,
  encrypting,
  completed,
  error,
}

/// 将字节数自动换算为人类可读格式 (B ~ TB)
String _formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const suffixes = ['KB', 'MB', 'GB', 'TB'];
  double size = bytes / 1000.0;
  int i = 0;
  while (size >= 1000 && i < suffixes.length - 1) {
    size /= 1000.0;
    i++;
  }
  return '${size.toStringAsFixed(1)} ${suffixes[i]}';
}

/// 节点状态转换帮助方法
String statusToString(NodeStatus status) {
  return status.toString().split('.').last;
}

NodeStatus stringToStatus(String statusStr) {
  return NodeStatus.values.firstWhere(
    (e) => e.toString().split('.').last == statusStr,
    orElse: () => NodeStatus.pending_waiting,
  );
}

/// 加密节点基类
abstract class EncryptionNode {
  /// 根节点特有：全局唯一任务ID
  String? taskId;

  /// 节点名称
  String name;

  /// 节点类型
  NodeType type;

  /// 是否被暂停
  bool isPaused;

  /// 原始字节数
  int rawSize;

  /// 加密状态
  NodeStatus status;

  /// 自动换算的显示大小
  String get size => _formatBytes(rawSize);

  /// 错误信息
  String? errorMessage;

  /// 全局任务参数，仅根节点需要
  Map<String, dynamic>? taskArgs;

  EncryptionNode({
    this.taskId,
    required this.name,
    required this.type,
    this.isPaused = false,
    this.rawSize = 0,
    this.status = NodeStatus.pending_waiting,
    this.errorMessage,
    this.taskArgs,
  });

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    final safeArgs = taskArgs != null ? Map<String, dynamic>.from(taskArgs!) : null;
    if (safeArgs != null && safeArgs.containsKey('masterKey')) {
      safeArgs['masterKey'] = (safeArgs['masterKey'] as List<int>).toList(); // Ensure it's a list
    }
    return {
      if (taskId != null) 'taskId': taskId,
      'name': name,
      'type': type.toString().split('.').last,
      'isPaused': isPaused,
      'rawSize': rawSize,
      'status': statusToString(status),
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (safeArgs != null) 'taskArgs': safeArgs,
    };
  }

  /// 从 JSON 反序列化
  static EncryptionNode fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    if (typeStr == 'folder') {
      return FolderNode.fromJson(json);
    } else {
      return FileNode.fromJson(json);
    }
  }
}

/// 文件节点
class FileNode extends EncryptionNode {
  /// 绝对路径，用于后续读取
  String absolutePath;

  FileNode({
    String? taskId,
    required String name,
    required this.absolutePath,
    bool isPaused = false,
    int rawSize = 0,
    NodeStatus status = NodeStatus.pending_waiting,
    String? errorMessage,
    Map<String, dynamic>? taskArgs,
  }) : super(
          taskId: taskId,
          name: name,
          type: NodeType.file,
          isPaused: isPaused,
          rawSize: rawSize,
          status: status,
          errorMessage: errorMessage,
          taskArgs: taskArgs,
        );

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['absolutePath'] = absolutePath;
    return map;
  }

  factory FileNode.fromJson(Map<String, dynamic> json) {
    return FileNode(
      taskId: json['taskId'] as String?,
      name: json['name'] as String,
      absolutePath: json['absolutePath'] as String,
      isPaused: json['isPaused'] as bool? ?? false,
      rawSize: json['rawSize'] as int? ?? 0,
      status: stringToStatus(json['status'] as String? ?? 'pending_waiting'),
      errorMessage: json['errorMessage'] as String?,
      taskArgs: json['taskArgs'] as Map<String, dynamic>?,
    );
  }
}

/// 文件夹节点
class FolderNode extends EncryptionNode {
  /// 子节点列表
  List<EncryptionNode> children;

  /// 文件夹本身的路径（如果需要的话，但通常我们通过递归构建）
  String absolutePath;

  FolderNode({
    String? taskId,
    required String name,
    required this.absolutePath,
    bool isPaused = false,
    int rawSize = 0,
    NodeStatus status = NodeStatus.pending_waiting,
    String? errorMessage,
    Map<String, dynamic>? taskArgs,
    List<EncryptionNode>? children,
  })  : children = children ?? [],
        super(
          taskId: taskId,
          name: name,
          type: NodeType.folder,
          isPaused: isPaused,
          rawSize: rawSize,
          status: status,
          errorMessage: errorMessage,
          taskArgs: taskArgs,
        );

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['absolutePath'] = absolutePath;
    map['children'] = children.map((c) => c.toJson()).toList();
    return map;
  }

  factory FolderNode.fromJson(Map<String, dynamic> json) {
    final node = FolderNode(
      taskId: json['taskId'] as String?,
      name: json['name'] as String,
      absolutePath: json['absolutePath'] as String,
      isPaused: json['isPaused'] as bool? ?? false,
      rawSize: json['rawSize'] as int? ?? 0,
      status: stringToStatus(json['status'] as String? ?? 'pending_waiting'),
      errorMessage: json['errorMessage'] as String?,
      taskArgs: json['taskArgs'] as Map<String, dynamic>?,
    );
    if (json['children'] != null) {
      final list = json['children'] as List<dynamic>;
      node.children = list.map((c) => EncryptionNode.fromJson(c as Map<String, dynamic>)).toList();
    }
    return node;
  }

  /// 动态计算总原始大小，包含所有子节点
  void recalculateRawSize() {
    int total = 0;
    for (var child in children) {
      if (child is FolderNode) {
        child.recalculateRawSize();
      }
      total += child.rawSize;
    }
    rawSize = total;
  }
}
