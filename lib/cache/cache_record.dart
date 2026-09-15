/// 缓存状态
enum CacheStatus {
  pending(0, '待缓存'),
  downloading(1, '缓存中'),
  completed(2, '已缓存'),
  failed(3, '缓存失败');

  const CacheStatus(this.value, this.label);

  final int value;
  final String label;

  static CacheStatus fromValue(int v) {
    for (final CacheStatus s in CacheStatus.values) {
      if (s.value == v) return s;
    }
    return CacheStatus.pending;
  }
}

/// 缓存记录模型（**账号维度元数据**）
///
/// 一条记录 = 某账号下「某资源的离线状态 + 权限校验结果 + 访问记录」，
/// 通过 [blobKey] 引用账号无关的文件本体（cache_blobs 表 / cache_resources 目录）：
/// 切换账号时只需重建元数据，文件本体可直接复用，无需重复下载。
///
/// 注意：[url] / [localPath] / [fileSize] 是**派生字段**，读取时由 blob 层填充，
/// 不写入 cache_records 表。
class CacheRecord {
  int? id;
  String accountId; // 账号隔离键（UserInfo.userId），'' 为未登录
  String blobKey; // 指向 CacheBlob.key（账号无关）
  String resourceId; // resource.id
  String resourceOldId; // resource.resourceId
  String resourceName; // 资源标题
  int resourceType; // ResourceType.value（1文本/2图片/3音频/4视频/6模型）
  String? resourceSuffix; // 文件后缀
  String url; // 派生：原始网络地址（https 归一化）
  String? localPath; // 派生：本地文件路径（相对缓存根目录）
  int? fileSize; // 派生：文件大小（字节）
  String goodsId; // 出版物 ID（聚合用）
  String goodsName; // 出版物名称
  String goodsImage; // 出版物封面
  String isliCode; // 链码
  String? versionCode; // 版本号
  int resourceIndex; // 在播放页资源列表中的下标（用于跳转定位）
  int status; // CacheStatus.value（账号维度的离线状态）
  double progress; // 0.0~1.0
  int permission; // 权限校验结果：1 已通过（允许离线访问）
  int accessCount; // 访问记录：播放/打开次数
  int? lastAccessAt; // 访问记录：最近访问时间（毫秒）
  int createdAt; // 时间戳（毫秒）
  int updatedAt;

