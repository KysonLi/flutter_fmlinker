import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'media_utils.dart';
import 'video_progress_slider.dart';

/// 视频播放视图（自持全屏/沉浸式/控制栏显隐逻辑）。
///
/// - 非全屏：视频等比适配铺满整屏（letterbox 黑边），控制栏位于页面操作栏上方，
///   随 [pageControlsVisible]（页面导航/操作栏显隐）联动；点击视频区域通过
///   [onTogglePageControls] 切换页面控制栏；
/// - 竖版视频全屏：cover 铺满当前屏幕，进入沉浸式隐藏系统状态栏/导航栏，
///   控制栏贴屏底、顶部自定义状态栏显示时间，均随内部显隐状态自动隐藏/点击切换；
/// - 横版视频全屏：RotatedBox 应用内旋转 90° 呈现横屏，控制栏与自定义状态栏
///   随视频一起旋转到横屏底部/顶部，不依赖系统旋转设置。
///
/// 进入/退出全屏会通过 [onFullscreenChanged] 通知宿主（用于隐藏/恢复页面级
/// 导航与操作栏）；全屏期间自定义状态栏随控制栏展示当前时间（横版居中、竖版居左）。
class VideoPlayerView extends StatefulWidget {
  final VideoPlayerController controller;

  /// 非全屏时页面导航/操作栏是否可见（视频控制栏随之联动显隐）
  final bool pageControlsVisible;

  /// 非全屏时控制栏距屏幕底部的页面操作栏高度（控制栏需要在其上方，避免遮挡）
  final double bottomBarHeight;

  /// 非全屏点击视频区域：切换页面导航/操作栏显隐
  final VoidCallback onTogglePageControls;

  /// 非全屏时操作控制栏（播放/暂停/拖动进度）：重置页面控制栏自动隐藏计时
  final VoidCallback onInteract;

  /// 全屏状态变化回调（true 进入全屏 / false 退出全屏）
  final ValueChanged<bool> onFullscreenChanged;

  const VideoPlayerView({
    super.key,
    required this.controller,
    required this.pageControlsVisible,
    this.bottomBarHeight = 52,
    required this.onTogglePageControls,
    required this.onInteract,
    required this.onFullscreenChanged,
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  bool _fullscreen = false;

  /// 视频控制栏（含自定义状态栏）是否可见：全屏时独立控制，非全屏时随页面控制栏联动
  bool _controlsVisible = true;

  /// 进入沉浸式前捕获的系统状态栏/底部安全区高度
  double _topInset = 0;
  double _bottomInset = 0;

  Timer? _hideTimer;
  Timer? _clockTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _clockTimer?.cancel();
    _restoreSystemUi(); // 兜底恢复系统状态栏/导航栏，避免全屏退出时残留沉浸式
    super.dispose();
  }

  /// 非全屏：视频控制栏显隐跟随页面控制栏
  bool get _inlineControlsVisible => !_fullscreen && widget.pageControlsVisible;

  void _onAreaTap() {
    if (_fullscreen) {
      // 全屏：仅切换视频控制栏（含自定义状态栏）
      setState(() => _controlsVisible = !_controlsVisible);
      if (_controlsVisible) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
      }
      return;
    }
    // 非全屏：切换页面导航/操作栏（视频控制栏随之联动）
    widget.onTogglePageControls();
  }

