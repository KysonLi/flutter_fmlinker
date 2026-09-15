import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// HLS(m3u8) 离线下载结果
class HlsDownloadResult {
  const HlsDownloadResult({
    required this.entryPath,
    required this.totalBytes,
    required this.segmentCount,
    required this.resumedCount,
  });

  /// 本地播放入口（index.m3u8）绝对路径
  final String entryPath;

  /// 分片 + 密钥 + 初始化段总字节数
  final int totalBytes;

  /// 分片总数
  final int segmentCount;

  /// 续传命中（已存在被跳过）的分片数
  final int resumedCount;
}

/// HLS 下载异常
class HlsDownloadException implements Exception {
  HlsDownloadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'HlsDownloadException: $message${cause == null ? '' : ' ($cause)'}';
}

/// 待下载资产（分片 / 加密密钥 / 初始化段）
class _HlsAsset {
  _HlsAsset({
    required this.url,
    required this.name,
    this.byteRange,
    this.isKey = false,
  });

  final String url;

  /// 本地文件名（相对资源目录）
  final String name;

  /// `#EXT-X-BYTERANGE` 声明的 `长度@偏移`，为空表示整段下载
  final String? byteRange;

  final bool isKey;
}

/// HLS(m3u8) 离线下载器
///
/// m3u8 与普通直链不同：它是「播放列表 + N 个分片」的组合，只下载列表本身无法离线播放，
/// 因此必须特殊处理：
/// - 主列表（`#EXT-X-STREAM-INF`）自动挑选码率最高的一路，支持嵌套主列表
/// - 分片地址按所属播放列表的 URL 做相对解析（相对路径、带鉴权 query 的地址均可）
/// - `#EXT-X-KEY`（AES-128 密钥）、`#EXT-X-MAP`（fMP4 初始化段）一并下载并改写为本地地址
/// - `#EXT-X-BYTERANGE` 按字节区间抓取，落地为独立分片后去掉该标签
/// - 分片统一重命名为 `seg_00000.ts` 形式，避免签名 query / 超长文件名导致写盘失败
/// - 并发下载 + 断点续传（已完成分片直接跳过，暂停后可继续）
/// - 全部完成后写出 `index.m3u8`，播放器用 file:// 打开即可离线播放
class HlsDownloader {
  HlsDownloader({required Dio dio, this.concurrency = 4, this.retry = 2})
      : _dio = dio;

  final Dio _dio;

  /// 并发分片数
  final int concurrency;

  /// 单分片失败重试次数
  final int retry;

  /// 播放入口文件名
  static const String entryName = 'index.m3u8';

  /// 主列表嵌套最大层数
  static const int _maxMasterDepth = 3;

  /// 进度回调节流间隔
  static const Duration _progressInterval = Duration(milliseconds: 200);

