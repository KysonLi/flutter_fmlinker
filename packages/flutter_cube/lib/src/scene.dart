import 'dart:ui';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_cube/flutter_cube.dart';
import 'package:vector_math/vector_math_64.dart';
import 'object.dart';
import 'camera.dart';
import 'mesh.dart';
import 'material.dart';

typedef ObjectCreatedCallback = void Function(Object object);

class Scene {
  Scene({VoidCallback? onUpdate, ObjectCreatedCallback? onObjectCreated}) {
    this._onUpdate = onUpdate;
    this._onObjectCreated = onObjectCreated;
    world = Object(scene: this);
  }

  Camera camera = Camera();
  late Object world;
  Image? texture;
  BlendMode blendMode = BlendMode.srcOver;
  BlendMode textureBlendMode = BlendMode.srcOver;
  VoidCallback? _onUpdate;
  ObjectCreatedCallback? _onObjectCreated;
  int vertexCount = 0;
  int faceCount = 0;
  bool _needsUpdateTexture = false;

  /// 复用渲染缓冲，避免每帧为高面模型重新分配大数组（GC 压力）。
  RenderMesh? _renderMeshPool;
  final List<Polygon> _renderIndices = <Polygon>[];

  // calculate the total number of vertices and faces
  void _calculateVertices(Object o) {
    vertexCount += o.mesh.vertices.length;
    faceCount += o.mesh.indices.length;
    final List<Object> children = o.children;
    for (int i = 0; i < children.length; i++) {
      _calculateVertices(children[i]);
    }
  }

  RenderMesh _makeRenderMesh() {
    vertexCount = 0;
    faceCount = 0;
    _calculateVertices(world);
    RenderMesh? pool = _renderMeshPool;
    if (pool == null ||
        pool.positions.length < vertexCount * 2 ||
        pool.indices.length < faceCount) {
      pool = RenderMesh(vertexCount, faceCount);
      _renderMeshPool = pool;
    }
    final RenderMesh renderMesh = pool;
    renderMesh.vertexCount = 0;
    renderMesh.indexCount = 0;
    renderMesh.texture = texture;
    // 清除上一次绘制残留的索引，避免未命中裁剪的面被复用旧 Polygon 误收集
    renderMesh.indices.fillRange(0, faceCount, null);
    return renderMesh;
  }