  CacheRecord({
    this.id,
    this.accountId = '',
    this.blobKey = '',
    this.resourceId = '',
    this.resourceOldId = '',
    this.resourceName = '',
    this.resourceType = 0,
    this.resourceSuffix,
    this.url = '',
    this.localPath,
    this.fileSize,
    this.goodsId = '',
    this.goodsName = '',
    this.goodsImage = '',
    this.isliCode = '',
    this.versionCode,
    this.resourceIndex = 0,
    this.status = 0, // CacheStatus.pending.value
    this.progress = 0,
    this.permission = 0,
    this.accessCount = 0,
    this.lastAccessAt,
    int? createdAt,
    int? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  CacheStatus get statusEnum => CacheStatus.fromValue(status);

  bool get isCompleted => status == CacheStatus.completed.value;

  /// 是否已通过权限校验（可离线访问）
  bool get isPermitted => permission == 1;

  /// 源地址是否为 HLS(m3u8) 视频（后缀判定，无后缀的 CDN 地址由下载时探测兜底）
  bool get isHlsSource {
    final String u = url.toLowerCase().split('?').first;
    if (u.endsWith('.m3u8') || u.endsWith('.m3u')) return true;
    final String suffix = (resourceSuffix ?? '').toLowerCase();
    return suffix.contains('m3u8') || suffix.contains('m3u');
  }

  /// 本地是否为 HLS 多文件缓存（入口为 .m3u8 时，同目录下还有分片/密钥文件）
  bool get isHlsLocal => (localPath ?? '').toLowerCase().endsWith('.m3u8');

  /// 从「记录 + 关联 blob」的结果集构造
  ///
  /// blob 字段（url/localPath/fileSize/isHls）由 CacheDatabase 的联表查询带出，
  /// 故此处直接读取，保持上层调用方式不变。
  factory CacheRecord.fromMap(Map<String, dynamic> map) {
    return CacheRecord(
      id: map['id'] as int?,
      accountId: (map['accountId'] as String?) ?? '',
      blobKey: (map['blobKey'] as String?) ?? '',
      resourceId: (map['resourceId'] as String?) ?? '',
      resourceOldId: (map['resourceOldId'] as String?) ?? '',
      resourceName: (map['resourceName'] as String?) ?? '',
      resourceType: (map['resourceType'] as int?) ?? 0,
      resourceSuffix: map['resourceSuffix'] as String?,
      // 派生字段：优先取 blob 层（别名 blobUrl 等），兼容旧列名兜底
      url: (map['blobUrl'] as String?) ?? (map['url'] as String?) ?? '',
      localPath: (map['blobPath'] as String?) ?? (map['localPath'] as String?),
      fileSize: (map['blobSize'] as int?) ?? (map['fileSize'] as int?),
      goodsId: (map['goodsId'] as String?) ?? '',
      goodsName: (map['goodsName'] as String?) ?? '',
      goodsImage: (map['goodsImage'] as String?) ?? '',
      isliCode: (map['isliCode'] as String?) ?? '',
      versionCode: map['versionCode'] as String?,
      resourceIndex: (map['resourceIndex'] as int?) ?? 0,
      status: (map['status'] as int?) ?? CacheStatus.pending.value,
      progress: ((map['progress'] as num?) ?? 0).toDouble(),
      permission: (map['permission'] as int?) ?? 0,
      accessCount: (map['accessCount'] as int?) ?? 0,
      lastAccessAt: map['lastAccessAt'] as int?,
      createdAt: (map['createdAt'] as int?) ?? 0,
      updatedAt: (map['updatedAt'] as int?) ?? 0,
    );
  }

  /// 账号维度元数据（写入 cache_records；不含派生字段）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'accountId': accountId,
      'blobKey': blobKey,
      'resourceId': resourceId,
      'resourceOldId': resourceOldId,
      'resourceName': resourceName,
      'resourceType': resourceType,
      'resourceSuffix': resourceSuffix,
      'goodsId': goodsId,
      'goodsName': goodsName,
      'goodsImage': goodsImage,
      'isliCode': isliCode,
      'versionCode': versionCode,
      'resourceIndex': resourceIndex,
      'status': status,
      'progress': progress,
      'permission': permission,
      'accessCount': accessCount,
      'lastAccessAt': lastAccessAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  CacheRecord copyWith({
    int? id,
    String? accountId,
    String? blobKey,
    String? resourceId,
    String? resourceOldId,
    String? resourceName,
    int? resourceType,
    String? resourceSuffix,
    String? url,
    String? localPath,
    int? fileSize,
    String? goodsId,
    String? goodsName,
    String? goodsImage,
    String? isliCode,
    String? versionCode,
    int? resourceIndex,
    int? status,
    double? progress,
    int? permission,
    int? accessCount,
    int? lastAccessAt,
    int? createdAt,
    int? updatedAt,
  }) {
    return CacheRecord(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      blobKey: blobKey ?? this.blobKey,
      resourceId: resourceId ?? this.resourceId,
      resourceOldId: resourceOldId ?? this.resourceOldId,
      resourceName: resourceName ?? this.resourceName,
      resourceType: resourceType ?? this.resourceType,
      resourceSuffix: resourceSuffix ?? this.resourceSuffix,
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
      fileSize: fileSize ?? this.fileSize,
      goodsId: goodsId ?? this.goodsId,
      goodsName: goodsName ?? this.goodsName,
      goodsImage: goodsImage ?? this.goodsImage,
      isliCode: isliCode ?? this.isliCode,
      versionCode: versionCode ?? this.versionCode,
      resourceIndex: resourceIndex ?? this.resourceIndex,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      permission: permission ?? this.permission,
      accessCount: accessCount ?? this.accessCount,
      lastAccessAt: lastAccessAt ?? this.lastAccessAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