  /// URL 是否看起来是 HLS（后缀判定，无法覆盖无后缀的 CDN 地址）
  static bool isHlsUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final String lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.m3u8') || lower.endsWith('.m3u');
  }

  /// 探测地址是否为 HLS（用于无后缀的资源地址，仅当后缀无法判定时调用）
  static Future<bool> probe(Dio dio, String url) async {
    try {
      final Response<dynamic> res = await dio.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: const <String, dynamic>{'Accept': '*/*'},
        ),
      );
      final String body = res.data?.toString() ?? '';
      if (body.contains('#EXTM3U')) return true;
      final String ct = res.headers.value('content-type')?.toLowerCase() ?? '';
      return ct.contains('mpegurl');
    } catch (e) {
      return false;
    }
  }

  /// 下载整条 HLS 流到 [dir]，返回本地播放入口
  ///
  /// [onProgress] 进度（0~1，按已下载字节估算）；[bytes] 为已落盘字节数（全程递增）
  /// [cancelToken] 取消（暂停/切换网络）后抛出 DioException，调用方按暂停处理
  Future<HlsDownloadResult> download({
    required String url,
    required Directory dir,
    CancelToken? cancelToken,
    void Function(double progress, int bytes)? onProgress,
  }) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // 上次未完成会残留旧入口，先清理避免误判为已完成
    final File entry = File('${dir.path}/$entryName');
    if (await entry.exists()) await entry.delete();

    // 1. 拉取播放列表，主列表则按码率挑选一路（支持嵌套）
    Uri baseUri = Uri.parse(url);
    String content = await _fetchPlaylist(url, cancelToken);
    for (int depth = 0; depth < _maxMasterDepth; depth++) {
      if (!_isMasterPlaylist(content)) break;
      final Uri? variant = _pickVariant(content, baseUri);
      if (variant == null) break;
      baseUri = variant;
      content = await _fetchPlaylist(baseUri.toString(), cancelToken);
    }

    // 2. 解析媒体列表：下载清单 + 重写为本地相对地址
    final _ParseResult parsed = _parseMediaPlaylist(content, baseUri);
    if (parsed.assets.isEmpty) {
      throw HlsDownloadException('播放列表没有可用分片：$url');
    }

    // 3. 并发下载 + 断点续传
    final _Tracker tracker = _Tracker(total: parsed.segmentCount);
    final Directory assetDir = dir;
    for (final _HlsAsset asset in parsed.assets) {
      final File f = File('${assetDir.path}/${asset.name}');
      if (await f.exists()) {
        final int len = await f.length();
        if (len > 0) {
          tracker.markResumed(len, isSegment: !asset.isKey);
          continue;
        }
      }
      tracker.pending.add(asset);
    }
    onProgress?.call(tracker.progress, tracker.completedBytes);

    final List<_HlsAsset> queue = tracker.pending;
    int cursor = 0;
    Object? firstError;

    Future<void> worker() async {
      while (true) {
        if (firstError != null || (cancelToken?.isCancelled ?? false)) return;
        final int idx = cursor++;
        if (idx >= queue.length) return;
        final _HlsAsset asset = queue[idx];
        try {
          await _fetchAsset(asset, assetDir, cancelToken, tracker,
              (int received) {
            tracker.inflight[asset.name] = received;
            _reportThrottled(tracker, onProgress);
          });
          tracker.markDone(
            await File('${assetDir.path}/${asset.name}').length(),
            isSegment: !asset.isKey,
          );
          onProgress?.call(tracker.progress, tracker.completedBytes);
        } catch (e) {
          firstError ??= e;
          return;
        }
      }
    }

    final int workers = concurrency < 1
        ? 1
        : (queue.length < concurrency ? queue.length : concurrency);
    await Future.wait(
      List<Future<void>>.generate(workers, (_) => Future<void>(worker)),
    );

    if (cancelToken?.isCancelled ?? false) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        type: DioExceptionType.cancel,
        error: 'cancelled',
      );
    }
    if (firstError != null) {
      if (firstError is HlsDownloadException) throw firstError!;
      throw HlsDownloadException('分片下载失败：$url', cause: firstError);
    }

    // 4. 写出本地播放列表
    await entry.writeAsString(parsed.playlist, flush: true);

    return HlsDownloadResult(
      entryPath: entry.path,
      totalBytes: tracker.completedBytes,
      segmentCount: parsed.segmentCount,
      resumedCount: tracker.resumed,
    );
  }

  // ==================== 播放列表 ====================

  Future<String> _fetchPlaylist(String url, CancelToken? cancelToken) async {
    try {
      final Response<dynamic> res = await _dio.get<dynamic>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          headers: const <String, dynamic>{'Accept': '*/*'},
        ),
      );
      String text = res.data?.toString() ?? '';
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      if (text.trim().isEmpty) {
        throw HlsDownloadException('播放列表内容为空：$url');
      }
      if (!text.contains('#EXTM3U')) {
        throw HlsDownloadException('播放列表格式非法（缺少 #EXTM3U）：$url');
      }
      return text;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw HlsDownloadException('播放列表拉取失败：$url', cause: e);
    }
  }

  bool _isMasterPlaylist(String content) =>
      content.contains('#EXT-X-STREAM-INF');

  /// 从主列表中挑选码率最高的一路（`#EXT-X-I-FRAME-STREAM-INF` 属于快进预览，不参与）
  Uri? _pickVariant(String content, Uri baseUri) {
    String? bestUri;
    int bestBandwidth = -1;
    final List<String> lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final Map<String, String> attrs = _parseAttributes(line);
      final int bandwidth = int.tryParse(attrs['BANDWIDTH'] ?? '') ?? 0;
      // URI 在标签的下一行
      for (int j = i + 1; j < lines.length; j++) {
        final String next = lines[j].trim();
        if (next.isEmpty) continue;
        if (next.startsWith('#')) break;
        if (bandwidth > bestBandwidth) {
          bestBandwidth = bandwidth;
          bestUri = next;
        }
        break;
      }
    }
    if (bestUri == null) return null;
    return _resolve(baseUri, bestUri);
  }

  /// 解析媒体列表：输出本地播放列表文本 + 待下载资产清单
  _ParseResult _parseMediaPlaylist(String content, Uri baseUri) {
    final List<String> out = <String>[];
    final List<_HlsAsset> assets = <_HlsAsset>[];
    // 同一密钥地址只下载一次，多处 #EXT-X-KEY 共用本地文件
    final Map<String, String> keyCache = <String, String>{};
    final Set<String> addedKeys = <String>{};

    int segIndex = 0;
    int initIndex = 0;
    int keyIndex = 0;
    int segmentCount = 0;
    String? pendingRange;

    for (final String rawLine in content.split('\n')) {
      final String line = rawLine.trimRight();
      final String trimmed = line.trim();

      if (trimmed.isEmpty) {
        out.add(line);
        continue;
      }

      // 分片地址（非 # 开头）
      if (!trimmed.startsWith('#')) {
        final Uri? resolved = _resolve(baseUri, trimmed);
        if (resolved == null) {
          out.add(line);
          continue;
        }
        final String localName =
            'seg_${segIndex.toString().padLeft(5, '0')}${_extOf(resolved, '.ts')}';
        assets.add(_HlsAsset(
          url: resolved.toString(),
          name: localName,
          byteRange: pendingRange,
        ));
        pendingRange = null;
        segIndex++;
        segmentCount++;
        out.add(localName);
        continue;
      }

      if (trimmed.startsWith('#EXT-X-KEY')) {
        final Map<String, String> attrs = _parseAttributes(trimmed);
        final String method = (attrs['METHOD'] ?? '').toUpperCase();
        final String keyUri = attrs['URI'] ?? '';
        if (method == 'NONE' || keyUri.isEmpty) {
          out.add(line);
          continue;
        }
        final Uri? resolved = _resolve(baseUri, keyUri);
        if (resolved == null) {
          out.add(line);
          continue;
        }
        final String key = resolved.toString();
        final String localName =
            keyCache[key] ??= 'key_${keyIndex++}${_extOf(resolved, '.key')}';
        if (addedKeys.add(key)) {
          assets.add(_HlsAsset(url: key, name: localName, isKey: true));
        }
        out.add(line.replaceFirst(
            RegExp(r'URI\s*=\s*"[^"]*"'), 'URI="$localName"'));
        continue;
      }

      if (trimmed.startsWith('#EXT-X-MAP')) {
        final Map<String, String> attrs = _parseAttributes(trimmed);
        final String mapUri = attrs['URI'] ?? '';
        final Uri? resolved = _resolve(baseUri, mapUri);
        if (resolved == null) {
          out.add(line);
          continue;
        }
        final String localName =
            'init_${initIndex.toString().padLeft(3, '0')}${_extOf(resolved, '.mp4')}';
        initIndex++;
        assets.add(_HlsAsset(url: resolved.toString(), name: localName));
        // 初始化段可能只覆盖部分字节区间，本地已是完整文件，去掉 BYTERANGE
        out.add(line
            .replaceFirst(RegExp(r'URI\s*=\s*"[^"]*"'), 'URI="$localName"')
            .replaceFirst(RegExp(r',?BYTERANGE\s*=\s*"[^"]*"'), '')
            .replaceFirst(RegExp(r',?BYTERANGE\s*=\s*[^,]+'), ''));
        continue;
      }

      if (trimmed.startsWith('#EXT-X-BYTERANGE')) {
        // 该标签作用于紧随其后的分片；下载时会按区间抓取并落地为完整文件，故不再输出
        pendingRange = trimmed.substring(trimmed.indexOf(':') + 1).trim();
        continue;
      }

      // 其它标签原样保留（#EXTINF / #EXT-X-DISCONTINUITY / #EXT-X-ENDLIST ...）
      out.add(line);
    }

    final String playlist = '${out.join('\n').trimRight()}\n';
    return _ParseResult(
      playlist: playlist,
      assets: assets,
      segmentCount: segmentCount,
    );
  }

  // ==================== 分片下载 ====================

  Future<void> _fetchAsset(
    _HlsAsset asset,
    Directory dir,
    CancelToken? cancelToken,
    _Tracker tracker,
    void Function(int received) onReceived,
  ) async {
    final File target = File('${dir.path}/${asset.name}');
    final File part = File('${target.path}.part');
    Object? lastError;

    for (int attempt = 0; attempt <= retry; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException(
          requestOptions: RequestOptions(path: asset.url),
          type: DioExceptionType.cancel,
          error: 'cancelled',
        );
      }
      try {
        if (await part.exists()) await part.delete();
        await _dio.download(
          asset.url,
          part.path,
          cancelToken: cancelToken,
          options: Options(
            headers: <String, dynamic>{
              'Accept': '*/*',
              if (asset.byteRange != null)
                'Range': _rangeHeader(asset.byteRange!),
            },
          ),
          onReceiveProgress: (int received, int total) {
            if (received > 0) onReceived(received);
          },
        );
        final int len = await part.length();
        if (len <= 0) {
          throw HlsDownloadException('分片内容为空：${asset.url}');
        }
        if (await target.exists()) await target.delete();
        await part.rename(target.path);
        tracker.inflight.remove(asset.name);
        return;
      } catch (e) {
        if ((e is DioException && CancelToken.isCancel(e)) ||
            (cancelToken?.isCancelled ?? false)) {
          // 取消：保留已完成分片，交由调用方按暂停处理
          rethrow;
        }
        lastError = e;
        tracker.inflight.remove(asset.name);
        if (attempt < retry) {
          await Future<void>.delayed(
              Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
    }
    throw HlsDownloadException('分片下载失败：${asset.url}', cause: lastError);
  }

  /// `长度@偏移` → HTTP Range 头（`bytes=起点-终点`）
  String _rangeHeader(String spec) {
    final List<String> parts = spec.split('@');
    final int length = int.tryParse(parts[0].trim()) ?? 0;
    final int offset =
        parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
    if (length <= 0) return 'bytes=$offset-';
    return 'bytes=$offset-${offset + length - 1}';
  }

  // ==================== 工具 ====================

  /// 相对地址解析（相对路径 / 根路径 / 绝对地址 / 带鉴权 query 均支持）
  static Uri? _resolve(Uri baseUri, String ref) {
    if (ref.isEmpty) return null;
    try {
      return baseUri.resolve(ref);
    } catch (e) {
      final Uri? direct = Uri.tryParse(ref);
      return direct;
    }
  }

  /// `#EXT-X-KEY:METHOD=AES-128,URI="key.key",IV=0x...` → 属性表
  static Map<String, String> _parseAttributes(String line) {
    final Map<String, String> map = <String, String>{};
    final int idx = line.indexOf(':');
    if (idx < 0) return map;
    final String content = line.substring(idx + 1);
    final RegExp re = RegExp(r'([A-Za-z0-9\-]+)\s*=\s*("[^"]*"|[^,]*)');
    for (final Match m in re.allMatches(content)) {
      String value = m.group(2)?.trim() ?? '';
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      map[m.group(1)!.toUpperCase()] = value;
    }
    return map;
  }

  /// 从地址中取安全扩展名（query 已由 Uri.path 剔除），异常时用兜底值
  static String _extOf(Uri uri, String fallback) {
    final String name = uri.path.split('/').last;
    final int dot = name.lastIndexOf('.');
    if (dot <= 0) return fallback;
    final String ext = name.substring(dot);
    if (!RegExp(r'^\.[A-Za-z0-9]{1,4}$').hasMatch(ext)) return fallback;
    if (ext.toLowerCase() == '.m3u8') return fallback;
    return ext;
  }

  /// 分片下载回调非常高频，按时间片抽样上报，避免刷爆 UI
  void _reportThrottled(
    _Tracker tracker,
    void Function(double progress, int bytes)? onProgress,
  ) {
    if (onProgress == null) return;
    final DateTime now = DateTime.now();
    final DateTime? last = _lastReport;
    if (last != null && now.difference(last) < _progressInterval) return;
    _lastReport = now;
    onProgress(tracker.progress, tracker.completedBytes);
  }

  DateTime? _lastReport;
}

class _ParseResult {
  _ParseResult({
    required this.playlist,
    required this.assets,
    required this.segmentCount,
  });

  /// 重写后的本地播放列表文本
  final String playlist;

  /// 待下载资产（分片 + 密钥 + 初始化段）
  final List<_HlsAsset> assets;

  /// 分片数量（不含密钥/初始化段）
  final int segmentCount;
}

/// 进度统计：已下载字节 / 估算总字节
class _Tracker {
  _Tracker({required this.total});

  final int total;
  final List<_HlsAsset> pending = <_HlsAsset>[];
  final Map<String, int> inflight = <String, int>{};

  int completedBytes = 0;
  int completed = 0;
  int resumed = 0;

  void markResumed(int bytes, {required bool isSegment}) {
    if (!isSegment) return;
    completed++;
    resumed++;
    completedBytes += bytes;
  }

  void markDone(int bytes, {required bool isSegment}) {
    if (!isSegment) return;
    completed++;
    completedBytes += bytes;
  }

  double get progress {
    if (total <= 0) return 0;
    final int inflightBytes =
        inflight.values.fold<int>(0, (int sum, int v) => sum + v);
    final double avg = completed > 0 ? completedBytes / completed : 0;
    final double estTotal =
        avg > 0 ? avg * total : (completedBytes + inflightBytes).toDouble();
    if (estTotal <= 0) return completed / total;
    final double p = (completedBytes + inflightBytes) / estTotal;
    return p.clamp(0.0, 1.0);
  }
}
