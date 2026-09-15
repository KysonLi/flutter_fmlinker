import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fmlink/cache/cache_blob.dart';
import 'package:fmlink/cache/cache_database.dart';
import 'package:fmlink/cache/cache_paths.dart';
import 'package:fmlink/cache/cache_record.dart';
import 'package:fmlink/cache/hls_downloader.dart';
import 'package:fmlink/common/app_navigator.dart';
import 'package:fmlink/common/constants.dart';
import 'package:fmlink/models/user_info.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/resource/source_detail.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/network_info_util.dart';

/// 添加缓存的结果
enum CacheAddResult {
  alreadyCached, // 本账号已缓存
  alreadyQueued, // 本账号已在缓存队列
  added, // 已加入队列（开始下载或待缓存）
  reused, // 命中全局共享文件本体，直接复用完成（无需下载）
  needConfirm, // 移动网络需用户确认（已加入待缓存队列）
  noAddress, // 无可用地址
  noPermission, // 无权离线访问（未购买/未解锁）
}

/// 资源缓存管理器（ChangeNotifier 单例）
///
/// 职责：
/// - 缓存队列管理（待缓存/缓存中/已缓存/失败），串行下载
/// - 网络判断：WiFi 直接下载；移动网络需确认（24h 有效期内不重复询问）
/// - 生命周期：App 启动/挂起恢复后询问是否继续未完成任务
/// - 进度通知：notifyListeners 供缓存页/播放页刷新
///
/// 存储分层（见 CacheDatabase 注释）：
/// - **文件本体全局共享**：cache_resources/{blobKey}，key 只由资源 ID 决定，不含账号。
///   切换账号下载同一资源时，只要权限校验通过就直接复用本地文件，不重复下载
/// - **元数据账号隔离**：cache_records 带 accountId，权限、离线状态、访问记录
///   均按账号分别存储；账号变化时 [syncAccount] 重新加载
class CacheService extends ChangeNotifier with WidgetsBindingObserver {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  /// 移动网络确认有效期（24 小时）
  static const Duration _cellularConfirmValidity = Duration(hours: 24);
  static const String _kCellularConfirmKey = 'cache_cellular_confirm_time';

  /// 访问记录落库节流间隔（内存计数每次都会累加，落库按此间隔合并）
  static const Duration _accessPersistInterval = Duration(seconds: 30);

