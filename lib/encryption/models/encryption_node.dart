import 'package:path/path.dart' as p;

enum EncryptionStatus {
  pendingWaiting,
  pendingPaused,
  encrypting,
  completed,
  error,
}

enum EncryptionNodeType {
  file,
  folder,
}

class EncryptionNode {
  final String? taskId; // 仅根节点包含
  final String name;
  final EncryptionNodeType type;
  bool isPaused;
  final List<EncryptionNode>? children; // 仅文件夹节点包含
  final String? size; // 仅文件节点包含，自动换算1~1000且保留1位小数
  final int? rawSize; // 仅文件节点包含，原始字节
  EncryptionStatus? status; // 仅文件节点包含
  final String absolutePath; // 节点的绝对路径，便于后续处理
  final Map<String, dynamic>? taskArgs; // 任务参数（仅根节点包含，持久化时不保存 masterKey）

  EncryptionNode({
    this.taskId,
    required this.name,
    required this.type,
    this.isPaused = false,
    this.children,
    this.size,
    this.rawSize,
    this.status,
    required this.absolutePath,
    this.taskArgs,
  });

  // 辅助方法：自动换算字节大小
  static String formatSize(int bytes) {
    if (bytes < 1000) return '$bytes B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double s = bytes.toDouble();
    while (s >= 1000 && i < suffixes.length - 1) {
      s /= 1024;
      i++;
    }
    return '${s.toStringAsFixed(1)} ${suffixes[i]}';
  }

  // 序列化
  Map<String, dynamic> toJson() {
    final safeArgs = taskArgs == null ? null : Map<String, dynamic>.from(taskArgs!);
    if (safeArgs != null) {
      safeArgs.remove('masterKey');
      safeArgs.remove('sendPort');
    }
    return {
      if (taskId != null) 'taskId': taskId,
      'name': name,
      'type': type.name,
      'isPaused': isPaused,
      if (children != null) 'children': children!.map((e) => e.toJson()).toList(),
      if (size != null) 'size': size,
      if (rawSize != null) 'rawSize': rawSize,
      if (status != null) 'status': status!.name,
      'absolutePath': absolutePath,
      if (safeArgs != null) 'taskArgs': safeArgs,
    };
  }

  // 反序列化
  factory EncryptionNode.fromJson(Map<String, dynamic> json) {
    return EncryptionNode(
      taskId: json['taskId'] as String?,
      name: json['name'] as String,
      type: EncryptionNodeType.values.firstWhere((e) => e.name == json['type']),
      isPaused: json['isPaused'] as bool? ?? false,
      children: json['children'] != null
          ? (json['children'] as List).map((e) => EncryptionNode.fromJson(e)).toList()
          : null,
      size: json['size'] as String?,
      rawSize: json['rawSize'] as int?,
      status: json['status'] != null
          ? EncryptionStatus.values.firstWhere((e) => e.name == json['status'])
          : null,
      absolutePath: json['absolutePath'] as String,
      taskArgs: json['taskArgs'] as Map<String, dynamic>?,
    );
  }
}
