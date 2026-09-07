import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show compute;
import 'package:vector_math/vector_math_64.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'material.dart';

class Polygon {
  Polygon(this.vertex0, this.vertex1, this.vertex2, [this.sumOfZ = 0]);
  int vertex0;
  int vertex1;
  int vertex2;
  double sumOfZ;
  List<int> copyToArray() => [vertex0, vertex1, vertex2];
}

/// 后台 isolate 的顶点重映射输入（flat 数组）。
class _RebuildInput {
  _RebuildInput({
    required this.vertices,
    required this.texcoords,
    required this.faceVertex,
    required this.faceTex,
  });
  final Float64List vertices; // x,y,z 连续
  final Float64List texcoords; // u,v 连续
  final Int32List faceVertex; // 每面 3 个顶点下标
  final Int32List faceTex; // 每面 3 个纹理下标
}

/// 后台 isolate 的顶点重映射结果。
class _RebuildData {
  _RebuildData({
    required this.vertices,
    required this.texcoords,
    required this.faceVertex,
  });
  final Float64List vertices;
  final Float64List texcoords;
  final Int32List faceVertex;
}

/// 在后台 isolate 中执行顶点重映射（与 _rebuildVertices 等价）：
/// 同一顶点被多个不同纹理坐标引用时，为每个纹理坐标复制顶点。
_RebuildData _rebuildMeshSync(_RebuildInput input) {
  final int texcoordsCount = input.texcoords.length ~/ 2;
  final int faceCount = input.faceVertex.length ~/ 3;
  final Map<int, int> indexMap = <int, int>{};
  final List<double> newVertices = <double>[];
  final List<double> newTexcoords = <double>[];
  final Int32List newFaceVertex = Int32List(faceCount * 3);
  for (int i = 0; i < faceCount; i++) {
    for (int j = 0; j < 3; j++) {
      final int vIndex = input.faceVertex[i * 3 + j];
      final int tIndex = input.faceTex[i * 3 + j];
      final int vtIndex = vIndex * texcoordsCount + tIndex;
      int? v = indexMap[vtIndex];
      if (v == null) {
        v = newVertices.length ~/ 3;
        indexMap[vtIndex] = v;
        newVertices.add(input.vertices[vIndex * 3]);
        newVertices.add(input.vertices[vIndex * 3 + 1]);
        newVertices.add(input.vertices[vIndex * 3 + 2]);
        newTexcoords.add(input.texcoords[tIndex * 2]);
        newTexcoords.add(input.texcoords[tIndex * 2 + 1]);
      }
      newFaceVertex[i * 3 + j] = v;
    }
  }
  return _RebuildData(
    vertices: Float64List.fromList(newVertices),
    texcoords: Float64List.fromList(newTexcoords),
    faceVertex: newFaceVertex,
  );
}

Float64List _flattenVertices(List<Vector3> vertices) {
  final Float64List flat = Float64List(vertices.length * 3);
  for (int i = 0; i < vertices.length; i++) {
    final Float64List s = vertices[i].storage;
    flat[i * 3] = s[0];
    flat[i * 3 + 1] = s[1];
    flat[i * 3 + 2] = s[2];
  }
  return flat;
}

Float64List _flattenTexcoords(List<Offset> texcoords) {
  final Float64List flat = Float64List(texcoords.length * 2);
  for (int i = 0; i < texcoords.length; i++) {
    flat[i * 2] = texcoords[i].dx;
    flat[i * 2 + 1] = texcoords[i].dy;
  }
  return flat;
}

Int32List _flattenFaceIndices(List<Polygon> indices) {
  final Int32List flat = Int32List(indices.length * 3);
  for (int i = 0; i < indices.length; i++) {
    flat[i * 3] = indices[i].vertex0;
    flat[i * 3 + 1] = indices[i].vertex1;
    flat[i * 3 + 2] = indices[i].vertex2;
  }
  return flat;
}

void _fillVerticesFromFlat(List<Vector3> vertices, Float64List flat) {
  final List<Vector3> result =
      List<Vector3>.generate(flat.length ~/ 3, (int i) => Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2]));
  vertices
    ..clear()
    ..addAll(result);
}

void _fillTexcoordsFromFlat(List<Offset> texcoords, Float64List flat) {
  final List<Offset> result =
      List<Offset>.generate(flat.length ~/ 2, (int i) => Offset(flat[i * 2], flat[i * 2 + 1]));
  texcoords
    ..clear()
    ..addAll(result);
}