  /// 全屏下交互后重置自动隐藏计时；非全屏交由页面重置
  void _onInteract() {
    if (_fullscreen) {
      _scheduleHide();
    } else {
      widget.onInteract();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_fullscreen || !_controlsVisible) return;
      setState(() => _controlsVisible = false);
    });
  }

  /// 视频全屏切换：纯应用内呈现，不依赖系统旋转设置。
  void _toggleFullscreen() {
    if (_fullscreen) {
      _restoreSystemUi();
      _hideTimer?.cancel();
      setState(() {
        _fullscreen = false;
        _controlsVisible = false;
      });
      widget.onFullscreenChanged(false);
    } else {
      _hideTimer?.cancel();
      // 进入沉浸式前捕获状态栏/底部安全区高度，用于自定义状态栏与控制栏避让
      _topInset = MediaQuery.of(context).padding.top;
      _bottomInset = MediaQuery.of(context).padding.bottom;
      _enterImmersiveMode();
      setState(() {
        _fullscreen = true;
        // 进入全屏先展示控制栏与自定义状态栏，随后定时自动隐藏
        _controlsVisible = true;
      });
      _scheduleHide();
      widget.onFullscreenChanged(true);
    }
    _syncClockTimer();
  }

  // ==================== 全屏系统栏控制 ====================

  void _enterImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 全屏期间定时刷新自定义状态栏时间（非全屏时停止，避免无谓重建）
  void _syncClockTimer() {
    if (_fullscreen) {
      _clockTimer ??= Timer.periodic(const Duration(seconds: 30), (Timer _) {
        if (mounted && _fullscreen) setState(() {});
      });
    } else {
      _clockTimer?.cancel();
      _clockTimer = null;
    }
  }

  String _clockText() {
    final DateTime now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onAreaTap,
      child: _fullscreen ? _buildFullscreen() : _buildInline(),
    );
  }

  /// 非全屏：等比适配、居中留黑边（letterbox）；控制栏位于页面操作栏上方
  Widget _buildInline() {
    final VideoPlayerController vc = widget.controller;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: AspectRatio(
            aspectRatio: vc.value.aspectRatio,
            child: VideoPlayer(vc),
          ),
        ),
        if (_inlineControlsVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom:
                widget.bottomBarHeight + MediaQuery.of(context).padding.bottom,
            child: _buildControlBar(),
          ),
      ],
    );
  }

  /// 全屏：视频铺满整屏，控制栏贴屏底、自定义状态栏贴屏顶
  Widget _buildFullscreen() {
    final VideoPlayerController vc = widget.controller;
    final bool landscape = _isLandscape(vc);
    final Widget controlBar = _buildControlBar(landscape: landscape);
    final Widget statusBar = _buildStatusBar(landscape: landscape);

    if (landscape) {
      // 横版视频全屏：应用内旋转 90°，竖屏屏幕上呈现横屏画面
      final Size screen = MediaQuery.of(context).size;
      return RotatedBox(
        quarterTurns: 1,
        child: SizedBox(
          width: screen.height,
          height: screen.width,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _fillVideo(vc),
              if (_controlsVisible) ...<Widget>[
                Positioned(left: 0, right: 0, bottom: 0, child: controlBar),
                Positioned(left: 0, right: 0, top: 0, child: statusBar),
              ],
            ],
          ),
        ),
      );
    }
    // 竖版视频全屏：cover 铺满当前屏幕
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _fillVideo(vc),
        if (_controlsVisible) ...<Widget>[
          Positioned(left: 0, right: 0, bottom: 0, child: controlBar),
          Positioned(left: 0, right: 0, top: 0, child: statusBar),
        ],
      ],
    );
  }

  /// 视频是否为横版（宽 > 高）
  bool _isLandscape(VideoPlayerController vc) {
    final Size vs = vc.value.size;
    return vs.width > vs.height && vs.width > 0 && vs.height > 0;
  }

  /// 全屏铺满：居中裁剪（cover）
  Widget _fillVideo(VideoPlayerController vc) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: vc.value.size.width > 0 ? vc.value.size.width : 16,
          height: vc.value.size.height > 0 ? vc.value.size.height : 9,
          child: VideoPlayer(vc),
        ),
      ),
    );
  }

  /// 视频控制栏：播放/暂停 + 当前时长 + 进度条 + 总时长 + 全屏。
  /// 全屏时左右内缩避开全面屏圆角；竖版全屏底部预留 iOS Home 指示条高度
  /// （Android 沉浸式已隐藏导航栏），横版全屏内容随视频旋转、无底部系统安全区。
  Widget _buildControlBar({bool landscape = false}) {
    final VideoPlayerController vc = widget.controller;
    final EdgeInsets padding;
    if (_fullscreen && landscape) {
      padding = const EdgeInsets.fromLTRB(16, 16, 16, 6);
    } else if (_fullscreen) {
      padding = EdgeInsets.fromLTRB(
          16, 16, 16, (Platform.isIOS ? _bottomInset : 0) + 6);
    } else {
      padding = const EdgeInsets.fromLTRB(8, 16, 8, 6);
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // 吸收点击，避免触发外层视频区域点击/页面控制栏显隐
        child: Padding(
          padding: padding,
          child: Row(
            children: <Widget>[
              _iconButton(
                vc.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                () {
                  if (vc.value.isPlaying) {
                    vc.pause();
                  } else {
                    vc.play();
                  }
                  _onInteract(); // 交互后重置自动隐藏计时
                },
              ),
              Text(
                fmtDuration(vc.value.position),
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                  ),
                  child: VideoProgressSlider(
                    controller: vc,
                    onSeek: (Duration d) {
                      vc.seekTo(d);
                      _onInteract();
                    },
                  ),
                ),
              ),
              Text(
                fmtDuration(vc.value.duration),
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
              _iconButton(
                _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                _toggleFullscreen,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 视频控制栏图标按钮（带点击热区扩展）
  Widget _iconButton(IconData icon, VoidCallback onTap, {double size = 28}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  /// 全屏自定义状态栏：沉浸式隐藏系统状态栏后，随视频控制栏显示当前时间。
  /// [landscape] 为 true 时时间居中（横版），否则居左（竖版）。
  Widget _buildStatusBar({bool landscape = false}) {
    return Container(
      height: (landscape ? 0 : _topInset) + 24,
      alignment: landscape ? Alignment.center : Alignment.centerLeft,
      padding: EdgeInsets.only(top: landscape ? 0 : _topInset),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x66000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          _clockText(),
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
      ),
    );
  }
}
