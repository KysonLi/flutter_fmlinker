import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'dart:ui';

class Material {
  Material()
      : name = '',
        ambient = Vector3.all(0.1),
        diffuse = Vector3.all(0.8),
        specular = Vector3.all(0.5),
        ke = Vector3.zero(),
        tf = Vector3.zero(),
        mapKa = '',
        mapKd = '',
        mapKe = '',
        shininess = 0,
        ni = 0,
        opacity = 1.0,
        illum = 0;
  String name;
  Vector3 ambient;
  Vector3 diffuse;
  Vector3 specular;
  Vector3 ke;
  Vector3 tf;
  double shininess;
  double ni;
  double opacity;
  int illum;
  String mapKa;
  String mapKd;
  String mapKe;
}

/// Loading material from Material Library File (.mtl).
/// Reference：http://paulbourke.net/dataformats/mtl/
///
Future<Map<String, Material>> loadMtl(String fileName, {bool isAsset = true}) async {
  final materials = Map<String, Material>();
  String data;
  try {
    if (isAsset) {
      data = await rootBundle.loadString(fileName);
    } else {
      data = await File(fileName).readAsString();
    }
  } catch (_) {
    return materials;
  }
  final List<String> lines = data.split('\n');

  Material material = Material();
  for (String line in lines) {
    List<String> parts = line.trim().split(RegExp(r"\s+"));
    switch (parts[0]) {
      case 'newmtl':
        material = Material();
        if (parts.length >= 2) {
          material.name = parts[1];
          materials[material.name] = material;
        }
        break;
      case 'Ka':
        if (parts.length >= 4) {
          final v = Vector3(double.parse(parts[1]), double.parse(parts[2]), double.parse(parts[3]));
          material.ambient = v;
        }
        break;
      case 'Kd':
        if (parts.length >= 4) {
          final v = Vector3(double.parse(parts[1]), double.parse(parts[2]), double.parse(parts[3]));
          material.diffuse = v;
        }
        break;
      case 'Ks':
        if (parts.length >= 4) {
          final v = Vector3(double.parse(parts[1]), double.parse(parts[2]), double.parse(parts[3]));
          material.specular = v;
        }
        break;
      case 'Ke':
        if (parts.length >= 4) {
          final v = Vector3(double.parse(parts[1]), double.parse(parts[2]), double.parse(parts[3]));
          material.ke = v;
        }
        break;
      case 'map_Ka':
        if (parts.length >= 2) {
          material.mapKa = parts.last;
        }
        break;
      case 'map_Kd':
        if (parts.length >= 2) {
          material.mapKd = parts.last;
        }
        break;
      case 'Ns':
        if (parts.length >= 2) {
          material.shininess = double.parse(parts[1]);
        }
        break;
      case 'Ni':
        if (parts.length >= 2) {
          material.ni = double.parse(parts[1]);
        }
        break;
      case 'd':
        if (parts.length >= 2) {
          material.opacity = double.parse(parts[1]);
        }
        break;
      case 'illum':
        if (parts.length >= 2) {
          material.illum = int.parse(parts[1]);
        }
        break;
      default:
    }
  }
  return materials;
}

/// OHOS fork 上 `File.readAsBytes()` 走 asset 通道会抛
/// "Unable to load asset"（而 `readAsString()` 正常），退化为流式读取。
Future<Uint8List> _readBinaryFile(String fileName) async {
  try {
    final Uint8List bytes = await File(fileName).readAsBytes();
    return bytes;
  } catch (e) {
    print('[CUBE3D] readAsBytes FAIL $fileName: $e');
  }
  final BytesBuilder builder = BytesBuilder(copy: false);
  final Stream<List<int>> stream = File(fileName).openRead();
  await for (final List<int> chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// load an image from asset
Future<Image> loadImageFromAsset(String fileName, {bool isAsset = true, int maxSize = 2048}) {
  final c = Completer<Image>();
  Future<Uint8List> dataFuture;
  if (isAsset) {
    dataFuture = rootBundle.load(fileName).then((data) => data.buffer.asUint8List());
  } else {
    dataFuture = _readBinaryFile(fileName);
  }
  dataFuture.then((data) async {
    try {
      // 超大贴图（如 rose 的 wildtextures 5000x3333）若全尺寸解码，
      // 解码缓冲 + 打包纹理内存可能挤爆设备导致 decode 失败/返回 null，
      // 进而整模型退化为无贴图的黑色顶点色。这里超过 2048 上限等比缩小。
      final ImmutableBuffer buffer = await ImmutableBuffer.fromUint8List(data);
      final Codec codec = await instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
          if (intrinsicWidth <= maxSize && intrinsicHeight <= maxSize) {
            return const TargetImageSize();
          }
          final double scale = maxSize / math.max(intrinsicWidth, intrinsicHeight);
          return TargetImageSize(
            width: (intrinsicWidth * scale).round(),
            height: (intrinsicHeight * scale).round(),
          );
        },
      );
      final FrameInfo frameInfo = await codec.getNextFrame();
      print('[CUBE3D] decode ok $fileName -> '
          '${frameInfo.image.width}x${frameInfo.image.height}');
      c.complete(frameInfo.image);
    } catch (e) {
      print('[CUBE3D] decode FAIL $fileName: $e');
      c.completeError(e);
    }
  }).catchError((error) {
    print('[CUBE3D] read FAIL $fileName: $error');
    c.completeError(error);
  });
  return c.future;
}

/// load texture from asset
Future<MapEntry<String, Image>?> loadTexture(Material? material, String basePath, {bool isAsset = true}) async {
  // get the texture file name
  if (material == null) return null;
  String fileName = material.mapKa;
  if (fileName == '') fileName = material.mapKd;
  if (fileName == '') return null;

  // try to load image from asset in subdirectories
  Image? image;
  final List<String> dirList = fileName.split(RegExp(r'[/\\]+'));
  while (dirList.length > 0) {
    fileName = path.join(basePath, path.joinAll(dirList));
    try {
      image = await loadImageFromAsset(fileName, isAsset: isAsset);
    } catch (e) {
      print('[CUBE3D] loadTexture miss $fileName: $e');
    }
    if (image != null) return MapEntry(fileName, image);
    dirList.removeAt(0);
  }
  print('[CUBE3D] loadTexture null for ${material?.name}');
  try {
    final Directory dir = Directory(path.dirname(fileName));
    if (dir.existsSync()) {
      final List<String> entries =
          dir.listSync().map((e) => path.basename(e.path)).toList();
      print('[CUBE3D] dir ${dir.path}: $entries');
    } else {
      print('[CUBE3D] dir MISSING ${dir.path}');
    }
  } catch (e) {
    print('[CUBE3D] dir probe error: $e');
  }
  return null;
}

Future<Uint32List> getImagePixels(Image image) async {
  final c = Completer<Uint32List>();
  image.toByteData(format: ImageByteFormat.rawRgba).then((data) {
    c.complete(data!.buffer.asUint32List());
  }).catchError((error) {
    c.completeError(error);
  });

  return c.future;
}

/// Convert Vector3 to Color
Color toColor(Vector3 v, [double opacity = 1.0]) {
  return Color.fromRGBO((v.r * 255).toInt(), (v.g * 255).toInt(), (v.b * 255).toInt(), opacity);
}