class Mesh {
  Mesh({List<Vector3>? vertices, List<Offset>? texcoords, List<Polygon>? indices, List<Color>? colors, this.texture, Rect? textureRect, this.texturePath, Material? material, this.name}) {
    this.vertices = vertices ?? <Vector3>[];
    this.texcoords = texcoords ?? <Offset>[];
    this.colors = colors ?? <Color>[];
    this.indices = indices ?? <Polygon>[];
    this.material = material ?? Material();
    this.textureRect = textureRect ?? Rect.fromLTWH(0, 0, texture?.width.toDouble() ?? 1.0, texture?.height.toDouble() ?? 1.0);
  }
  late List<Vector3> vertices;
  late List<Offset> texcoords;
  late List<Color> colors;
  late List<Polygon> indices;
  Image? texture;
  late Rect textureRect;
  String? texturePath;
  late Material material;
  String? name;

  /// 调制式光照结果缓存（贴图 + 高面模型）。
  ///
  /// 光照只依赖固定光源方向与模型矩阵（与相机无关），一次烘焙后即可复用，
  /// 避免旋转/缩放时每帧对 8 万面重复计算法线明暗。
  /// [bakedColorsModel] 为烘焙时的模型矩阵，矩阵不变则直接复用缓存。
  Int32List? bakedColors;
  Matrix4? bakedColorsModel;
}

/// Loading mesh from Wavefront's object file (.obj).
/// Reference：http://paulbourke.net/dataformats/obj/
///
/// 解析与顶点重映射在后台 isolate 中进行（compute），避免 8 万面模型
/// 的文本解析/归一化/哈希重建阻塞 UI 线程（进入页面动画卡顿）。
Future<List<Mesh>> loadObj(String fileName, bool normalized, {bool isAsset = true}) async {
  Map<String, Material>? materials;
  String basePath = path.dirname(fileName);

  var data;
  if (isAsset) {
    // load obj data from asset.
    data = await rootBundle.loadString(fileName);
  } else {
    // load obj data from file.
    data = await File(fileName).readAsString();
  }
  // 后台 isolate：逐行解析 + 按 normalized 缩放顶点
  final _ObjParseData parsed = await compute(_parseObjSync, _ParseObjInput(data, normalized));

  // 依 mtllib 加载材质库（需读写文件系统，留在主 isolate）
  for (final String mtlFile in parsed.mtlFiles) {
    materials = await loadMtl(path.join(basePath, mtlFile), isAsset: isAsset);
  }

  // 用解析结果重建渲染对象（顶点/纹理/索引元素表）
  final List<Vector3> vertices = List<Vector3>.generate(
    parsed.vertices.length ~/ 3,
    (int i) => Vector3(parsed.vertices[i * 3], parsed.vertices[i * 3 + 1], parsed.vertices[i * 3 + 2]),
  );
  final List<Offset> texcoords = List<Offset>.generate(
    parsed.texcoords.length ~/ 2,
    (int i) => Offset(parsed.texcoords[i * 2], parsed.texcoords[i * 2 + 1]),
  );
  final int faceCount = parsed.faceVertex.length ~/ 3;
  final List<Polygon> vertexIndices = <Polygon>[];
  final List<Polygon> textureIndices = <Polygon>[];
  for (int i = 0; i < faceCount; i++) {
    vertexIndices.add(Polygon(
      parsed.faceVertex[i * 3],
      parsed.faceVertex[i * 3 + 1],
      parsed.faceVertex[i * 3 + 2],
    ));
  }
  if (parsed.faceTex.length == parsed.faceVertex.length) {
    for (int i = 0; i < faceCount; i++) {
      textureIndices.add(Polygon(
        parsed.faceTex[i * 3],
        parsed.faceTex[i * 3 + 1],
        parsed.faceTex[i * 3 + 2],
      ));
    }
  }

  // 与逐面解析时代的兜底一致：部分面无 UV（faceTex 长度不足）时，
  // 用 (0,0,0) 纹理索引补齐，确保后续重映射/UV 修复逻辑行为不变。
  if (textureIndices.isEmpty && vertexIndices.isNotEmpty) {
    for (int i = 0; i < vertexIndices.length; i++) {
      textureIndices.add(Polygon(0, 0, 0));
    }
  }

  final meshes = await _buildMesh(
    vertices,
    texcoords,
    vertexIndices,
    textureIndices,
    materials,
    parsed.elementNames,
    parsed.elementMaterials,
    parsed.elementOffsets,
    basePath,
    isAsset,
  );
  // 顶点已在后台 isolate 内按 normalized 缩放，此处无需二次 normalizeMesh
  // （再算一遍全局 maxLength 只会得到 0.5，缩放比为 1，属于无效遍历）。
  return meshes;
}

