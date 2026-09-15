import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 缓存存储路径统一管理器
///
/// 目录约定（全部落在 App 私有目录 ApplicationSupportDirectory 下）：
/// - 普通资源（文本/图片/音频/单文件视频）：`cache_resources/{key}{ext}`
/// - HLS(m3u8) 视频：`cache_resources/{key}/index.m3u8` + 分片/密钥同目录
///
/// 存储地址特殊处理说明：
/// 1. 数据库只保存 **相对缓存根目录** 的路径（如 `cache_resources/123/index.m3u8`），
///    iOS 容器 UUID 在 App 升级后会变化、Android 沙盒路径也可能变化，
///    保存绝对路径会导致「明明下载过却播不了」；
/// 2. 读取时统一用 [resolve] 还原成当前容器下的绝对路径，并对历史遗留的绝对路径做兜底重定向；
/// 3. 目录名统一做文件系统安全化（去掉 URL query、非法字符），避免签名地址导致建目录失败。
class CachePaths {
  CachePaths._();

  /// 缓存根目录名
  static const String rootName = 'cache_resources';

  /// HLS 播放入口文件名
  static const String hlsEntryName = 'index.m3u8';

  /// 失败分片的临时后缀
  static const String partSuffix = '.part';

  static String? _supportDir;

  /// 当前 App 私有目录（首次调用会初始化并缓存）
  static Future<String> init() async {
    final String? cached = _supportDir;
    if (cached != null) return cached;
    final Directory dir = await getApplicationSupportDirectory();
    _supportDir = dir.path;
    return _supportDir!;
  }

  /// 当前容器下的缓存根目录（不存在则创建）
  static Future<String> root() async {
    final String base = await init();
    final String path = '$base/$rootName';
    final Directory dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  /// 文件系统安全化的相对片段（去掉 query/非法字符），用于目录名/文件名
  static String safeName(String raw) {
    String name = raw;
    final int q = name.indexOf('?');
    if (q >= 0) name = name.substring(0, q);
    final int h = name.indexOf('#');
    if (h >= 0) name = name.substring(0, h);
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');
    if (name.length > 60) name = name.substring(0, 60);
    return name.isEmpty ? 'file' : name;
  }

  /// 绝对路径 → 库内相对路径（不在缓存根目录下时原样返回）
  static String toStored(String path) {
    final String p = path.replaceAll('\\', '/');
    if (!p.startsWith('/')) return p;
    if (p.startsWith('$rootName/')) return p;
    final String marker = '/$rootName/';
    final int idx = p.lastIndexOf(marker);
    if (idx < 0) return path;
    return p.substring(idx + 1);
  }

  /// 库内路径 → 当前容器下的绝对路径
  ///
  /// - 相对路径：拼当前容器目录
  /// - 绝对路径：存在则直接使用；已失效（容器迁移/换包）则按 `cache_resources/` 之后的部分重拼
  static String? resolve(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    final String p = stored.replaceAll('\\', '/');
    final String? base = _supportDir;

    if (!p.startsWith('/')) {
      if (base == null) return p; // 未初始化：调用方按文件不存在兜底
      return '$base/$p';
    }
    if (_existsSync(p)) return p;

    // 历史/失效绝对路径：按容器无关的相对部分重定向
    final int idx = p.lastIndexOf('/$rootName/');
    if (idx >= 0 && base != null) return '$base/${p.substring(idx + 1)}';
    return p;
  }

  /// 判断库内路径在当前容器下是否存在（文件或目录）
  static bool exists(String? stored) {
    final String? p = resolve(stored);
    if (p == null) return false;
    return _existsSync(p);
  }

  /// 记录对应的资源目录（HLS 为多文件目录）
  ///
  /// 注意：普通资源返回其所在目录（即缓存根目录），删除时不可递归删除该目录。
  static String directoryOf(String? stored) {
    final String? p = resolve(stored);
    if (p == null || !p.contains('/')) return '';
    return p.substring(0, p.lastIndexOf('/'));
  }

  static bool _existsSync(String path) =>
      File(path).existsSync() || Directory(path).existsSync();
}
