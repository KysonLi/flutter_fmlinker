import 'dart:async';
import 'dart:io';

import 'package:fmlink/cache/cache_paths.dart';

/// 本地媒体服务：把缓存目录通过 `127.0.0.1` 回环 HTTP 暴露出去
///
/// 为什么需要它：
/// 各端播放器对「本地文件 + HLS」支持不一致。以 OHOS 端 video_player 为例，
/// `file://` 会被转成 `fd://`（见插件 VideoPlayer.getIUri），播放列表因此失去基准地址，
/// 相对路径的分片/密钥无法解析；Android/iOS 对本地 m3u8 也存在兼容差异。
/// 改用 `http://127.0.0.1:<port>/media/...` 后，播放器按标准 HLS 流程加载，
/// 分片、`#EXT-X-KEY`、`#EXT-X-MAP` 都能正常解析。
///
/// 安全性：
/// - 仅监听回环地址（不对外暴露），且不依赖外网，飞行模式下同样可用
/// - 只允许访问缓存根目录内的文件，并做路径穿越校验
/// - 只放行播放所需的文件后缀白名单
class LocalMediaServer {
  LocalMediaServer._();

  static final LocalMediaServer instance = LocalMediaServer._();

  /// URL 前缀：`http://127.0.0.1:<port>/media/<缓存根目录下的相对路径>`
  static const String pathPrefix = '/media/';

  /// 允许访问的文件后缀（播放列表/分片/密钥/图片/文本）
  static const Set<String> _allowedExtensions = <String>{
    '.m3u8',
    '.m3u',
    '.ts',
    '.m4s',
    '.mp4',
    '.m4v',
    '.m4a',
    '.aac',
    '.mp3',
    '.cmfv',
    '.cmfa',
    '.cmft',
    '.vtt',
    '.key',
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.txt',
    '.json',
  };

  static const Map<String, String> _contentTypes = <String, String>{
    '.m3u8': 'application/vnd.apple.mpegurl',
    '.m3u': 'application/vnd.apple.mpegurl',
    '.ts': 'video/mp2t',
    '.m4s': 'video/mp4',
    '.mp4': 'video/mp4',
    '.m4v': 'video/mp4',
    '.m4a': 'audio/mp4',
    '.aac': 'audio/aac',
    '.mp3': 'audio/mpeg',
    '.cmfv': 'video/mp4',
    '.cmfa': 'audio/mp4',
    '.cmft': 'application/octet-stream',
    '.vtt': 'text/vtt',
    '.key': 'application/octet-stream',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.gif': 'image/gif',
    '.txt': 'text/plain; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
  };

  HttpServer? _server;
  Future<String?>? _starting;

  bool get isRunning => _server != null;

  /// 确保服务已启动，返回基地址（如 `http://127.0.0.1:53211`）；失败返回 null
  Future<String?> ensureStarted() async {
    final HttpServer? running = _server;
    if (running != null) return _baseUrl(running);
    // 并发调用共用同一次启动过程
    return _starting ??= _start();
  }

  Future<String?> _start() async {
    try {
      // 端口交由系统分配，避免与其它服务冲突
      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(_handle, onError: (Object e) => print('本地媒体服务异常: $e'));
      _server = server;
      print('本地媒体服务已启动: ${_baseUrl(server)}');
      return _baseUrl(server);
    } catch (e) {
      print('本地媒体服务启动失败: $e');
      return null;
    } finally {
      _starting = null;
    }
  }