/// 后台 isolate 的 obj 解析输入。
class _ParseObjInput {
  _ParseObjInput(this.data, this.normalized);
  final String data;
  final bool normalized;
}

/// 后台 isolate 的 obj 解析结果（flat 数组，便于跨 isolate 传输）。
class _ObjParseData {
  _ObjParseData({
    required this.vertices,
    required this.texcoords,
    required this.faceVertex,
    required this.faceTex,
    required this.mtlFiles,
    required this.elementNames,
    required this.elementMaterials,
    required this.elementOffsets,
  });
  final Float64List vertices; // x,y,z 连续
  final Float64List texcoords; // u,v 连续
  final Int32List faceVertex; // 每面 3 个顶点下标
  final Int32List faceTex; // 每面 3 个纹理下标
  final List<String> mtlFiles; // mtllib 引用的材质库文件
  final List<String> elementNames;
  final List<String> elementMaterials;
  final List<int> elementOffsets;
}

/// 在后台 isolate 中执行 obj 解析（与 loadObj 内联解析逻辑等价）。
_ObjParseData _parseObjSync(_ParseObjInput input) {
  final String data = input.data;
  final bool normalized = input.normalized;
  final List<double> vertices = <double>[];
  final List<double> texcoords = <double>[];
  final List<int> faceVertex = <int>[];
  final List<int> faceTex = <int>[];
  final List<String> mtlFiles = <String>[];
  final List<String> elementNames = <String>[];
  final List<String> elementMaterials = <String>[];
  final List<int> elementOffsets = <int>[];
  String? materialName;
  String? objectlName;
  String? groupName;

  final lines = data.split('\n');
  for (var line in lines) {
    final List<String> parts = line.trim().split(RegExp(r"\s+"));
    switch (parts[0]) {
      case 'mtllib':
        if (parts.length >= 2) mtlFiles.add(parts[1]);
        break;
      case 'v':
        if (parts.length >= 4) {
          vertices.add(double.parse(parts[1]));
          vertices.add(double.parse(parts[2]));
          vertices.add(double.parse(parts[3]));
        }
        break;
      case 'vt':
        if (parts.length >= 3) {
          double x = double.parse(parts[1]);
          double y = double.parse(parts[2]);
          if (x < 0 || x > 1.0) x %= 1.0;
          if (y < 0 || y > 1.0) y %= 1.0;
          texcoords.add(x);
          texcoords.add(y);
        }
        break;
      case 'usemtl':
        if (parts.length >= 2) materialName = parts[1];
        elementNames.add(objectlName ?? groupName ?? materialName ?? '');
        elementMaterials.add(materialName ?? '');
        elementOffsets.add(faceVertex.length ~/ 3);
        break;
      case 'g':
        if (parts.length >= 2) groupName = parts[1];
        break;
      case 'o':
        if (parts.length >= 2) objectlName = parts[1];
        break;
      case 'f':
        if (parts.length >= 4) {
          final List<String> p1 = parts[1].split('/');
          final List<String> p2 = parts[2].split('/');
          final List<String> p3 = parts[3].split('/');
          // 与 _getVertexIndex 等价
          int getVertexIndex(String vIndex) {
            final int v = int.parse(vIndex);
            return v < 0 ? v + 1 : v - 1;
          }

          final int v0 = getVertexIndex(p1[0]);
          final int v1 = getVertexIndex(p2[0]);
          final int v2 = getVertexIndex(p3[0]);
          faceVertex.add(v0);
          faceVertex.add(v1);
          faceVertex.add(v2);
          // 首面三个顶点都有 UV 时，记录纹理索引并进入 fan 三角化
          int? firstTex;
          int? lastTex;
          if ((p1.length >= 2 && p1[1] != '') &&
              (p2.length >= 2 && p2[1] != '') &&
              (p3.length >= 2 && p3[1] != '')) {
            firstTex = getVertexIndex(p1[1]);
            final int t1 = getVertexIndex(p2[1]);
            lastTex = getVertexIndex(p3[1]);
            faceTex.add(firstTex);
            faceTex.add(t1);
            faceTex.add(lastTex);
          }
          // polygon to triangle fan：f v1 v2 v3 v4 ... ==> (v1,v2,v3)+(v1,v3,v4)+...
          int lastVertex = v2;
          for (int i = 4; i < parts.length; i++) {
            final List<String> pN = parts[i].split('/');
            final int vN = getVertexIndex(pN[0]);
            faceVertex.add(v0);
            faceVertex.add(lastVertex);
            faceVertex.add(vN);
            lastVertex = vN;
            if (firstTex != null && pN.length >= 2 && pN[1] != '') {
              final int tN = getVertexIndex(pN[1]);
              faceTex.add(firstTex);
              faceTex.add(lastTex!);
              faceTex.add(tN);
              lastTex = tN;
            }
          }
        }
        break;
      default:
    }
  }

  // normalize（等价于 normalizeMesh 的缩放）在后台一并完成
  if (normalized && vertices.isNotEmpty) {
    double maxLength = 0;
    for (int i = 0; i < vertices.length; i += 3) {
      final double x = vertices[i];
      final double y = vertices[i + 1];
      final double z = vertices[i + 2];
      if (x > maxLength) maxLength = x;
      if (y > maxLength) maxLength = y;
      if (z > maxLength) maxLength = z;
    }
    final double scale = 0.5 / maxLength;
    for (int i = 0; i < vertices.length; i++) {
      vertices[i] *= scale;
    }
  }

  return _ObjParseData(
    vertices: Float64List.fromList(vertices),
    texcoords: Float64List.fromList(texcoords),
    faceVertex: Int32List.fromList(faceVertex),
    faceTex: Int32List.fromList(faceTex),
    mtlFiles: mtlFiles,
    elementNames: elementNames,
    elementMaterials: elementMaterials,
    elementOffsets: elementOffsets,
  );
}

