import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fmlink/services/link_service.dart';
import 'package:fmlink/services/user_service.dart';

/// 扫码页
///
/// 支持三类码：
/// - ISLI 线码（链码，嵌在书页文本行间的"双下划线"，BarcodeFormat.isli_line_code）
/// - ISLI 图标码（书籍封底标志码，BarcodeFormat.isli）
/// - 普通二维码/条码（内容为 ISLI 码或链接时同样处理）
///
/// 扫到 ISLI 码后调用 LinkService.getTargetsWithIsliCodeV2 解析关联资源，
/// 并跳转 /scan/result 展示。
class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final LinkService _linkService = LinkService();
  final UserService _userService = UserService();
  final ImagePicker _imagePicker = ImagePicker();

  late final MobileScannerController _controller;
  late final AnimationController _lineController;

  /// 正在解析/跳转中，忽略新扫码回调
  bool _isHandling = false;

  /// 同一码值 3 秒内去重
  String? _lastValue;
  int _lastValueTime = 0;

  @override
  void initState() {
    super.initState();
    // formats 留空 = 全部格式（native 侧同时启用 ISLI 线码 + ISLI 图标码解码）
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
    );
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _lineController.dispose();
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// 扫描窗口：宽 0.8 屏宽、高 0.5 屏宽（线码扁长、图标码接近方形，折中取偏扁矩形）
  Rect _windowFor(Size size) {
    final double w = size.width * 0.8;
    final double h = w * 0.62;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: w,
      height: h,
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isHandling || capture.barcodes.isEmpty) return;
    final Barcode barcode = capture.barcodes.first;
    final String? value = barcode.rawValue;
    if (value == null || value.isEmpty) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (value == _lastValue && now - _lastValueTime < 3000) return;
    _lastValue = value;
    _lastValueTime = now;

    _handleValue(value, barcode.format);
  }

  Future<void> _handleValue(String value, BarcodeFormat format) async {
    // 1) native ISLI 解码器直接产出（线码/图标码）
    if (format == BarcodeFormat.isli || format == BarcodeFormat.isli_line_code) {
      await _resolveIsli(value);
      return;
    }

    // 2) 普通码内容是 ISLI 码（纯数字 10~20 位，可含连字符/空格）
    final String digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (RegExp(r'^[0-9\- ]+$').hasMatch(value) &&
        digits.length >= 10 &&
        digits.length <= 20) {
      await _resolveIsli(digits);
      return;
    }

    // 3) 链接 → 询问后用内置 WebView 打开
    final Uri? uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await _confirmOpenUrl(value, uri.host);
      return;
    }

    // 4) 其余内容仅提示
    final String tip = value.length > 30 ? '${value.substring(0, 30)}…' : value;
    EasyLoading.showToast('无法识别的内容：$tip');
  }

  Future<void> _confirmOpenUrl(String url, String host) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开链接', style: TextStyle(fontSize: 16)),
        content: Text(host, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _pauseCameraAndPush(
        '/webview?url=${Uri.encodeComponent(url)}',
      );
    }
  }

  /// 解析 ISLI 码并跳转结果页
  Future<void> _resolveIsli(String isliCode) async {
    if (_isHandling) return;
    _isHandling = true;
    EasyLoading.show(status: '识别中...');
    try {
      // 冷启动后 Constants.token 为空，先从本地存储恢复
      await _userService.refreshToken();

      final Map<String, dynamic> result =
          await _linkService.getTargetsWithIsliCodeV2(isliCode);
      EasyLoading.dismiss();

      if (!mounted) return;
      if (result['status'] == true) {
        await _pauseCameraAndPush('/scan/result', extra: {
          'isliCode': isliCode,
          'data': result['data'],
        });
      } else {
        EasyLoading.showError(result['msg'] ?? '未找到关联资源');
      }
    } catch (e) {
      debugPrint('ISLI码解析失败: $e');
      EasyLoading.dismiss();
      EasyLoading.showError('识别失败，请重试');
    } finally {
      _isHandling = false;
    }
  }

  /// 停相机 → 跳转 → 返回后重启相机（扫码页是 tab 页，跳转期间保持挂载）
  Future<void> _pauseCameraAndPush(String location, {Object? extra}) async {
    try {
      await _controller.stop();
    } catch (_) {}
    if (!mounted) return;
    await context.push(location, extra: extra);
    if (mounted) {
      try {
        await _controller.start();
      } catch (_) {}
    }
  }

  /// 相册选图识别（ISLI 解码走整图，不裁剪扫描窗口）
  Future<void> _pickFromAlbum() async {
    if (_isHandling) return;
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (file == null) return;

      EasyLoading.show(status: '识别中...');
      final BarcodeCapture? capture = await _controller.analyzeImage(
        file.path,
        // 传整图窗口，避免控制器里存的实时扫描窗口把相册图裁掉
        scanWindow: const Rect.fromLTWH(0, 0, 1, 1),
      );
      EasyLoading.dismiss();
      if (!mounted) return;

      if (capture == null || capture.barcodes.isEmpty) {
        EasyLoading.showError('未识别到码，请换一张图片');
        return;
      }
      final Barcode barcode = capture.barcodes.first;
      final String? value = barcode.rawValue;
      if (value == null || value.isEmpty) {
        EasyLoading.showError('未识别到码，请换一张图片');
        return;
      }
      _lastValue = value;
      _lastValueTime = DateTime.now().millisecondsSinceEpoch;
      await _handleValue(value, barcode.format);
    } catch (e) {
      debugPrint('相册识码失败: $e');
      EasyLoading.dismiss();
      EasyLoading.showError('图片识别失败');
    }
  }

  /// 手动输入链码/ISLI码
  Future<void> _showManualInputDialog() async {
    if (_isHandling) return;
    final TextEditingController inputController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入链码', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: inputController,
          autofocus: true,
          keyboardType: TextInputType.text,
          maxLength: 25,
          decoration: const InputDecoration(
            hintText: '如 10-0001-0001-1',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final String input = inputController.text.trim();
    inputController.dispose();
    if (confirmed != true || !mounted) return;

    final String digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10 || digits.length > 20) {
      EasyLoading.showError('码格式不正确');
      return;
    }
    await _resolveIsli(digits);
  }

  Widget _buildErrorWidget(BuildContext context, MobileScannerException error) {
    final bool permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            permissionDenied ? Icons.no_photography_outlined : Icons.error_outline,
            color: Colors.white54,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            permissionDenied ? '相机权限未开启' : '相机启动失败',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (permissionDenied)
            OutlinedButton(
              onPressed: () async {
                try {
                  await openAppSettings();
                } catch (_) {
                  EasyLoading.showToast('请到系统设置中开启相机权限');
                }
              },
              child: const Text('去开启权限'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => unawaited(_controller.start()),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 相机预览（含扫描窗口）
            LayoutBuilder(
              builder: (context, constraints) {
                return MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  scanWindow: _windowFor(constraints.biggest),
                  errorBuilder: _buildErrorWidget,
                );
              },
            ),
            // 扫描框遮罩 + 扫描线
            LayoutBuilder(
              builder: (context, constraints) {
                return AnimatedBuilder(
                  animation: _lineController,
                  builder: (context, _) => CustomPaint(
                    size: constraints.biggest,
                    painter: _ScannerOverlayPainter(
                      window: _windowFor(constraints.biggest),
                      lineProgress: _lineController.value,
                    ),
                  ),
                );
              },
            ),
            // 顶栏
            Align(
              alignment: Alignment.topCenter,
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  const Expanded(
                    child: Text(
                      '扫一扫',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline,
                        color: Colors.white, size: 24),
                    onPressed: () => context.push('/scan/help'),
                  ),
                ],
              ),
            ),
            // 底部提示 + 操作
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '将码对准框内，即可自动扫描\n支持：链码 · ISLI标志码 · 二维码',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  _buildBottomControls(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 手电筒
        ValueListenableBuilder<MobileScannerState>(
          valueListenable: _controller,
          builder: (context, state, _) {
            final bool torchOn = state.torchState == TorchState.on;
            return _ControlButton(
              icon: torchOn ? Icons.flash_on : Icons.flash_off,
              label: torchOn ? '轻触关闭' : '手电筒',
              onTap: () => unawaited(_controller.toggleTorch()),
            );
          },
        ),
        _ControlButton(
          icon: Icons.photo_library_outlined,
          label: '相册',
          onTap: () => unawaited(_pickFromAlbum()),
        ),
        _ControlButton(
          icon: Icons.keyboard_alt_outlined,
          label: '输入链码',
          onTap: () => unawaited(_showManualInputDialog()),
        ),
      ],
    );
  }
}