  final CacheDatabase _db = CacheDatabase();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));

  List<CacheRecord> _records = [];

  /// 全局共享的文件本体索引（账号无关，blobKey → CacheBlob）
  final Map<String, CacheBlob> _blobs = <String, CacheBlob>{};

  /// 当前元数据所属账号（UserInfo.userId，'' 表示未登录）
  String _accountId = '';
  bool _loaded = false;
  bool _initialized = false;
  bool _downloading = false;
  CancelToken? _currentCancelToken;
  bool _askedContinue = false;

  /// 下载位被占用期间发生过账号切换：释放后需要重新调度新账号队列
  bool _pendingRequeue = false;

  /// 全部缓存记录（按创建时间倒序）
  List<CacheRecord> get records => List.unmodifiable(_records);

  /// 已缓存记录
  List<CacheRecord> get completed =>
      _records.where((r) => r.isCompleted).toList();

  /// 未完成任务（待缓存 + 缓存中 + 失败）
  List<CacheRecord> get unfinished =>
      _records.where((r) => !r.isCompleted).toList();

  bool get hasUnfinished => unfinished.isNotEmpty;

  // ==================== 初始化 / 账号同步 ====================

  /// 初始化：加载记录、注册生命周期观察者、询问是否继续未完成任务
  Future<void> init() async {
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addObserver(this);
      // 冷启动后询问是否继续未完成任务
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _askContinueUnfinished();
      });
    }
    await syncAccount();
  }

  /// 同步当前账号：账号变化（登录/退出/切号）时重新加载该账号的元数据
  ///
  /// 文件本体不随账号变化，切换后仍指向同一份本地文件（命中即复用）。
  Future<void> syncAccount() async {
    final String account = await _currentAccountId();
    if (_loaded && account == _accountId) return;

    // 账号切换时，进行中的下载属于旧账号：取消并把下载位让给新账号队列
    if (_accountId != account && _downloading) {
      _currentCancelToken?.cancel();
      _pendingRequeue = true;
    }
    _accountId = account;
    _loaded = true;
    await _reload();
    _pumpQueue();
  }

  /// 当前账号标识（UserId；未登录返回 ''）
  Future<String> _currentAccountId() async {
    try {
      final UserInfo? info = await UserService().getUserInfo();
      final String userId = info?.userId ?? '';
      if (userId.isNotEmpty) return userId;
    } catch (e) {
      print('获取账号标识失败: $e');
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString(Constants.kUserId) ?? '';
    } catch (e) {
      return '';
    }
  }

  /// 重新加载当前账号的元数据 + 全局文件本体索引
  Future<void> _reload() async {
    await CachePaths.init();
    // 旧版本数据无账号归属：登录态下首次同步时归到当前账号
    // （未登录时保持占位，避免把已登录用户的历史缓存错记到游客账号）
    if (_accountId.isNotEmpty) {
      try {
        await _db.claimLegacyRecords(_accountId);
      } catch (e) {
        print('迁移历史缓存归属失败: $e');
      }
    }
    _records = await _db.recordsOf(_accountId);
    _blobs
      ..clear()
      ..addEntries((await _db.blobs())
          .map((CacheBlob b) => MapEntry<String, CacheBlob>(b.key, b)));
    await _migrateLocalPaths();
    notifyListeners();
  }

  /// 存储地址特殊处理：把历史记录里的绝对路径迁移为相对路径。
  ///
  /// 绝对路径在 iOS 换包（容器 UUID 变化）或 App 迁移后会失效，
  /// 表现为「已缓存但播放/打开失败」，因此统一改为相对缓存根目录存储。
  Future<void> _migrateLocalPaths() async {
    for (final CacheBlob blob in _blobs.values) {
      final String? path = blob.localPath;
      if (path == null || path.isEmpty || !path.startsWith('/')) continue;
      final String stored = CachePaths.toStored(path);
      if (stored == path) continue;
      blob.localPath = stored;
      blob.updatedAt = DateTime.now().millisecondsSinceEpoch;
      try {
        await _db.upsertBlob(blob);
      } catch (e) {
        print('缓存路径迁移失败: $e');
      }
    }
  }

  // ==================== 查询 ====================

  /// 按资源查询缓存记录
  CacheRecord? recordFor(ScanResource r) {
    final String id = r.id?.toString() ?? '';
    final String oldId = r.resourceId ?? '';
    for (final CacheRecord rec in _records) {
      if ((id.isNotEmpty && rec.resourceId == id) ||
          (oldId.isNotEmpty && rec.resourceOldId == oldId)) {
        return rec;
      }
    }
    return null;
  }

  /// 按 URL 查询缓存记录
  CacheRecord? recordByUrl(String url) {
    for (final CacheRecord rec in _records) {
      if (rec.url == url) return rec;
    }
    return null;
  }

  /// 记录当前可用的本地路径（已缓存 + 文件真实存在时才返回）
  ///
  /// 统一在此处理容器路径变化：数据库存的是相对路径，这里还原为绝对路径；
  /// 历史绝对路径失效时按 `cache_resources/` 之后的部分重定向到当前容器。
  String? localPathFor(CacheRecord record) {
    if (!record.isCompleted || !record.isPermitted) return null;
    if (!CachePaths.exists(record.localPath)) return null;
    return CachePaths.resolve(record.localPath);
  }

  /// 记录对应的共享文件本体（若已下载完成且文件可用）
  ///
  /// 账号无关：任何账号下载过同一资源，其它账号都能命中这份文件。
  CacheBlob? usableBlobFor(CacheRecord record) {
    final String key = record.blobKey.isNotEmpty
        ? record.blobKey
        : CacheBlob.keyOf(
            resourceId: record.resourceId,
            resourceOldId: record.resourceOldId,
            url: record.url,
          );
    final CacheBlob? blob = _blobs[key];
    if (blob == null || !blob.isUsable) return null;
    return blob;
  }

  /// 记录访问记录（播放/打开一次）：accountCount++、lastAccessAt 更新
  ///
  /// 访问记录属于账号维度元数据，节流写入避免频繁落库。
  void touchAccess(CacheRecord record) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    record.accessCount++;
    final int? last = record.lastAccessAt;
    final bool needPersist =
        last == null || now - last > _accessPersistInterval.inMilliseconds;
    record.lastAccessAt = now;
    if (!needPersist) return;
    _db.update(record).catchError((Object e) {
      print('更新访问记录失败: $e');
    });
  }

  /// 某链码下所有「已缓存且文件可用」的记录（按资源下标升序），供离线播放使用
  ///
  /// - 链码比较前统一去掉非数字字符（缓存中存的是带连字符的完整链码）
  /// - 指定版本号时优先只取该版本的缓存；该版本无缓存则退回全部缓存
  List<CacheRecord> cachedByIsli(String isliCode, {String? versionCode}) {
    final String target = _digitsOf(isliCode);
    if (target.isEmpty) return <CacheRecord>[];
    final List<CacheRecord> matched = _records
        .where((CacheRecord r) =>
            r.isCompleted &&
            r.isPermitted &&
            _digitsOf(r.isliCode) == target &&
            CachePaths.exists(r.localPath))
        .toList();
    if (matched.isEmpty) return matched;

    final String? version =
        (versionCode == null || versionCode.isEmpty) ? null : versionCode;
    if (version != null) {
      final List<CacheRecord> sameVersion =
          matched.where((CacheRecord r) => r.versionCode == version).toList();
      if (sameVersion.isNotEmpty) {
        return sameVersion..sort(_byResourceIndex);
      }
    }
    return matched..sort(_byResourceIndex);
  }

  static int _byResourceIndex(CacheRecord a, CacheRecord b) =>
      a.resourceIndex.compareTo(b.resourceIndex);

  /// 链码归一化：仅保留数字
  static String _digitsOf(String? code) =>
      (code ?? '').replaceAll(RegExp(r'\D'), '');

  // ==================== 添加缓存 ====================

  /// 加入缓存队列（含网络判断与移动网络确认）
  ///
  /// [isliCode] 纯数字链码（供缓存页跳转播放页使用）
  /// [resourceIndex] 当前资源在播放页资源列表中的下标
  Future<CacheAddResult> addToCache(ScanResource r, SourceScanData data,
      {String? isliCode, int resourceIndex = 0}) async {
    final CacheRecord? existing = recordFor(r);
    if (existing != null) {
      return existing.isCompleted
          ? CacheAddResult.alreadyCached
          : CacheAddResult.alreadyQueued;
    }

    // 权限校验：未购买/未解锁的资源不允许落离线缓存（元数据按账号隔离）
    if (!data.isSourceAccessible) return CacheAddResult.noPermission;

    final String url = _httpsUrl(r.cleanAddress);
    if (url.isEmpty) return CacheAddResult.noAddress;

    final CacheRecord record =
        _buildRecord(r, data, url, isliCode, resourceIndex);

    // 文件本体全局共享：本账号未缓存但文件已存在（如切换账号后重新下载）→ 直接复用
    final CacheBlob? shared = usableBlobFor(record);
    if (shared != null) {
      record.blobKey = shared.key;
      record.permission = 1;
      record.status = CacheStatus.completed.value;
      record.progress = 1;
      record.url = shared.url.isNotEmpty ? shared.url : url;
      record.localPath = shared.localPath;
      record.fileSize = shared.fileSize;
      record.accessCount = 1;
      record.lastAccessAt = DateTime.now().millisecondsSinceEpoch;
      record.id = await _db.insert(record);
      _records.insert(0, record);
      notifyListeners();
      print('复用本地缓存文件: ${shared.key} (${record.resourceName})');
      return CacheAddResult.reused;
    }

    // 先插入待缓存记录
    record.id = await _db.insert(record);
    _records.insert(0, record);
    notifyListeners();

    // 网络判断
    final NetworkType net = await NetworkInfoUtil.getNetworkType();
    if (net == NetworkType.none) {
      // 无网络：保持待缓存，联网后由用户继续
      return CacheAddResult.added;
    }
    if (net == NetworkType.cellular) {
      final bool confirmed = await _isCellularConfirmed();
      if (!confirmed) {
        // 移动网络且未确认：保持待缓存，由 UI 层弹窗确认
        return CacheAddResult.needConfirm;
      }
    }

    // WiFi 或已确认的移动网络：开始下载
    await _pumpQueue();
    return CacheAddResult.added;
  }

  /// 用户确认移动网络下载后调用：记录确认时间并开始下载
  Future<void> confirmCellularAndStart() async {
    await _setCellularConfirmed();
    await _pumpQueue();
  }

  CacheRecord _buildRecord(ScanResource r, SourceScanData data, String url,
      String? isliCode, int resourceIndex) {
    final String resourceId = r.id?.toString() ?? '';
    final String resourceOldId = r.resourceId ?? '';
    return CacheRecord(
      accountId: _accountId,
      blobKey: CacheBlob.keyOf(
        resourceId: resourceId,
        resourceOldId: resourceOldId,
        url: url,
      ),
      resourceId: resourceId,
      resourceOldId: resourceOldId,
      resourceName: r.resourceName ?? '资源${r.resourceNo ?? ''}',
      resourceType: r.type.value,
      resourceSuffix: r.resourceSuffix,
      url: url,
      goodsId: data.goodsId,
      goodsName: data.goodsName ?? '',
      goodsImage: data.goodsImage ?? '',
      isliCode: isliCode ?? data.source?.sourceIdentifier ?? '',
      versionCode: data.versionCode?.toString(),
      resourceIndex: resourceIndex,
      status: CacheStatus.pending.value,
      progress: 0,
      permission: 1, // 已通过 isSourceAccessible 校验
      accessCount: 0,
    );
  }

  // ==================== 下载队列 ====================

  /// 串行下载队列：按顺序取待缓存任务下载
  ///
  /// 队列中的记录都属于当前账号；账号切换后旧记录已不在 [_records] 中。
  Future<void> _pumpQueue() async {
    if (_downloading) return;
    _downloading = true;
    try {
      while (true) {
        CacheRecord? next;
        for (final CacheRecord r in _records) {
          if (r.status == CacheStatus.pending.value) {
            next = r;
            break;
          }
        }
        if (next == null) return;
        // 记录不属于当前账号（切换瞬间的残留）→ 停止，等待新账号同步
        if (next.accountId != _accountId) return;
        final bool keepGoing = await _download(next);
        if (!keepGoing) return; // 暂停：不自动继续，等待用户恢复
      }
    } finally {
      _downloading = false;
      // 占用下载位期间发生过账号切换：释放后重新调度新账号队列
      if (_pendingRequeue) {
        _pendingRequeue = false;
        unawaited(_pumpQueue());
      }
    }
  }

  /// 下载单个记录，返回是否继续队列（暂停时返回 false）
  Future<bool> _download(CacheRecord record) async {
    record.status = CacheStatus.downloading.value;
    record.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _db.update(record);
    notifyListeners();

    // HLS(m3u8) 与普通直链的落地方式完全不同，需要分流处理
    final bool hls = await _shouldUseHls(record);
    if (!hls) {
      // 直链不支持断点续传，进度从 0 重新开始
      record.progress = 0;
      await _db.update(record);
      notifyListeners();
    } else {
      print('HLS缓存开始: ${record.resourceName} ${record.url}');
    }
    return hls ? _downloadHls(record) : _downloadFile(record);
  }

  /// 是否为 HLS 流（m3u8 需要下载播放列表 + 全部分片，属于多文件缓存）
  ///
  /// 1. 地址/后缀明确是 m3u8 → 直接判定
  /// 2. 中断续传时本地已是 m3u8 入口 → 保持 HLS 方式，避免按整文件重复下载
  /// 3. 音视频资源且地址无可用后缀（CDN 签名地址常见）→ 探测内容类型判断
  Future<bool> _shouldUseHls(CacheRecord record) async {
    if (record.isHlsSource || record.isHlsLocal) return true;

    final bool media = record.resourceType == ResourceType.video.value ||
        record.resourceType == ResourceType.audio.value;
    if (!media || _hasKnownExtension(record.url)) return false;

    final bool hls = await HlsDownloader.probe(_dio, record.url);
    if (hls) print('探测到HLS流: ${record.url}');
    return hls;
  }

  /// 地址是否带已知（非 HLS）后缀，用于决定是否需要内容探测
  static bool _hasKnownExtension(String url) {
    final String path = Uri.tryParse(url)?.path ?? url;
    final String name = path.toLowerCase().split('/').last;
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return false;
    const Set<String> known = <String>{
      '.mp4',
      '.mov',
      '.m4v',
      '.avi',
      '.mkv',
      '.flv',
      '.webm',
      '.3gp',
      '.ts',
      '.mp3',
      '.m4a',
      '.aac',
      '.wav',
      '.flac',
      '.ogg',
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
      '.html',
      '.htm',
      '.pdf',
      '.txt',
      '.json',
      '.glb',
      '.gltf',
      '.obj',
      '.zip',
    };
    return known.any(name.endsWith);
  }

  /// 普通直链下载（单文件）
  Future<bool> _downloadFile(CacheRecord record) async {
    final String dir = await _cacheDir();
    final String savePath = '$dir/${_cacheFileName(record)}';
    final CancelToken cancelToken = CancelToken();
    _currentCancelToken = cancelToken;

    try {
      await _dio.download(
        record.url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (int received, int total) {
          if (total <= 0) return;
          record.progress = received / total;
          record.updatedAt = DateTime.now().millisecondsSinceEpoch;
          // 首次获知文件总大小：写入共享层，缓存列表据此展示（暂停/失败后仍可见）
          if (record.fileSize != total) {
            unawaited(_saveBlobSize(record, total));
          }
          notifyListeners();
        },
      );
      // 下载完成：文件本体写入共享层，记录只保存 blobKey 与账号元数据
      record.status = CacheStatus.completed.value;
      record.progress = 1;
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _putBlob(
        key: _cacheKey(record),
        url: record.url,
        localPath: CachePaths.toStored(savePath),
        fileSize: await File(savePath).length(),
        resourceType: record.resourceType,
        isHls: false,
        versionCode: record.versionCode,
      );
      await _db.update(record);
      notifyListeners();
      return true;
    } catch (e) {
      return _handleDownloadError(record, cancelToken, e);
    } finally {
      _currentCancelToken = null;
    }
  }

  /// HLS(m3u8) 下载：整条流落地到独立目录，支持暂停续传
  ///
  /// - 目录：cache_resources/{key}/，入口 index.m3u8，分片/密钥同目录
  /// - 暂停：已完成分片保留，恢复后跳过已下载分片继续
  /// - 失败：保留已完成分片，重试时继续复用
  Future<bool> _downloadHls(CacheRecord record) async {
    final String root = await CachePaths.root();
    final String blobKey = _cacheKey(record);
    final Directory dir = Directory('$root/$blobKey');

    // 先登记共享文件本体（含入口路径）：HLS 是多文件缓存，
    // 暂停/失败后可整目录清理，其它账号再次下载时也能续传复用同一目录
    record.blobKey = blobKey;
    record.localPath =
        CachePaths.toStored('${dir.path}/${HlsDownloader.entryName}');
    record.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _putBlob(
      key: blobKey,
      url: record.url,
      localPath: record.localPath,
      resourceType: record.resourceType,
      isHls: true,
      versionCode: record.versionCode,
    );
    await _db.update(record);

    final CancelToken cancelToken = CancelToken();
    _currentCancelToken = cancelToken;

    try {
      final HlsDownloadResult result = await HlsDownloader(dio: _dio).download(
        url: record.url,
        dir: dir,
        cancelToken: cancelToken,
        onProgress: (double progress, int bytes) {
          record.progress = progress;
          // 已下载分片字节数（内存态，暂停/失败时落库，完成后为总大小）
          record.fileSize = bytes;
          record.updatedAt = DateTime.now().millisecondsSinceEpoch;
          notifyListeners();
        },
      );
      record.status = CacheStatus.completed.value;
      record.progress = 1;
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      final CacheBlob blob = await _putBlob(
        key: blobKey,
        url: record.url,
        localPath: CachePaths.toStored(result.entryPath),
        fileSize: result.totalBytes,
        resourceType: record.resourceType,
        isHls: true,
        versionCode: record.versionCode,
      );
      record.blobKey = blob.key;
      record.localPath = blob.localPath;
      record.fileSize = blob.fileSize;
      await _db.update(record);
      notifyListeners();
      print('HLS缓存完成: ${record.resourceName} '
          '分片${result.segmentCount} 续传${result.resumedCount} '
          '大小${result.totalBytes}');
      return true;
    } catch (e) {
      return _handleDownloadError(record, cancelToken, e);
    } finally {
      _currentCancelToken = null;
    }
  }

  /// 写入/更新共享文件本体索引（账号无关），供所有账号复用
  Future<CacheBlob> _putBlob({
    required String key,
    required String url,
    String? localPath,
    int? fileSize,
    required int resourceType,
    required bool isHls,
    String? versionCode,
  }) async {
    final CacheBlob blob = (_blobs[key] ?? CacheBlob(key: key)).copyWith(
      url: url,
      localPath: localPath,
      fileSize: fileSize,
      resourceType: resourceType,
      isHls: isHls,
      versionCode: versionCode,
    );
    _blobs[key] = blob;
    await _db.upsertBlob(blob);
    return blob;
  }

  /// 记录文件大小到共享层（缓存列表据此展示；下载中也可展示已知大小）
  Future<void> _saveBlobSize(CacheRecord record, int size) async {
    record.fileSize = size;
    try {
      await _putBlob(
        key: _cacheKey(record),
        url: record.url,
        localPath: record.localPath,
        fileSize: size,
        resourceType: record.resourceType,
        isHls: record.isHlsLocal,
        versionCode: record.versionCode,
      );
    } catch (e) {
      print('记录缓存大小失败: $e');
    }
  }

  /// 下载异常统一处理：取消按暂停（不回退 HLS 已下载分片），其余标记失败
  Future<bool> _handleDownloadError(
      CacheRecord record, CancelToken cancelToken, Object e) async {
    // 暂停/失败时保留已下载大小，缓存列表仍可展示（HLS 为已下载分片合计）
    if (record.fileSize != null && record.fileSize! > 0) {
      await _saveBlobSize(record, record.fileSize!);
    }
    if (cancelToken.isCancelled) {
      // 取消（暂停）不算失败，回到待缓存，且不自动继续队列
      record.status = CacheStatus.pending.value;
      if (!record.isHlsLocal) record.progress = 0;
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _db.update(record);
      notifyListeners();
      return false;
    }
    // 下载失败：标记失败，继续下一个待缓存任务
    record.status = CacheStatus.failed.value;
    record.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _db.update(record);
    notifyListeners();
    print('缓存失败: ${record.url} $e');
    return true;
  }

  // ==================== 操作 ====================

  /// 暂停（仅对缓存中任务生效，回到待缓存）
  Future<void> pause(int id) async {
    final CacheRecord? rec = _find(id);
    if (rec == null) return;
    // 仅当该记录正在下载时取消当前下载
    if (rec.status == CacheStatus.downloading.value) {
      _currentCancelToken?.cancel();
    }
    rec.status = CacheStatus.pending.value;
    // HLS 已下载分片会保留，进度不回退，恢复后断点续传
    if (!rec.isHlsLocal) rec.progress = 0;
    rec.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _db.update(rec);
    notifyListeners();
  }

  /// 恢复（待缓存/失败 → 开始下载）
  Future<void> resume(int id) async {
    final CacheRecord? rec = _find(id);
    if (rec == null) return;
    if (rec.status == CacheStatus.completed.value) return;
    rec.status = CacheStatus.pending.value;
    if (!rec.isHlsLocal) rec.progress = 0;
    rec.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _db.update(rec);
    notifyListeners();
    await _pumpQueue();
  }

  /// 失败重试
  Future<void> retry(int id) => resume(id);

  /// 删除该账号的离线记录；文件本体按**跨账号引用计数**决定是否真正回收
  ///
  /// - 仅删除当前账号的元数据（权限、离线状态、访问记录）
  /// - 若其它账号仍引用同一文件本体，则保留本地文件，避免影响对方离线播放
  Future<void> removeCache(int id) async {
    final CacheRecord? rec = _find(id);
    if (rec == null) return;
    // 正在下载则取消
    if (rec.status == CacheStatus.downloading.value) {
      _currentCancelToken?.cancel();
    }
    final String blobKey =
        rec.blobKey.isNotEmpty ? rec.blobKey : _cacheKey(rec);

    await _db.delete(id);
    _records.removeWhere((r) => r.id == id);

    // 该文件本体是否仍被其它账号的记录引用
    final int refs = await _db.refCountOfBlob(blobKey);
    if (refs <= 0) {
      await _deleteBlobFiles(rec);
      await _db.deleteBlob(blobKey);
      _blobs.remove(blobKey);
    }
    notifyListeners();
  }

  /// 删除文件本体（HLS 为「播放列表 + 分片」多文件，需整目录递归删除）
  Future<void> _deleteBlobFiles(CacheRecord rec) async {
    final String? abs = CachePaths.resolve(rec.localPath);
    if (abs == null || abs.isEmpty) return;
    try {
      if (rec.isHlsLocal || abs.toLowerCase().endsWith('.m3u8')) {
        final Directory dir = Directory(abs.substring(0, abs.lastIndexOf('/')));
        if (await dir.exists()) await dir.delete(recursive: true);
      } else {
        final File file = File(abs);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      print('删除缓存文件失败: $e');
    }
  }

  /// 删除某出版物的全部缓存
  Future<void> removeByGoods(String goodsId) async {
    final List<CacheRecord> goodsRecords =
        _records.where((r) => r.goodsId == goodsId).toList();
    for (final CacheRecord rec in goodsRecords) {
      await removeCache(rec.id!);
    }
  }

  /// 继续所有未完成任务
  Future<void> continueUnfinished() async {
    await _pumpQueue();
  }

  CacheRecord? _find(int id) {
    for (final CacheRecord rec in _records) {
      if (rec.id == id) return rec;
    }
    return null;
  }

  // ==================== 移动网络确认 ====================

  Future<bool> _isCellularConfirmed() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? last = prefs.getInt(_kCellularConfirmKey);
      if (last == null) return false;
      return DateTime.now().millisecondsSinceEpoch - last <
          _cellularConfirmValidity.inMilliseconds;
    } catch (e) {
      return false;
    }
  }

  Future<void> _setCellularConfirmed() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _kCellularConfirmKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('记录移动网络确认时间失败: $e');
    }
  }

  // ==================== 生命周期 ====================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 挂起恢复后询问是否继续未完成任务
      _askContinueUnfinished();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 进入后台：暂停当前下载，避免后台消耗流量；下次恢复时重新询问
      _currentCancelToken?.cancel();
      _askedContinue = false;
    }
  }

  /// 询问是否继续未完成任务（冷启动/挂起恢复）
  Future<void> _askContinueUnfinished() async {
    if (!hasUnfinished || _askedContinue) return;
    _askedContinue = true;
    final BuildContext? ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    final bool? ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('继续缓存', style: TextStyle(fontSize: 16)),
        content: const Text('检测到未完成的缓存任务，是否继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _pumpQueue();
    }
  }

  // ==================== 工具 ====================

  Future<String> _cacheDir() => CachePaths.root();

  /// 文件本体标识：优先用资源 ID，缺失时用 URL 哈希；统一做文件系统安全化。
  ///
  /// 注意**不含账号**：同一资源在所有账号下指向同一份文件，因此可跨账号复用。
  String _cacheKey(CacheRecord record) {
    if (record.blobKey.isNotEmpty) return record.blobKey;
    return CacheBlob.keyOf(
      resourceId: record.resourceId,
      resourceOldId: record.resourceOldId,
      url: record.url,
    );
  }

  /// 普通资源文件名：主干 + 扩展名
  String _cacheFileName(CacheRecord record) {
    return '${_cacheKey(record)}${_extensionOf(record)}';
  }

  /// 扩展名：URL 路径后缀优先（已剔除签名 query），其次 resourceSuffix
  String _extensionOf(CacheRecord record) {
    final String path = Uri.tryParse(record.url)?.path ?? record.url;
    final String name = path.split('/').last;
    final int dot = name.lastIndexOf('.');
    if (dot > 0) {
      final String ext = name.substring(dot);
      if (RegExp(r'^\.[A-Za-z0-9]{1,5}$').hasMatch(ext)) {
        return ext.toLowerCase();
      }
    }
    final String suffix = (record.resourceSuffix ?? '').trim();
    if (suffix.isEmpty) return '';
    return suffix.startsWith('.')
        ? suffix.toLowerCase()
        : '.${suffix.toLowerCase()}';
  }

  /// http → https 并去掉端口；同时去除反引号与首尾空白
  static String _httpsUrl(String? raw) {
    String url = cleanUrl(raw).trim();
    if (url.toLowerCase().startsWith('http://')) {
      url = url.replaceFirst(
          RegExp(r'^http://', caseSensitive: false), 'https://');
      url = url.replaceFirst(
          RegExp(r'^(https://[^/?#]+):\d+(?=/|$|#|\?)'), r'$1');
    }
    return url;
  }
}