/// Load the texture image file and rebuild vertices and texcoords to keep the same length.
Future<List<Mesh>> _buildMesh(
  List<Vector3> vertices,
  List<Offset> texcoords,
  List<Polygon> vertexIndices,
  List<Polygon> textureIndices,
  Map<String, Material>? materials,
  List<String> elementNames,
  List<String> elementMaterials,
  List<int> elementOffsets,
  String basePath,
  bool isAsset,
) async {
  if (elementOffsets.length == 0) {
    elementNames.add('');
    elementMaterials.add('');
    elementOffsets.add(0);
  }

  final List<Mesh> meshes = <Mesh>[];
  for (int index = 0; index < elementOffsets.length; index++) {
    int faceStart = elementOffsets[index];
    int faceEnd = (index + 1 < elementOffsets.length) ? elementOffsets[index + 1] : vertexIndices.length;

    var newVertices = <Vector3>[];
    var newTexcoords = <Offset>[];
    var newIndices = <Polygon>[];
    var newTextureIndices = <Polygon>[];

    if (faceStart == 0 && faceEnd == vertexIndices.length) {
      newVertices = vertices;
      newTexcoords = texcoords;
      newIndices = vertexIndices;
      newTextureIndices = textureIndices;
    } else {
      _copyRangeIndices(faceStart, faceEnd, vertices, vertexIndices, newVertices, newIndices);
      _copyRangeIndices(faceStart, faceEnd, texcoords, textureIndices, newTexcoords, newTextureIndices);
    }

    // load texture image from assets.
    final Material? material = (materials != null) ? materials[elementMaterials[index]] : null;
    final MapEntry<String, Image>? imageEntry =
        await loadTexture(material, basePath, isAsset: isAsset);
    print('[CUBE3D] mesh=${elementNames[index]} mat=${elementMaterials[index]} '
        'tex=${imageEntry?.key} img=${imageEntry?.value.width}x${imageEntry?.value.height} '
        'diffuse=${material?.diffuse}');

    // fix zero texture area
    if (imageEntry != null) {
      _remapZeroAreaUVs(newTexcoords, newTextureIndices, imageEntry.value.width.toDouble(), imageEntry.value.height.toDouble());
    }

    // If a vertex has multiple different texture coordinates,
    // then create a vertex for each texture coordinate.
    // 放到后台 isolate 执行（8 万面哈希重建较重，避免阻塞 UI 帧）
    if (newIndices.isNotEmpty && newTexcoords.isNotEmpty) {
      final _RebuildData rebuilt = await compute(
        _rebuildMeshSync,
        _RebuildInput(
          vertices: _flattenVertices(newVertices),
          texcoords: _flattenTexcoords(newTexcoords),
          faceVertex: _flattenFaceIndices(newIndices),
          faceTex: _flattenFaceIndices(newTextureIndices),
        ),
      );
      _fillVerticesFromFlat(newVertices, rebuilt.vertices);
      _fillTexcoordsFromFlat(newTexcoords, rebuilt.texcoords);
      final int faceCount = rebuilt.faceVertex.length ~/ 3;
      for (int i = 0; i < faceCount && i < newIndices.length; i++) {
        newIndices[i]
          ..vertex0 = rebuilt.faceVertex[i * 3]
          ..vertex1 = rebuilt.faceVertex[i * 3 + 1]
          ..vertex2 = rebuilt.faceVertex[i * 3 + 2];
      }
    }

    final Mesh mesh = Mesh(
      vertices: newVertices,
      texcoords: newTexcoords,
      indices: newIndices,
      texture: imageEntry?.value,
      texturePath: imageEntry?.key,
      material: material,
      name: elementNames[index],
    );
    meshes.add(mesh);
  }

  return meshes;
}