  String _baseUrl(HttpServer server) =>
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}';

  /// 本地绝对路径 → 回环播放地址（不在缓存目录内或后缀不允许时返回 null）
  Future<String?> urlForLocalPath(String absolutePath) async {
    final String base = (await ensureStarted()) ?? '';
    if (base.isEmpty) return null;
    final String? relative = await _relativeOf(absolutePath);
    if (relative == null) return null;
    // 逐段编码：保留路径分隔符，避免文件名中的特殊字符破坏 URL
    final String encoded =
        relative.split('/').map(Uri.encodeComponent).join('/');
    return '$base$pathPrefix$encoded';
  }

  /// 绝对路径 → 相对缓存根目录的路径（带安全校验）
  Future<String?> _relativeOf(String absolutePath) async {
    final String root = await CachePaths.root();
    final String normalized = absolutePath.replaceAll('\\', '/');
    final String prefix = '$root/';
    if (!normalized.startsWith(prefix)) return null;
    final String relative = normalized.substring(prefix.length);
    if (relative.isEmpty || relative.contains('..')) return null;
    if (!_allowedExtensions.contains(_extensionOf(relative))) return null;
    return relative;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        await _fail(request, HttpStatus.methodNotAllowed);
        return;
      }
      final String path = request.uri.path;
      if (!path.startsWith(pathPrefix)) {
        await _fail(request, HttpStatus.notFound);
        return;
      }
      // Uri.path 保留百分号编码，这里解码回真实相对路径
      final String relative =
          Uri.decodeComponent(path.substring(pathPrefix.length));
      final File? file = await _resolve(relative);
      if (file == null) {
        await _fail(request, HttpStatus.notFound);
        return;
      }
      await _serve(request, file);
    } catch (e) {
      print('本地媒体请求处理失败: $e');
      try {
        await _fail(request, HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  /// 校验并解析请求路径，确保落在缓存目录内
  Future<File?> _resolve(String relative) async {
    if (relative.isEmpty || relative.contains('..')) return null;
    final String root = await CachePaths.root();
    final File file = File('$root/$relative');
    final String path = file.absolute.path;
    if (!path.startsWith('$root/')) return null;
    if (!_allowedExtensions.contains(_extensionOf(path))) return null;
    if (!await file.exists()) return null;
    return file;
  }

  Future<void> _serve(HttpRequest request, File file) async {
    final String contentType =
        _contentTypes[_extensionOf(file.path)] ?? 'application/octet-stream';
    final int length = await file.length();
    final HttpResponse response = request.response;
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    // 播放列表始终读最新内容，分片可长缓存
    response.headers.set(
      HttpHeaders.cacheControlHeader,
      _extensionOf(file.path).startsWith('.m3u')
          ? 'no-store'
          : 'max-age=31536000',
    );

    final List<int>? range = _parseRange(request, length);
    if (range == null) {
      response.statusCode = HttpStatus.ok;
      response.headers.set(HttpHeaders.contentLengthHeader, length.toString());
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      await response.addStream(file.openRead());
      await response.close();
      return;
    }

    final int start = range[0];
    final int end = range[1];
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.contentLengthHeader, '${end - start + 1}');
    response.headers
        .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    await response.addStream(file.openRead(start, end + 1));
    await response.close();
  }

  /// 简单单段 Range 解析：合法返回 [start, endInclusive]，非法/未请求返回 null
  List<int>? _parseRange(HttpRequest request, int length) {
    final String? header = request.headers.value(HttpHeaders.rangeHeader);
    if (header == null || !header.startsWith('bytes=')) return null;
    final String spec = header.substring('bytes='.length).split(',').first;
    final List<String> parts = spec.split('-');
    if (parts.length != 2) return null;
    final int? start = parts[0].isEmpty ? null : int.tryParse(parts[0].trim());
    final int? end = parts[1].isEmpty ? null : int.tryParse(parts[1].trim());
    if (start == null && end == null) return null;
    if (start == null) {
      // bytes=-N：最后 N 字节
      final int from = length - end!;
      if (from < 0) return <int>[0, length - 1];
      return <int>[from, length - 1];
    }
    if (start >= length) return null;
    final int last = end == null || end >= length ? length - 1 : end;
    return <int>[start, last];
  }

  Future<void> _fail(HttpRequest request, int status) async {
    request.response.statusCode = status;
    await request.response.close();
  }

  String _extensionOf(String path) {
    final String name = path.split('/').last.toLowerCase();
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }

  /// 停止服务（页面退出/释放资源时可选调用）
  Future<void> stop() async {
    final HttpServer? server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