  bool _isBackFace(double ax, double ay, double bx, double by, double cx, double cy) {
    double area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay);
    return area <= 0;
  }

  bool _isClippedFace(double ax, double ay, double az, double bx, double by, double bz, double cx, double cy, double cz) {
    // clip if at least one vertex is outside the near and far plane
    if (az < 0 || az > 1 || bz < 0 || bz > 1 || cz < 0 || cz > 1) return true;
    // clip if the face's bounding box does not intersect the viewport
    double left;
    double right;
    if (ax < bx) {
      left = ax;
      right = bx;
    } else {
      left = bx;
      right = ax;
    }
    if (left > cx) left = cx;
    if (left > 1) return true;
    if (right < cx) right = cx;
    if (right < -1) return true;

    double top;
    double bottom;
    if (ay < by) {
      top = ay;
      bottom = by;
    } else {
      top = by;
      bottom = ay;
    }
    if (top > cy) top = cy;
    if (top > 1) return true;
    if (bottom < cy) bottom = cy;
    if (bottom < -1) return true;
    return false;
  }

  void _renderObject(RenderMesh renderMesh, Object o, Matrix4 model, Matrix4 view, Matrix4 projection) {
    if (!o.visiable) return;
    model *= o.transform;
    final Matrix4 transform = projection * view * model;

    // apply transform and add vertices to renderMesh
    final double viewportWidth = camera.viewportWidth;
    final double viewportHeight = camera.viewportHeight;
    final Float32List positions = renderMesh.positions;
    final Float32List positionsZ = renderMesh.positionsZ;
    final List<Vector3> vertices = o.mesh.vertices;
    final int vertexOffset = renderMesh.vertexCount;
    final int vertexCount = vertices.length;
    final Vector4 v = Vector4.identity();
    for (int i = 0; i < vertexCount; i++) {
      // Conver Vector3 to Vector4
      final Float64List storage3 = vertices[i].storage;
      v.setValues(storage3[0], storage3[1], storage3[2], 1.0);
      // apply "model => world => camera => perspective" transform
      v.applyMatrix4(transform);
      // transform from homonegenous coordinates to the normalized device coordinates，
      final int xIndex = (vertexOffset + i) * 2;
      final int yIndex = xIndex + 1;
      final Float64List storage4 = v.storage;
      final double w = storage4[3]; //v.w;
      positions[xIndex] = storage4[0] / w; //v.x;
      positions[yIndex] = storage4[1] / w; //v.y;
      positionsZ[vertexOffset + i] = storage4[2] / w; //v.z;
    }
    renderMesh.vertexCount += vertexCount;

    // add faces to renderMesh
    final List<Polygon?> renderIndices = renderMesh.indices;
    final List<Polygon> indices = o.mesh.indices;
    final int indexOffset = renderMesh.indexCount;
    final int indexCount = indices.length;
    final bool culling = o.backfaceCulling;
    for (int i = 0; i < indexCount; i++) {
      final Polygon p = indices[i];
      final int vertex0 = vertexOffset + p.vertex0;
      final int vertex1 = vertexOffset + p.vertex1;
      final int vertex2 = vertexOffset + p.vertex2;
      final double ax = positions[vertex0 * 2];
      final double ay = positions[vertex0 * 2 + 1];
      final double az = positionsZ[vertex0];
      final double bx = positions[vertex1 * 2];
      final double by = positions[vertex1 * 2 + 1];
      final double bz = positionsZ[vertex1];
      final double cx = positions[vertex2 * 2];
      final double cy = positions[vertex2 * 2 + 1];
      final double cz = positionsZ[vertex2];
      if (!culling || !_isBackFace(ax, ay, bx, by, cx, cy)) {
        if (!_isClippedFace(ax, ay, az, bx, by, bz, cx, cy, cz)) {
          final double sumOfZ = az + bz + cz;
          renderIndices[indexOffset + i] = Polygon(vertex0, vertex1, vertex2, sumOfZ);
        }
      }
    }
    renderMesh.indexCount += indexCount;

    // add vertex colors to renderMesh
    final Int32List renderColors = renderMesh.colors;
    final List<Color> colors = o.mesh.colors;
    final int colorCount = o.mesh.vertices.length;
    if (o.mesh.texture != null) {
      // 有贴图：调制式兰伯特明暗（贴图 × 灰度）。这类烘焙模型 Kd/Ka
      // 常为 0，用白化光照避免全黑。光照只依赖固定光源方向与模型矩阵
      // （与相机无关），结果烘焙进 mesh 缓存；高面模型旋转/缩放时
      // 不再每帧重复计算 8 万面法线，显著降低 CPU 开销。
      Int32List? baked = o.mesh.bakedColors;
      if (baked == null || _matrixValueChanged(o.mesh.bakedColorsModel, model.storage)) {
        const double ambient = 0.55;
        final Vector3 lightDir = Vector3(0.3, 0.5, 1.0).normalized();
        final Matrix4 normalTransform = (model.clone()..invert()).transposed();
        final Vector3 a = Vector3.zero();
        final Vector3 b = Vector3.zero();
        final Vector3 c = Vector3.zero();
        baked = Int32List(colorCount);
        for (int i = 0; i < indexCount; i++) {
          final Polygon p = indices[i];
          a.setFrom(vertices[p.vertex0]);
          b.setFrom(vertices[p.vertex1]);
          c.setFrom(vertices[p.vertex2]);
          final Vector3 normal = normalVector(a, b, c)
            ..applyMatrix4(normalTransform)
            ..normalize();
          final double diff = math.max(normal.dot(lightDir), 0.0);
          final double brightness = (ambient + (1.0 - ambient) * diff).clamp(0.0, 1.0);
          final int b8 = (brightness * 255).round();
          final int value = (0xFF << 24) | (b8 << 16) | (b8 << 8) | b8;
          baked[p.vertex0] = value;
          baked[p.vertex1] = value;
          baked[p.vertex2] = value;
        }
        o.mesh.bakedColors = baked;
        o.mesh.bakedColorsModel = model.clone();
      }
      renderColors.setRange(vertexOffset, vertexOffset + colorCount, baked);
    } else if (colorCount != o.mesh.colors.length) {
      final int colorValue = toColor(o.mesh.material.diffuse, o.mesh.material.opacity).value;
      for (int i = 0; i < colorCount; i++) {
        renderColors[vertexOffset + i] = colorValue;
      }
    } else {
      for (int i = 0; i < colorCount; i++) {
        renderColors[vertexOffset + i] = colors[i].value;
      }
    }

    // apply perspective to screen transform
    for (int i = 0; i < vertexCount; i++) {
      final int x = (vertexOffset + i) * 2;
      final int y = x + 1;
      // remaps coordinates from [-1, 1] to the [0, viewport] space.
      positions[x] = (1.0 + positions[x]) * viewportWidth / 2;
      positions[y] = (1.0 - positions[y]) * viewportHeight / 2;
    }

    // add texture coordinates to renderMesh
    final int texcoordCount = o.mesh.vertices.length;
    final Float32List renderTexcoords = renderMesh.texcoords;
    if (o.mesh.texture != null && o.mesh.texcoords.length == texcoordCount) {
      final int imageWidth = o.mesh.textureRect.width.toInt();
      final int imageHeight = o.mesh.textureRect.height.toInt();
      final double imageLeft = o.mesh.textureRect.left;
      final double imageTop = o.mesh.textureRect.top;
      final List<Offset> texcoords = o.mesh.texcoords;
      for (int i = 0; i < texcoordCount; i++) {
        final Offset t = texcoords[i];
        final double x = t.dx * imageWidth + imageLeft;
        final double y = (1.0 - t.dy) * imageHeight + imageTop;
        final int xIndex = (vertexOffset + i) * 2;
        final int yIndex = xIndex + 1;
        renderTexcoords[xIndex] = x;
        renderTexcoords[yIndex] = y;
      }
    } else {
      for (int i = 0; i < texcoordCount; i++) {
        final int xIndex = (vertexOffset + i) * 2;
        final int yIndex = xIndex + 1;
        renderTexcoords[xIndex] = 0;
        renderTexcoords[yIndex] = 0;
      }
    }

    // render children
    List<Object> children = o.children;
    for (int i = 0; i < children.length; i++) {
      _renderObject(renderMesh, children[i], model, view, projection);
    }
  }

  void render(Canvas canvas, Size size) {
    // check if texture needs to update
    if (_needsUpdateTexture) {
      _needsUpdateTexture = false;
      _updateTexture();
    }

    // create render mesh from objects
    final renderMesh = _makeRenderMesh();
    _renderObject(renderMesh, world, Matrix4.identity(), camera.lookAtMatrix, camera.projectionMatrix);

    // remove the culled faces and recreate list.
    _renderIndices.clear();
    final List<Polygon?> rawIndices = renderMesh.indices;
    for (int i = 0; i < rawIndices.length; i++) {
      final Polygon? p = rawIndices[i];
      if (p != null) _renderIndices.add(p);
    }
    final List<Polygon> renderIndices = _renderIndices;
    if (renderIndices.length == 0) return;

    // sort the faces by z
    renderIndices.sort((Polygon a, Polygon b) {
      // return b.sumOfZ.compareTo(a.sumOfZ);
      final double az = a.sumOfZ;
      final double bz = b.sumOfZ;
      if (bz > az) return 1;
      if (bz < az) return -1;
      return 0;
    });

    // Flutter 的 Vertices.raw 索引仅支持 Uint16List（顶点数 ≤ 65535），
    // 高面模型（如本项目的 obj 有 8 万+ 顶点）需分批绘制，每批顶点重映射后 < 65535。
    final paint = Paint();
    if (renderMesh.texture != null) {
      Float64List matrix4 = new Matrix4.identity().storage;
      final shader = ImageShader(renderMesh.texture!, TileMode.mirror, TileMode.mirror, matrix4);
      paint.shader = shader;
    }
    paint.blendMode = blendMode;

    final int indexCount = renderIndices.length;
    const int batchTriangleLimit = 20000; // 每批去重后顶点 ≤ 60000 < 65535
    final bool hasTexture = renderMesh.texture != null;
    for (int start = 0; start < indexCount; start += batchTriangleLimit) {
      final int end = math.min(start + batchTriangleLimit, indexCount);

      // 批内顶点重映射：全局顶点索引 → 批内索引（0 起连续编号）
      final Map<int, int> remap = <int, int>{};
      for (int i = start; i < end; i++) {
        final Polygon p = renderIndices[i];
        remap.putIfAbsent(p.vertex0, () => remap.length);
        remap.putIfAbsent(p.vertex1, () => remap.length);
        remap.putIfAbsent(p.vertex2, () => remap.length);
      }

      final int batchVertexCount = remap.length;
      final Float32List batchPositions = Float32List(batchVertexCount * 2);
      final Float32List? batchTexcoords =
          hasTexture ? Float32List(batchVertexCount * 2) : null;
      final Int32List batchColors = Int32List(batchVertexCount);
      remap.forEach((int globalIndex, int localIndex) {
        batchPositions[localIndex * 2] = renderMesh.positions[globalIndex * 2];
        batchPositions[localIndex * 2 + 1] = renderMesh.positions[globalIndex * 2 + 1];
        batchColors[localIndex] = renderMesh.colors[globalIndex];
        if (hasTexture) {
          batchTexcoords![localIndex * 2] = renderMesh.texcoords[globalIndex * 2];
          batchTexcoords[localIndex * 2 + 1] = renderMesh.texcoords[globalIndex * 2 + 1];
        }
      });

      final Uint16List batchIndices = Uint16List((end - start) * 3);
      for (int i = start; i < end; i++) {
        final Polygon p = renderIndices[i];
        final int index0 = (i - start) * 3;
        batchIndices[index0] = remap[p.vertex0]!;
        batchIndices[index0 + 1] = remap[p.vertex1]!;
        batchIndices[index0 + 2] = remap[p.vertex2]!;
      }

      final Vertices vertices = Vertices.raw(
        VertexMode.triangles,
        batchPositions,
        textureCoordinates: batchTexcoords,
        colors: batchColors,
        indices: batchIndices,
      );
      // multiply：贴图 × 顶点明暗灰度，纹理保留颜色的同时显出几何褶皱
      canvas.drawVertices(vertices, hasTexture ? BlendMode.multiply : textureBlendMode, paint);
    }
  }

  /// 判断矩阵与缓存烘焙时相比是否变化。
  ///
  /// 不能用引用比较（`cached != model`）：每次 render 都会新建
  /// Matrix4.identity()，引用恒不相等会导致高面模型每帧重复烘焙
  /// 8 万面法线光照（旋转/缩放卡顿）。
  bool _matrixValueChanged(Matrix4? cached, Float64List current) {
    if (cached == null) return true;
    final Float64List cachedStorage = cached.storage;
    for (int i = 0; i < 16; i++) {
      if (cachedStorage[i] != current[i]) return true;
    }
    return false;
  }

  void objectCreated(Object object) {
    updateTexture();
    if (_onObjectCreated != null) _onObjectCreated!(object);
  }

  /// 参照 iOS 端参考实现的观感优化：根据模型包围盒自动居中并适配视口。
  ///
  /// [object] 及其所有子对象的 mesh 顶点都会纳入包围盒计算；
  /// 由于 flutter_cube 的 trackBall 旋转以原点为圆心，这里会把模型平移
  /// 使包围盒中心回到原点，相机 target 保持原点、position 按包围盒半径
  /// 与 fov 推算距离。不包含自动旋转。
  void fitToObject(Object object, {double margin = 1.3}) {
    final List<Mesh> meshes = <Mesh>[];
    _getAllMesh(meshes, object);

    final double inf = double.infinity;
    final Vector3 min = Vector3(inf, inf, inf);
    final Vector3 max = Vector3(-inf, -inf, -inf);
    bool hasVertex = false;
    for (final Mesh mesh in meshes) {
      final List<Vector3> vertices = mesh.vertices;
      for (int i = 0; i < vertices.length; i++) {
        final Float64List s = vertices[i].storage;
        hasVertex = true;
        if (s[0] < min.x) min.x = s[0];
        if (s[1] < min.y) min.y = s[1];
        if (s[2] < min.z) min.z = s[2];
        if (s[0] > max.x) max.x = s[0];
        if (s[1] > max.y) max.y = s[1];
        if (s[2] > max.z) max.z = s[2];
      }
    }
    if (!hasVertex) return;

    final Vector3 center = Vector3(
      (min.x + max.x) * 0.5,
      (min.y + max.y) * 0.5,
      (min.z + max.z) * 0.5,
    );
    final double radius = center.distanceTo(Vector3(max.x, max.y, max.z));

    // 把模型平移回原点，保证拖动旋转（以原点为圆心）时模型保持在视野中央
    object.position
      ..setFrom(center)
      ..negate();
    object.updateTransform();

    // fov 为纵向视场角；宽高比 < 1（竖屏）时水平视野更窄，需要推得更远
    final double tanHalfFov = math.tan(radians(camera.fov) / 2.0);
    double distance = radius / tanHalfFov;
    if (camera.aspectRatio < 1.0) {
      distance = math.max(distance, radius / (tanHalfFov * camera.aspectRatio));
    }
    distance *= margin;

    camera.target.setFrom(Vector3.zero());
    camera.position.setFrom(Vector3(0.0, 0.0, -distance));
    camera.zoom = 1.0;

    update();
  }

  void update() {
    if (_onUpdate != null) _onUpdate!();
  }

  void _getAllMesh(List<Mesh> meshes, Object object) {
    meshes.add(object.mesh);
    final List<Object> children = object.children;
    for (int i = 0; i < children.length; i++) {
      _getAllMesh(meshes, children[i]);
    }
  }

  void _updateTexture() async {
    final meshes = <Mesh>[];
    _getAllMesh(meshes, world);
    try {
      texture = await packingTexture(meshes);
      print('[CUBE3D] scene texture=${texture?.width}x${texture?.height} null=${texture == null}');
    } catch (e) {
      print('[CUBE3D] pack FAILED: $e');
      texture = null;
    }
    update();
  }

  /// Mark needs update texture
  void updateTexture() {
    _needsUpdateTexture = true;
    update();
  }
}

class RenderMesh {
  RenderMesh(int vertexCount, int faceCount) {
    positions = Float32List(vertexCount * 2);
    positionsZ = Float32List(vertexCount);
    texcoords = Float32List(vertexCount * 2);
    colors = Int32List(vertexCount);
    indices = List<Polygon?>.filled(faceCount, null);
  }
  late Float32List positions;
  late Float32List positionsZ;
  late Float32List texcoords;
  late Int32List colors;
  late List<Polygon?> indices;
  Image? texture;
  int vertexCount = 0;
  int indexCount = 0;
}