/// Copy a mesh from the obj
void _copyRangeIndices<type>(int start, int end, List<type> fromVertices, List<Polygon> fromIndices, List<type> toVertices, List<Polygon> toIndices) {
  if (start < 0 || end > fromIndices.length) return;
  final faceMap = List<int?>.filled(fromVertices.length, null);
  final List<int> face = List<int>.filled(3, 0);
  for (int i = start; i < end; i++) {
    final List<int> vi = fromIndices[i].copyToArray();
    for (int j = 0; j < vi.length; j++) {
      int index = vi[j];
      if (index < 0) index = fromVertices.length - 1 + index;
      int? v = faceMap[index];
      if (v == null) {
        face[j] = toVertices.length;
        faceMap[index] = toVertices.length;
        toVertices.add(fromVertices[index]);
      } else {
        face[j] = v;
      }
    }
    toIndices.add(Polygon(face[0], face[1], face[2]));
  }
}

/// Remap the UVs when the texture area is zero.
void _remapZeroAreaUVs(List<Offset> texcoords, List<Polygon> textureIndices, double textureWidth, double textureHeight) {
  for (int index = 0; index < textureIndices.length; index++) {
    Polygon p = textureIndices[index];
    if (texcoords[p.vertex0] == texcoords[p.vertex1] && texcoords[p.vertex0] == texcoords[p.vertex2]) {
      double u = (texcoords[p.vertex0].dx * textureWidth).floorToDouble();
      double v = (texcoords[p.vertex0].dy * textureHeight).floorToDouble();
      double u1 = (u + 1.0) / textureWidth;
      double v1 = (v + 1.0) / textureHeight;
      u /= textureWidth;
      v /= textureHeight;
      int texindex = texcoords.length;
      texcoords.add(Offset(u, v));
      texcoords.add(Offset(u, v1));
      texcoords.add(Offset(u1, v));
      p.vertex0 = texindex;
      p.vertex1 = texindex + 1;
      p.vertex2 = texindex + 2;
    }
  }
}

/// Calculate normal vector
Vector3 normalVector(Vector3 a, Vector3 b, Vector3 c) {
  return (b - a).cross(c - a).normalized();
}

