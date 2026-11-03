import 'dart:io';

import 'package:flutter/material.dart';
import 'package:imagecropper_ohos/imagecropper_ohos.dart';
import 'package:imagecropper_ohos/page/crop.dart';

/// 头像裁剪页（鸿蒙专用）
///
/// image_cropper 的 Dart 通道（plugins.hunghd.vn/image_cropper）在鸿蒙侧没有实现，
/// 鸿蒙改用 imagecropper_ohos：它只提供裁剪算法（sampleImage / cropImage）与
/// [Crop] 组件，需要自行搭建裁剪界面，因此这里实现一个 1:1 的头像裁剪页。
///
/// 使用方式：`Navigator.push<String>` 打开，确认裁剪后 pop 出裁剪结果文件路径，
/// 用户取消则 pop 出 null。
class AvatarCropScreen extends StatefulWidget {
  /// 待裁剪图片路径
  final String imagePath;

  const AvatarCropScreen({super.key, required this.imagePath});

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  /// 裁剪结果的目标长边像素（用于按缩放比例反推原图采样尺寸）
  static const int _outputSize = 800;

  final ImagecropperOhos _cropper = ImagecropperOhos();
  final GlobalKey<CropState> _cropKey = GlobalKey<CropState>();

  /// 供裁剪组件展示的等比缩小图（原图过大时组件会卡顿）
  File? _sample;
  bool _loading = true;
  bool _cropping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // context.size 在首帧后才可用，这里等一帧再取屏幕尺寸做采样
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSample());
  }

  @override
  void dispose() {
    _deleteSample();
    super.dispose();
  }

  void _deleteSample() {
    final File? sample = _sample;
    _sample = null;
    if (sample == null) return;
    try {
      if (sample.existsSync()) sample.deleteSync();
    } catch (e) {
      debugPrint('头像裁剪：删除临时图片失败 $e');
    }
  }

  Future<void> _loadSample() async {
    if (!mounted) return;
    final double longestSide = MediaQuery.of(context).size.longestSide;
    try {
      final File? sample = await _cropper
          .sampleImage(
            path: widget.imagePath,
            maximumSize: longestSide.ceil(),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _sample = sample;
        _loading = false;
      });
    } catch (e) {
      debugPrint('头像裁剪：加载图片失败 $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '图片加载失败，请重新选择';
      });
    }
  }

  Future<void> _confirm() async {
    final CropState? crop = _cropKey.currentState;
    final Rect? area = crop?.area;
    if (_cropping) return;
    if (crop == null || area == null) {
      // 图片尚未完成布局，无法裁剪
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片还未准备好，请稍候')),
      );
      return;
    }

    setState(() {
      _cropping = true;
    });

    File? sampled;
    try {
      // 按当前缩放比例反推采样尺寸：裁剪框越小 → 采样越大 → 结果更清晰
      final double scale = crop.scale > 0 ? crop.scale : 1;
      final int sampleSize = (_outputSize / scale).round().clamp(240, 3000);
      final File? sampleFile = await _cropper
          .sampleImage(
            path: widget.imagePath,
            maximumSize: sampleSize,
          )
          .timeout(const Duration(seconds: 20));
      if (sampleFile == null) {
        throw StateError('sampleImage 返回空文件');
      }
      sampled = sampleFile;
      final File cropped = await _cropper
          .cropImage(
            file: sampleFile,
            area: area,
            angle: crop.angle,
            cx: crop.cx,
            cy: crop.cy,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      Navigator.pop(context, cropped.path);
    } catch (e) {
      debugPrint('头像裁剪失败 $e');
      if (!mounted) return;
      setState(() {
        _cropping = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('裁剪失败，请重试')),
      );
    } finally {
      if (sampled != null) {
        try {
          if (sampled.existsSync()) sampled.deleteSync();
        } catch (e) {
          debugPrint('头像裁剪：删除临时图片失败 $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '裁剪头像',
          style: TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    if (_error != null || _sample == null) {
      return Center(
        child: Text(
          _error ?? '图片加载失败，请重新选择',
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
      );
    }
    return Column(
      children: <Widget>[
        Expanded(
          child: Crop.file(
            _sample!,
            key: _cropKey,
            aspectRatio: 1,
            maximumScale: 4,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  '拖动调整位置，双指缩放大小',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _cropping ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF409EFF),
                      disabledBackgroundColor:
                          const Color(0xFF409EFF).withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: _cropping
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '确定',
                            style: TextStyle(fontSize: 15, color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
