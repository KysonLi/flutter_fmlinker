import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';

/// 3D 模型加载异常，[message] 为面向用户展示的中文描述。
class Model3dLoadException implements Exception {
  final String message;

  const Model3dLoadException(this.message);

  @override
  String toString() => message;
}

/// zip 解压后台 isolate 的输入。
class _ExtractInput {
  _ExtractInput(this.zipPath, this.extractDir);
  final String zipPath;
  final String extractDir;
}

/// 在后台 isolate 中完成 zip 解压 + 写盘 + 定位 obj。
///
/// 大 zip 的 CPU 解压（ZipDecoder.decodeBytes）与磁盘写若放在主线程，
/// 会在进入页面的转场动画期间造成卡顿，故整体下沉到 isolate。
String _extractSync(_ExtractInput input) {
  final String extractDirPath = input.extractDir;
  final Archive archive =
      ZipDecoder().decodeBytes(File(input.zipPath).readAsBytesSync());
  for (final ArchiveFile f in archive) {
    if (!f.isFile || f.name.contains('..')) continue; // 跳过目录与路径穿越
    final File out = File('$extractDirPath/${f.name}');
    out
      ..createSync(recursive: true)
      ..writeAsBytesSync(f.content as List<int>);
  }
  final String? obj = _findObjSync(extractDirPath);
  if (obj == null) {
    throw const Model3dLoadException('压缩包内未找到可渲染的 OBJ 文件');
  }
  return obj;
}

/// 同步版查找目录下第一个 .obj 文件（供后台 isolate 使用）。
String? _findObjSync(String dirPath) {
  final List<String> pending = <String>[dirPath];
  while (pending.isNotEmpty) {
    final String dir = pending.removeLast();
    for (final FileSystemEntity entry in Directory(dir).listSync()) {
      if (entry is Directory) {
        pending.add(entry.path);
      } else if (entry.path.toLowerCase().endsWith('.obj')) {
        return entry.path;
      }
    }
  }
  return null;
}

/// 3D 模型资源下载缓存
///
/// 资源地址可能是「直接 .obj」或「.zip 压缩包」（内含 obj / mtl / 贴图）两种形态：
/// - 裸 obj：下载后同步拉取 mtllib 引用的 mtl 与 map_Kd / map_Ka 贴图，平铺到
///   `model3d/<hash>/`，使 flutter_cube 以 `isAsset: false` 相对路径即可解析；
/// - zip：下载后解压到 `model3d/<hash>/extracted/`，递归定位其中的 .obj 并返回。
///
/// 同一 URL 已缓存时直接返回本地 obj 路径，避免重复下载。
class Model3dCache {
  Model3dCache._();

  static final Model3dCache instance = Model3dCache._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));

  /// mtl 文件引用的贴图指令（map_Kd 优先、map_Ka 兜底）。
  static const List<String> _textureDirectives = <String>['map_Kd', 'map_Ka'];

  /// 下载并缓存 3D 模型资源，返回本地 obj 文件路径。
  Future<String> ensureDownloaded(String objUrl) async {
    final Directory dir = await _cacheDirFor(objUrl);
    final String fileName = _fileNameOf(objUrl);
    final String localFile = '${dir.path}/$fileName';
    final bool isArchive = _isArchive(fileName);

    // 已缓存：zip 定位 obj，裸 obj 直接返回
    if (await File(localFile).exists()) {
      return isArchive ? _extract(localFile, dir) : localFile;
    }

    try {
      await _download(objUrl, localFile);

      if (isArchive) {
        // zip：解压并定位其中的 obj（后台 isolate 完成）
        return _extract(localFile, dir);
      }

      // 裸 obj：同步下载引用的 mtl / 贴图
      final List<String> mtlRefs = _directiveValues(localFile, 'mtllib');
      for (final String mtlRef in mtlRefs) {
        final String mtlUrl = _resolve(objUrl, mtlRef);
        final String localMtl = '${dir.path}/${_fileNameOf(mtlUrl)}';
        await _download(mtlUrl, localMtl);

        final Set<String> texRefs = <String>{};
        for (final String directive in _textureDirectives) {
          texRefs.addAll(_directiveValues(localMtl, directive));
        }
        for (final String texRef in texRefs) {
          final String texUrl = _resolve(mtlUrl, texRef);
          await _download(texUrl, '${dir.path}/${_fileNameOf(texUrl)}');
        }
      }
      return localFile;
    } catch (_) {
      // 下载或解压失败时清理半成品，避免下次误判为已缓存
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// 解压 zip 到 `extracted/` 并定位其中的 .obj，已解压过则直接返回。
  ///
  /// 首次解压在后台 isolate 完成（见 [_extractSync]），避免阻塞 UI 线程。
  Future<String> _extract(String zipPath, Directory cacheDir) async {
    final Directory extractDir = Directory('${cacheDir.path}/extracted');
    if (await extractDir.exists()) {
      final String? cached = await _findObj(extractDir.path);
      if (cached != null) return cached;
      await extractDir.delete(recursive: true);
    }
    try {
      return await compute(
          _extractSync, _ExtractInput(zipPath, extractDir.path));
    } on Model3dLoadException {
      rethrow;
    } catch (_) {
      throw const Model3dLoadException('压缩包解析失败，文件可能已损坏');
    }
  }

  /// 递归查找目录下第一个 .obj 文件，无则返回 null。
  Future<String?> _findObj(String dirPath) async {
    final List<String> pending = <String>[dirPath];
    while (pending.isNotEmpty) {
      final String dir = pending.removeLast();
      final List<FileSystemEntity> entries =
          await Directory(dir).list().toList();
      for (final FileSystemEntity entry in entries) {
        if (entry is Directory) {
          pending.add(entry.path);
        } else if (entry.path.toLowerCase().endsWith('.obj')) {
          return entry.path;
        }
      }
    }
    return null;
  }

  bool _isArchive(String fileName) => fileName.toLowerCase().endsWith('.zip');

  /// 下载 URL 到本地路径，非 2xx 视为失败。
  Future<void> _download(String url, String savePath) async {
    final Response<dynamic> response = await _dio.download(url, savePath);
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw Model3dLoadException(
          '下载失败：HTTP ${response.statusCode}');
    }
  }

  /// 以 URL 为基准解析相对引用（支持子目录 / query）。
  String _resolve(String baseUrl, String ref) =>
      Uri.parse(baseUrl).resolve(ref).toString();

  /// 从 URL 中提取文件名（去掉路径与 query），空则回退 model.obj。
  String _fileNameOf(String url) {
    final String last = Uri.parse(url).pathSegments.isNotEmpty
        ? Uri.parse(url).pathSegments.last
        : '';
    return last.isEmpty ? 'model.obj' : last;
  }

  /// 读取本地文件，解析某指令（mtllib / map_Kd / map_Ka）引用的值。
  List<String> _directiveValues(String filePath, String directive) {
    if (!File(filePath).existsSync()) return <String>[];
    final RegExp regExp =
        RegExp('^\\s*$directive\\s+(\\S+)', caseSensitive: false);
    return File(filePath)
        .readAsLinesSync()
        .map((String line) {
          final Match? m = regExp.firstMatch(line);
          return m == null ? '' : m.group(1)!;
        })
        .where((String v) => v.isNotEmpty)
        .toList();
  }

  /// 缓存目录：`<documents>/model3d/<urlHash>/`
  Future<Directory> _cacheDirFor(String objUrl) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/model3d/${_hashOf(objUrl)}');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 轻量字符串哈希（跨运行稳定，用于缓存目录命名）。
  String _hashOf(String input) {
    var hash = 0;
    for (final int code in input.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }
}