// Packing all textures to a single image.
/// Reference：https://observablehq.com/@mourner/simple-rectangle-packing
///
Future<Image?> packingTexture(List<Mesh> meshes) async {
  // generate a key for a mesh.
  String getMeshKey(Mesh mesh) {
    if (mesh.texture != null) return mesh.texturePath ?? '' + mesh.textureRect.toString();
    return toColor(mesh.material.diffuse.bgr).toString();
  }

  // only pack the different textures.
  final allMeshes = meshes;
  final textures = Map<String, Mesh>();
  for (Mesh mesh in allMeshes) {
    if (mesh.vertices.length == 0) continue;
    final String key = getMeshKey(mesh);
    textures.putIfAbsent(key, () => mesh);
  }
  // if there is only one texture then return the texture directly.
  meshes = textures.values.toList();
  if (meshes.length == 1) {
    print('[CUBE3D] pack single texture ${meshes[0].texture?.width}x${meshes[0].texture?.height}');
    return meshes[0].texture;
  }
  if (meshes.length == 0) {
    print('[CUBE3D] pack none');
    return null;
  }
  print('[CUBE3D] pack start ${meshes.length} textures');

  // packing
  double area = 0;
  double maxWidth = 0;
  for (Mesh mesh in meshes) {
    area += mesh.textureRect.width * mesh.textureRect.height;
    maxWidth = math.max(maxWidth, mesh.textureRect.width);
  }
  meshes.sort((Mesh a, Mesh b) => b.textureRect.height.compareTo(a.textureRect.height));

  final double startWidth = math.max(math.sqrt(area / 0.95), maxWidth);
  final List<Rect> spaces = <Rect>[];
  spaces.add(Rect.fromLTWH(0, 0, startWidth, double.infinity));

  for (Mesh mesh in meshes) {
    for (int i = spaces.length - 1; i >= 0; i--) {
      final Rect block = mesh.textureRect;
      final Rect space = spaces[i];
      if (block.width > space.width || block.height > space.height) continue;
      mesh.textureRect = Rect.fromLTWH(space.left, space.top, block.width, block.height);
      if (block.width == space.width && block.height == space.height) {
        final Rect last = spaces.removeLast();
        if (i < spaces.length) spaces[i] = last;
      } else if (block.height == space.height) {
        spaces[i] = Rect.fromLTWH(space.left + block.width, space.top, space.width - block.width, space.height);
      } else if (block.width == space.width) {
        spaces[i] = Rect.fromLTWH(space.left, space.top + block.height, space.width, space.height - block.height);
      } else {
        spaces.add(Rect.fromLTWH(space.left + block.width, space.top, space.width - block.width, block.height));
        spaces[i] = Rect.fromLTWH(space.left, space.top + block.height, space.width, space.height - block.height);
      }
      break;
    }
  }

  // get the packed texture size
  int textureWidth = 0;
  int textureHeight = 0;
  for (Mesh mesh in meshes) {
    final Rect box = mesh.textureRect;
    if (textureWidth < box.left + box.width) textureWidth = (box.left + box.width).ceil();
    if (textureHeight < box.top + box.height) textureHeight = (box.top + box.height).ceil();
  }

  // get the pixels from mesh.texture
  final texture = Uint32List(textureWidth * textureHeight);
  for (Mesh mesh in meshes) {
    final int imageWidth = mesh.textureRect.width.toInt();
    final int imageHeight = mesh.textureRect.height.toInt();
    Uint32List pixels;
    if (mesh.texture != null) {
      final Uint32List data = await getImagePixels(mesh.texture!);
      pixels = data.buffer.asUint32List();
    } else {
      final int length = imageWidth * imageHeight;
      pixels = Uint32List(length);
      // color mode then set texture to transparent.
      final int color = 0; //mesh.material == null ? 0 : toColor(mesh.material.kd.bgr, mesh.material.d).value;
      for (int i = 0; i < length; i++) {
        pixels[i] = color;
      }
    }

    // break if the mesh.texture has changed
    if (mesh.textureRect.right > textureWidth || mesh.textureRect.bottom > textureHeight) break;

    // copy pixels from mesh.texture to texture
    int fromIndex = 0;
    int toIndex = mesh.textureRect.top.toInt() * textureWidth + mesh.textureRect.left.toInt();
    for (int y = 0; y < imageHeight; y++) {
      for (int x = 0; x < imageWidth; x++) {
        texture[toIndex + x] = pixels[fromIndex + x];
      }
      fromIndex += imageWidth;
      toIndex += textureWidth;
    }
  }

  // apply the packed textureRect to all meshes.
  for (Mesh mesh in allMeshes) {
    final String? key = getMeshKey(mesh);
    if (key != null) {
      final Rect? rect = textures[key]?.textureRect;
      if (rect != null) mesh.textureRect = rect;
    }
  }

  print('[CUBE3D] pack atlas ${textureWidth}x${textureHeight}');
  final c = Completer<Image>();
  decodeImageFromPixels(texture.buffer.asUint8List(), textureWidth, textureHeight, PixelFormat.rgba8888, (image) {
    c.complete(image);
  });
  return c.future;
}
