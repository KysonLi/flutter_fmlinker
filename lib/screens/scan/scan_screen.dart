import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fmlink/resource/resource_entry.dart';
import 'package:fmlink/utils/chain_code_parser.dart';

/// 扫码页
///
/// 三区域布局：
/// - 顶部导航条（黑色半透明背景）
/// - 中间扫码区：扫码类型 + 扫码框 + 提示文案 + 焦距调节器 + 灯光开关
/// - 底部控制台：链码 / 标志码（图标码）/ 相册
///
/// 默认链码（线码）扫码：扫码框为宽>>高的长方形，解码器只做线码解码。
/// 点击"标志码"切换为图标码扫码：扫码框变为正方形，解码器只做图标码解码。
/// 点击"相册"：暂停相机输入 → 选图 → 先线码后图标码解析 → 解析完成恢复相机。
///
/// 扫码分流（无弹窗）：
/// - 链码（1D 线码）：parseChainCode 分流——ISBN/ISSN→标志码详情页、
///   ISON→提示不支持、其余→ResourceEntry 统一入口。
/// - 标志码（2D 图标码）：直接进入标志码版权详情页。
/// - 离场停相机，返回后自动重启相机。
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

/// 扫码模式：链码（线码）/ 标志码（图标码）
enum _ScanMode { line, icon }

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _lineController;

  /// 当前扫码模式，默认链码
  _ScanMode _mode = _ScanMode.line;

  /// 本地缩放状态（0=1x 无变焦，1=最大变焦），拖动滑块即时更新
  double _zoomScale = 0;

  /// 初始模式是否已下发给 native 解码器
  bool _didApplyInitialMode = false;

  /// 正在解析/跳转中，忽略新扫码回调
  bool _isHandling = false;

  /// 同一码值 3 秒内去重
  String? _lastValue;
  int _lastValueTime = 0;

  /// ISLI 特征点（图像坐标，线码 2 点 / 图标码 6 点）与图像尺寸，用于黄点渲染
  final List<Offset> _featurePoints = [];
  final Size _imageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    // formats 留空 = 全部格式（相册分析需要同时识别线码+图标码）
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
    )..addListener(_onControllerStateChanged);
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerStateChanged);
    _lineController.dispose();
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// 相机就绪后下发一次初始模式（默认只开线码解码器）
  void _onControllerStateChanged() {
    if (_controller.value.isInitialized && !_didApplyInitialMode) {
      _didApplyInitialMode = true;
      unawaited(_applyMode(_mode));
    }
  }

  /// 顶部导航条总高度（状态栏 + 导航栏）
  double get _topBarHeight =>
      MediaQuery.of(context).padding.top + kToolbarHeight;

  /// 底部操作区总高度（Home 指示条 + 分段胶囊 + 底部留白）
  double get _bottomBarHeight =>
      MediaQuery.of(context).padding.bottom + 16 + 46 + 10;

  /// 中间扫码区域矩形（全屏坐标：扣除顶部导航条与底部控制台）
  Rect _middleRectFor(Size fullSize) {
    return Rect.fromLTRB(
      0,
      _topBarHeight,
      fullSize.width,
      fullSize.height - _bottomBarHeight,
    );
  }

  /// 扫码窗口：相对全屏预览坐标。线码为宽>>高长方形，图标码为正方形；
  /// 均居中于中间扫码区域，受中间区域尺寸限制并设最大宽度（小屏收缩）。
  Rect _windowFor(Rect middle) {
    final Offset center = middle.center;
    if (_mode == _ScanMode.line) {
      final double w = min(middle.width * 0.85, 380);
      final double h = min(w * 0.26, middle.height * 0.24);
      return Rect.fromCenter(center: center, width: w, height: h);
    }
    // 正方形：受宽度、中间区域高度与最大宽度三重限制
    final double side =
        min(min(middle.width * 0.62, middle.height * 0.50), 340);
    return Rect.fromCenter(center: center, width: side, height: side);
  }

  /// 切换扫码模式：更新扫码框形状 + 通知 native 只开对应解码器
  Future<void> _switchMode(_ScanMode mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    await _applyMode(mode);
  }

  /// 下发解码模式给 native（实时帧只做对应类型解码）
  Future<void> _applyMode(_ScanMode mode) async {
    try {
      await _controller.setISLIMode(
        icon: mode == _ScanMode.icon,
        line: mode == _ScanMode.line,
      );
    } catch (e) {
      debugPrint('setISLIMode failed: $e');
    }
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

    _handleValue(
      value,
      barcode.format,
      featurePoints: barcode.corners,
      imageSize: capture.size,
    );
  }

  Future<void> _handleValue(
    String value,
    BarcodeFormat format, {
    List<Offset> featurePoints = const [],
    Size imageSize = Size.zero,
  }) async {
    // 1) native ISLI 解码器直接产出（线码/图标码）：走新分流
    if (format == BarcodeFormat.isli ||
        format == BarcodeFormat.isli_line_code) {
      _handleIsli(value, format);
      return;
    }

    // 2) 普通码内容是 ISLI 码（纯数字 10~20 位，可含连字符/空格）→ 按线码处理
    final String digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (RegExp(r'^[0-9\- ]+$').hasMatch(value) &&
        digits.length >= 10 &&
        digits.length <= 20) {
      _handleIsli(digits, BarcodeFormat.isli_line_code);
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

  /// ISLI 码分流（无弹窗）：
  /// - 图标码（2D）→ 标志码版权详情页
  /// - 线码（1D）→ parseChainCode 分流：
  ///   ISBN/ISSN → 标志码版权详情页（markCode 作 mprCode）
  ///   ISON → 提示不支持
  ///   其余 → ResourceEntry 统一入口
  void _handleIsli(String code, BarcodeFormat format) {
    if (_isHandling) return;
    _isHandling = true;

    // 滴的一声提示音
    try {
      _controller.playScanSound();
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }

    // 图标码（2D 标志码）→ 直接进标志码详情
    if (format == BarcodeFormat.isli) {
      _stopCameraAndNavigate(() {
        ResourceEntry.openIsliCopyright(context, code);
      });
      return;
    }

    // 线码（1D 链码）→ parseChainCode 分流
    final ChainCodeInfo info = parseChainCode(code);
    if (info.isMarkStyle) {
      // ISBN / ISSN → 标志码版权详情页
      _stopCameraAndNavigate(() {
        ResourceEntry.openIsliCopyright(context, info.markCode);
      });
    } else if (info.isIson) {
      EasyLoading.showToast('暂不支持该码制');
      _isHandling = false;
    } else {
      // 普通链码 → 统一入口
      _stopCameraAndNavigate(() {
        ResourceEntry.openFromCode(context,
            isliCode: info.fullCode, fromScan: true);
      });
    }
  }

  /// 停相机 → 执行跳转 → 返回后自动重启相机
  Future<void> _stopCameraAndNavigate(VoidCallback navigate) async {
    try {
      await _controller.stop();
    } catch (_) {}
    if (!mounted) {
      _isHandling = false;
      return;
    }
    navigate();
    // 等待跳转返回后重启相机（push 是异步的，但这里用 then 回调）
    // 注：openFromCode/openIsliCopyright 内部用 context.push，
    // 返回该页后通过 RouteAware/widgetsBinding 检测恢复。
    // 简单方案：延迟检测 mounted 后重启。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // 持续等待直到用户返回（页面重新可见时重启）
    _resumeWhenVisible();
  }

  /// 页面重新可见时重启相机
  void _resumeWhenVisible() {
    // 使用 WidgetsBinding.addPostFrameCallback 检测；
    // 若用户已返回（mounted 且 Navigator.canPop 为 false 即当前页）则重启。
    if (!mounted) {
      _isHandling = false;
      return;
    }
    // 通过 ModalRoute 了解是否还在当前页栈顶
    final ModalRoute? route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      // 还在跳转中，稍后重试
      Future<void>.delayed(
          const Duration(milliseconds: 500), _resumeWhenVisible);
      return;
    }
    // 已返回当前页，重启相机
    _isHandling = false;
    try {
      _controller.start();
    } catch (_) {}
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

  /// 停相机 → 跳转 → 返回后重启相机（URL/相册等场景）
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
            permissionDenied
                ? Icons.no_photography_outlined
                : Icons.error_outline,
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
    // 状态栏文字（时间/电池等）显示为白色，适配黑色扫码背景
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final Size fullSize = constraints.biggest;
            final Rect middle = _middleRectFor(fullSize);
            final Rect window = _windowFor(middle);
            return Stack(
              fit: StackFit.expand,
              children: [
                // 相机预览铺满全屏（视频内容显示在最底部，上下栏为半透明覆盖层）
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  scanWindow: window,
                  errorBuilder: _buildErrorWidget,
                  overlayBuilder: (context, c) => AnimatedBuilder(
                    animation: _lineController,
                    builder: (context, _) => CustomPaint(
                      size: c.biggest,
                      painter: _ScannerOverlayPainter(
                        window: window,
                        lineProgress: _lineController.value,
                        featurePoints: _featurePoints,
                        imageSize: _imageSize,
                      ),
                    ),
                  ),
                ),
                // 顶部导航条（黑色半透明覆盖层）
                Align(
                  alignment: Alignment.topCenter,
                  child: _buildTopBar(),
                ),
                // 中间扫码区域：类型 + 提示 + 焦距 + 灯光，围绕扫码框垂直居中
                Positioned(
                  top: _topBarHeight,
                  bottom: _bottomBarHeight,
                  left: 0,
                  right: 0,
                  child: _buildMiddleControls(window),
                ),
                // 底部控制台（黑色半透明覆盖层）
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildBottomBar(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 顶部导航条：黑色半透明背景
  Widget _buildTopBar() {
    return Container(
      color: Colors.black.withAlpha(140),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 24),
                onPressed: () => context.pop(),
              ),
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
      ),
    );
  }

  /// 中间扫码区域控件：类型标签 + 提示文案（框上方）+ 焦距调节器 + 灯光开关，
  /// 以扫码框为锚点垂直居中分布。
  Widget _buildMiddleControls(Rect window) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildScanTypeBadge(),
          const SizedBox(height: 10),
          const Text(
            '将码对准框内，即可自动扫描',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          // 扫码框占位：让上下两组控件围绕框分布且整体居中
          SizedBox(width: window.width, height: window.height),
          const SizedBox(height: 48),
          _buildFocusAndTorchControls(),
        ],
      ),
    );
  }

  /// 当前扫码类型标签
  Widget _buildScanTypeBadge() {
    final bool line = _mode == _ScanMode.line;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        line ? '扫链码' : '扫标志码',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 焦距调节器（一行）+ 灯光开关（独立一行，居中）
  Widget _buildFocusAndTorchControls() {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final bool torchOn = state.torchState == TorchState.on;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 焦距调节：边框圆角容器 + 相机图标 + 滑块 + 倍率
            Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 5.0,
                        activeTrackColor: const Color(0xFF5E7A9A),
                        inactiveTrackColor:
                            Colors.white.withValues(alpha: 0.18),
                        thumbColor: Colors.white.withValues(alpha: 0.65),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                          elevation: 0,
                          pressedElevation: 2,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        overlayColor: const Color(0x1F5E7A9A),
                        showValueIndicator: ShowValueIndicator.never,
                      ),
                      child: Slider(
                        value: _zoomScale.clamp(0.0, 1.0),
                        onChanged: (v) {
                          setState(() => _zoomScale = v);
                          unawaited(_controller.setZoomScale(v));
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(1 + _zoomScale * 7).toStringAsFixed(1)}x',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => unawaited(_controller.toggleTorch()),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(
                  torchOn ? Icons.flash_on : Icons.flash_off,
                  color: torchOn ? const Color(0xFFFFD54F) : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 底部操作区：链码/标志码在同一胶囊内左右切换，半透明毛玻璃背景
  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ScanModeSegment(
                    normalIcon: 'assets/icons/chain_code_normal.png',
                    activeIcon: 'assets/icons/chain_code_active.png',
                    label: '链码',
                    active: _mode == _ScanMode.line,
                    onTap: () => unawaited(_switchMode(_ScanMode.line)),
                  ),
                  _ScanModeSegment(
                    normalIcon: 'assets/icons/isli_code_normal.png',
                    activeIcon: 'assets/icons/isli_code_active.png',
                    label: '标志码',
                    active: _mode == _ScanMode.icon,
                    onTap: () => unawaited(_switchMode(_ScanMode.icon)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分段胶囊内的单个按钮（图标 + 文案，选中蓝底高亮）
class _ScanModeSegment extends StatelessWidget {
  final String normalIcon;
  final String activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ScanModeSegment({
    required this.normalIcon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: active ? const Color(0xB3409EFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              active ? activeIcon : normalIcon,
              width: 30,
              height: 30,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 扫描窗口遮罩：框外压暗、四角括号、扫描线、特征点黄点
class _ScannerOverlayPainter extends CustomPainter {
  final Rect window;
  final double lineProgress;

  /// 特征点（图像坐标）与图像尺寸；非空时按 aspectFill 映射到预览坐标画黄点
  final List<Offset> featurePoints;
  final Size imageSize;

  const _ScannerOverlayPainter({
    required this.window,
    required this.lineProgress,
    this.featurePoints = const [],
    this.imageSize = Size.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 框外半透明压暗
    final Paint dim = Paint()..color = Colors.black.withAlpha(140);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, window.top), dim);
    canvas.drawRect(
        Rect.fromLTRB(0, window.bottom, size.width, size.height), dim);
    canvas.drawRect(
        Rect.fromLTRB(0, window.top, window.left, window.bottom), dim);
    canvas.drawRect(
        Rect.fromLTRB(window.right, window.top, size.width, window.bottom),
        dim);

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
    final double y = window.top + 4 + (window.height - 8) * lineProgress;
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

    // 特征点小黄亮点（线码 2 点 / 图标码 6 点）
    if (featurePoints.isNotEmpty && !imageSize.isEmpty) {
      final double ratio = max(
        size.width / imageSize.width,
        size.height / imageSize.height,
      );
      final double offX = (imageSize.width * ratio - size.width) / 2;
      final double offY = (imageSize.height * ratio - size.height) / 2;
      final Paint dot = Paint()..color = const Color(0xFFFFD54F);
      final Paint halo = Paint()..color = const Color(0x55FFD54F);
      for (final Offset pt in featurePoints) {
        final Offset p = Offset(pt.dx * ratio - offX, pt.dy * ratio - offY);
        canvas.drawCircle(p, 8, halo);
        canvas.drawCircle(p, 4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.window != window ||
        oldDelegate.lineProgress != lineProgress ||
        oldDelegate.featurePoints != featurePoints ||
        oldDelegate.imageSize != imageSize;
  }
}
