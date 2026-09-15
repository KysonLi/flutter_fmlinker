import 'package:flutter/material.dart';
import 'package:flutter_cube/flutter_cube.dart';

import 'package:fmlink/services/model3d/model3d_cache.dart';

/// 3D 模型展示页
///
/// 通过 [url] 传入 obj 资源地址，先经 [Model3dCache] 下载缓存到本地，
/// 再由 flutter_cube 渲染（拖动旋转 / 双指缩放）。
/// 若传入 [localZipPath]（已缓存的 zip 包），则直接解压本地包，不再下载。
class ResourceModel3dScreen extends StatefulWidget {
  final String? title;
  final String? url;

  /// 本地已缓存的 zip 包路径（有则直接解压，跳过网络下载）
  final String? localZipPath;

  const ResourceModel3dScreen({
    super.key,
    this.title,
    this.url,
    this.localZipPath,
  });

  @override
  State<ResourceModel3dScreen> createState() => _ResourceModel3dScreenState();
}

enum _LoadState { loading, loaded, error }

class _ResourceModel3dScreenState extends State<ResourceModel3dScreen> {
  _LoadState _state = _LoadState.loading;
  String? _localObjPath;
  String? _error;
  Scene? _scene;

  /// 模型真正可渲染（贴图打包完成）后才收起遮罩，避免下载完成后
  /// 还有 1~2 秒的空白（obj 解析 / 贴图解码是异步的）。
  bool _modelReady = false;
  int _readyTries = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = _LoadState.loading;
      _modelReady = false;
      _readyTries = 0;
    });
    final String url = (widget.url ?? '').trim();
    final String? localZip = widget.localZipPath;
    if (url.isEmpty && (localZip == null || localZip.isEmpty)) {
      setState(() {
        _state = _LoadState.error;
        _error = '未提供模型资源地址';
      });
      return;
    }
    try {
      final String localObj;
      if (localZip != null && localZip.isNotEmpty) {
        // 本地已缓存 zip：直接解压，不下载
        localObj = await Model3dCache.instance.extractLocalZip(localZip);
      } else {
        localObj = await Model3dCache.instance.ensureDownloaded(url);
      }
      if (!mounted) return;
      setState(() {
        _localObjPath = localObj;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      final String detail = e is Model3dLoadException
          ? e.message
          : (e.toString().length > 80
              ? '${e.toString().substring(0, 80)}…'
              : e.toString());
      setState(() {
        _error = '模型加载失败：$detail';
        _state = _LoadState.error;
      });
    }
  }

  /// 贴图打包是异步的（getImagePixels + 像素拷贝），按帧轮询
  /// [Scene.texture] 直到就绪；兜底超时（约 5 秒）：无贴图模型
  /// texture 恒为 null，不能一直转圈。
  void _checkModelReady() {
    if (!mounted) return;
    final Scene? scene = _scene;
    if (scene != null && scene.texture != null) {
      if (!_modelReady) setState(() => _modelReady = true);
      return;
    }
    if (_readyTries++ > 300) {
      if (!_modelReady) setState(() => _modelReady = true);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkModelReady());
  }

  @override
  Widget build(BuildContext context) {
    final String t = (widget.title ?? '').trim();
    return Scaffold(
      // 参照 iOS 参考实现的深色背景
      backgroundColor: const Color(0xFF313E54),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: const Color(0xFF313E54),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          t.isEmpty ? '3D 模型' : t,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _buildBody()),
          // 操作提示浮层
          if (_state == _LoadState.loaded)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '拖动旋转 · 双指缩放',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
            ),
          // 下载完成后渲染就绪前的加载遮罩：obj 解析 / 贴图解码打包是
          // 异步的，避免这段时间界面空白；模型可渲染后自动收起。
          if (_state == _LoadState.loaded && !_modelReady)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF313E54),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('模型加载中…',
                          style:
                              TextStyle(fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('模型下载中…',
                  style: TextStyle(fontSize: 13, color: Colors.white70)),
            ],
          ),
        );
      case _LoadState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 56, color: Colors.white30),
              const SizedBox(height: 12),
              Text(_error ?? '加载失败',
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _load,
                child: const Text('重试'),
              ),
            ],
          ),
        );
      case _LoadState.loaded:
        return Cube(
          interactive: true,
          onSceneCreated: (Scene scene) {
            _scene = scene;
            // 纯渲染路径：花瓣等单面模型关闭背面剔除避免缺面；
            // 相机在模型加载完成后自动适配居中。
            scene.world.add(Object(
              fileName: _localObjPath!,
              isAsset: false,
              backfaceCulling: false,
            ));
          },
          onObjectCreated: (Object object) {
            // 参照 iOS 参考实现的观感：按包围盒自动居中并推远相机（不自动旋转）
            _scene?.fitToObject(object);
            // 模型 mesh 已就绪，开始轮询贴图打包完成再收起加载遮罩
            _checkModelReady();
          },
        );
    }
  }
}
