import 'dart:convert';

enum SyncDirection { cloudToLocal, localToCloud, twoWay }

enum SyncStrategy { overwrite, merge, skip }

enum SyncStatus { pending, syncing, failed, paused, completed }

enum SyncItemAction { upload, download, delete }

class SyncFileItem {
  final String path;
  final String name;
  final int size;
  SyncStatus status;
  SyncItemAction action;
  int retryCount;
  String? errorMessage;

  static const int maxRetries = 3;

  SyncFileItem({
    required this.path,
    required this.name,
    required this.size,
    this.status = SyncStatus.pending,
    this.action = SyncItemAction.upload,
    this.retryCount = 0,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'size': size,
      'status': status.name,
      'action': action.name,
      'retryCount': retryCount,
      'errorMessage': errorMessage,
    };
  }

  factory SyncFileItem.fromJson(Map<String, dynamic> json) {
    return SyncFileItem(
      path: json['path'] as String,
      name: json['name'] as String,
      size: json['size'] as int,
      status: SyncStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SyncStatus.pending,
      ),
      action: SyncItemAction.values.firstWhere(
        (e) => e.name == (json['action'] ?? 'upload'),
        orElse: () => SyncItemAction.upload,
      ),
      retryCount: json['retryCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  SyncFileItem copyWith({
    String? path,
    String? name,
    int? size,
    SyncStatus? status,
    SyncItemAction? action,
    int? retryCount,
    String? errorMessage,
  }) {
    return SyncFileItem(
      path: path ?? this.path,
      name: name ?? this.name,
      size: size ?? this.size,
      status: status ?? this.status,
      action: action ?? this.action,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SyncTask {
  final String id;
  final SyncDirection direction;
  final SyncStrategy strategy;
  SyncStatus status;
  bool isUploadPaused;
  bool isDownloadPaused;
  final List<SyncFileItem> items;
  final DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;
  int retryCount;
  String? errorMessage;
  
  final String localVaultPath;
  final String cloudWebDavId;
  final String localFolderPath;
  final String cloudFolderPath;

  static const int maxRetries = 3;

  SyncTask({
    required this.id,
    required this.direction,
    required this.strategy,
    this.status = SyncStatus.pending,
    this.isUploadPaused = false,
    this.isDownloadPaused = false,
    required this.items,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.retryCount = 0,
    this.errorMessage,
    this.localVaultPath = '',
    this.cloudWebDavId = '',
    this.localFolderPath = '/',
    this.cloudFolderPath = '/',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'direction': direction.name,
      'strategy': strategy.name,
      'status': status.name,
      'isUploadPaused': isUploadPaused,
      'isDownloadPaused': isDownloadPaused,
      'items': items.map((item) => item.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'retryCount': retryCount,
      'errorMessage': errorMessage,
      'localVaultPath': localVaultPath,
      'cloudWebDavId': cloudWebDavId,
      'localFolderPath': localFolderPath,
      'cloudFolderPath': cloudFolderPath,
    };
  }

  factory SyncTask.fromJson(Map<String, dynamic> json) {
    return SyncTask(
      id: json['id'] as String,
      direction: SyncDirection.values.firstWhere(
        (e) => e.name == json['direction'],
        orElse: () => SyncDirection.cloudToLocal,
      ),
      strategy: SyncStrategy.values.firstWhere(
        (e) => e.name == json['strategy'],
        orElse: () => SyncStrategy.skip,
      ),
      status: SyncStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SyncStatus.pending,
      ),
      isUploadPaused: json['isUploadPaused'] as bool? ?? false,
      isDownloadPaused: json['isDownloadPaused'] as bool? ?? false,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => SyncFileItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      retryCount: json['retryCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
      localVaultPath: json['localVaultPath'] as String? ?? '',
      cloudWebDavId: json['cloudWebDavId'] as String? ?? '',
      localFolderPath: json['localFolderPath'] as String? ?? '/',
      cloudFolderPath: json['cloudFolderPath'] as String? ?? '/',
    );
  }

  SyncTask copyWith({
    String? id,
    SyncDirection? direction,
    SyncStrategy? strategy,
    SyncStatus? status,
    bool? isUploadPaused,
    bool? isDownloadPaused,
    List<SyncFileItem>? items,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    int? retryCount,
    String? errorMessage,
    String? localVaultPath,
    String? cloudWebDavId,
    String? localFolderPath,
    String? cloudFolderPath,
  }) {
    return SyncTask(
      id: id ?? this.id,
      direction: direction ?? this.direction,
      strategy: strategy ?? this.strategy,
      status: status ?? this.status,
      isUploadPaused: isUploadPaused ?? this.isUploadPaused,
      isDownloadPaused: isDownloadPaused ?? this.isDownloadPaused,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
      localVaultPath: localVaultPath ?? this.localVaultPath,
      cloudWebDavId: cloudWebDavId ?? this.cloudWebDavId,
      localFolderPath: localFolderPath ?? this.localFolderPath,
      cloudFolderPath: cloudFolderPath ?? this.cloudFolderPath,
    );
  }
}
