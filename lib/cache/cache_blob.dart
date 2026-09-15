import 'package:fmlink/cache/cache_paths.dart';

/// 资源文件本体（账号无关的共享层）
///
/// 分层约定：
/// - **本类（cache_blobs 表 + cache_resources 目录）**：只描述「文件在哪、多大、什么类型」，
///   标识仅由资源 ID 决定，**不含账号**，因此同一资源在所有账号间共用一份文件
/// - **CacheRecord（cache_records 表）**：权限、离线状态、访问记录等账号维度元数据，
///   通过 [key] 引用本表；切换账号时只重建元数据，不重复下载
class CacheBlob {
  CacheBlob({
    required this.key,
    this.url = '',
    this.localPath,
    this.fileSize,
    this.resourceType = 0,
    this.isHls = false,
    this.versionCode,
    int? createdAt,
    int? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 资源标识（同时作为文件名/目录名主干），账号无关
  final String key;

  /// 源地址（https 归一化）
  String url;

  /// 相对缓存根目录的路径；HLS 为 `{key}/index.m3u8`
  String? localPath;

  /// 文件总大小（HLS 为分片 + 密钥 + 初始化段之和）
  int? fileSize;

  int resourceType;

  /// 是否 HLS 多文件缓存（同目录下还有分片/密钥）
  bool isHls;

  String? versionCode;
  int createdAt;
  int updatedAt;

  /// 文件是否已落地且当前容器下可访问
  bool get isUsable =>
      (localPath?.isNotEmpty ?? false) && CachePaths.exists(localPath);

  /// 统一的 blob key：资源 ID 优先，缺失时用 URL 哈希；结果均为文件系统安全名
  static String keyOf({
    String resourceId = '',
    String resourceOldId = '',
    String url = '',
  }) {
    final String base =
        resourceId.isNotEmpty ? '${resourceId}_$resourceOldId' : hashUrl(url);
    return CachePaths.safeName(base);
  }

  /// 轻量字符串哈希（跨运行稳定，用于文件名兜底）
  static String hashUrl(String input) {
    var hash = 0;
    for (final int code in input.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  factory CacheBlob.fromMap(Map<String, dynamic> map) {
    return CacheBlob(
      key: (map['key'] as String?) ?? '',
      url: (map['url'] as String?) ?? '',
      localPath: map['localPath'] as String?,
      fileSize: map['fileSize'] as int?,
      resourceType: (map['resourceType'] as int?) ?? 0,
      isHls: ((map['isHls'] as int?) ?? 0) == 1,
      versionCode: map['versionCode'] as String?,
      createdAt: (map['createdAt'] as int?) ?? 0,
      updatedAt: (map['updatedAt'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'key': key,
      'url': url,
      'localPath': localPath,
      'fileSize': fileSize,
      'resourceType': resourceType,
      'isHls': isHls ? 1 : 0,
      'versionCode': versionCode,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  CacheBlob copyWith({
    String? url,
    String? localPath,
    int? fileSize,
    int? resourceType,
    bool? isHls,
    String? versionCode,
    int? createdAt,
    int? updatedAt,
  }) {
    return CacheBlob(
      key: key,
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
      fileSize: fileSize ?? this.fileSize,
      resourceType: resourceType ?? this.resourceType,
      isHls: isHls ?? this.isHls,
      versionCode: versionCode ?? this.versionCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