/// 底部圆形操作按钮
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 扫描窗口遮罩：框外压暗、四角括号、扫描线
class _ScannerOverlayPainter extends CustomPainter {
  final Rect window;
  final double lineProgress;

  const _ScannerOverlayPainter({
    required this.window,
    required this.lineProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 框外半透明压暗
    final Paint dim = Paint()..color = Colors.black.withAlpha(140);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, window.top), dim);
    canvas.drawRect(
        Rect.fromLTRB(0, window.bottom, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, window.top, window.left, window.bottom), dim);
    canvas.drawRect(
        Rect.fromLTRB(window.right, window.top, size.width, window.bottom), dim);

    // 四角括号
    final Paint corner = Paint()
      ..color = const Color(0xFF409EFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const double len = 22;
    final List<List<Offset>> brackets = [
      // 左上
      [window.topLeft, window.topLeft + const Offset(len, 0)],
      [window.topLeft, window.topLeft + const Offset(0, len)],
      // 右上
      [window.topRight, window.topRight + const Offset(-len, 0)],
      [window.topRight, window.topRight + const Offset(0, len)],
      // 左下
      [window.bottomLeft, window.bottomLeft + const Offset(len, 0)],
      [window.bottomLeft, window.bottomLeft + const Offset(0, -len)],
      // 右下
      [window.bottomRight, window.bottomRight + const Offset(-len, 0)],
      [window.bottomRight, window.bottomRight + const Offset(0, -len)],
    ];
    for (final List<Offset> line in brackets) {
      canvas.drawLine(line[0], line[1], corner);
    }

    // 扫描线（框内上下往返）
    final double y =
        window.top + 4 + (window.height - 8) * lineProgress;
    final Rect lineRect = Rect.fromLTRB(
      window.left + 6,
      y,
      window.right - 6,
      y + 2,
    );
    final Paint linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0x00409EFF),
          Color(0xFF409EFF),
          Color(0x00409EFF),
        ],
      ).createShader(lineRect);
    canvas.drawRect(lineRect, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.window != window ||
        oldDelegate.lineProgress != lineProgress;
  }
}
