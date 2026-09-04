import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:fmlink/resource/source_detail.dart';

import 'cover_image.dart';
import 'media_utils.dart';
import 'video_progress_slider.dart';

/// 音频播放视图：高斯模糊封面背景，居中封面卡片；
/// 资源名称下方为「当前时长 + 滑动进度条 + 总时长」，
/// 底部为「播放模式 / 播放·暂停 / 倍速」控制（循环/倍速由本组件自持并写入控制器）。
class AudioPlayerView extends StatefulWidget {
  final VideoPlayerController controller;
  final ScanResource resource;
  final List<String> coverUrls;

  const AudioPlayerView({
    super.key,
    required this.controller,
    required this.resource,
    required this.coverUrls,
  });

  @override
  State<AudioPlayerView> createState() => _AudioPlayerViewState();
}

class _AudioPlayerViewState extends State<AudioPlayerView> {
  bool _loop = false;
  double _speed = 1.0;

  static const List<double> _speedOptions = <double>[0.5, 1.0, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _applyParams();
  }

  @override
  void didUpdateWidget(covariant AudioPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换资源后控制器更新，重设循环/倍速参数
    if (oldWidget.controller != widget.controller) {
      _applyParams();
    }
  }

  /// 将当前循环/倍速设置写入控制器
  void _applyParams() {
    final VideoPlayerController vc = widget.controller;
    vc.setLooping(_loop);
    if (_speed != 1.0) {
      vc.setPlaybackSpeed(_speed);
    }
  }

  void _togglePlay() {
    final VideoPlayerController vc = widget.controller;
    if (vc.value.isPlaying) {
      vc.pause();
    } else {
      vc.play();
    }
    setState(() {});
  }

  void _toggleLoop() {
    setState(() => _loop = !_loop);
    widget.controller.setLooping(_loop);
  }

  void _cycleSpeed() {
    final int idx = _speedOptions.indexOf(_speed);
    final double next = _speedOptions[(idx + 1) % _speedOptions.length];
    setState(() => _speed = next);
    widget.controller.setPlaybackSpeed(next);
  }

  @override
  Widget build(BuildContext context) {
    final ScanResource r = widget.resource;
    final VideoPlayerController vc = widget.controller;
    final List<String> coverUrls = widget.coverUrls;
    final String name = (r.resourceName ?? '').trim().isEmpty
        ? '音频${r.resourceNo ?? ''}'
        : r.resourceName!;
    final String speedText = '${_speed.toStringAsFixed(1)}x';

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 背景：高斯模糊封面 + 暗色渐变遮罩保证前景可读
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: CoverImage(
            urls: coverUrls,
            fit: BoxFit.cover,
            placeholder: const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF1B1C22)),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x59000000), Color(0xE6000000)],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 84, 32, 72),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // 音频单屏展示：内容统一等比缩放，小屏自动缩小，不出现滚动/溢出
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _audioCoverCard(coverUrls),
                        const SizedBox(height: 26),
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 当前时长 / 滑动进度条 / 总时长
                        Row(
                          children: <Widget>[
                            Text(
                              fmtDuration(vc.value.position),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white70),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5),
                                  overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 12),
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white30,
                                  thumbColor: Colors.white,
                                ),
                                child: VideoProgressSlider(
                                  controller: vc,
                                  onSeek: vc.seekTo,
                                ),
                              ),
                            ),
                            Text(
                              fmtDuration(vc.value.duration),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white70),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // 播放模式 / 播放暂停 / 倍速
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            _audioCtrlButton(
                              icon: _loop ? Icons.repeat : Icons.repeat_one,
                              label: _loop ? '循环播放' : '单次播放',
                              onTap: _toggleLoop,
                            ),
                            const SizedBox(width: 56),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _togglePlay,
                              child: Icon(
                                vc.value.isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                size: 64,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 56),
                            _audioCtrlButton(
                              icon: Icons.speed,
                              label: speedText,
                              onTap: _cycleSpeed,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 音频封面卡片（3:4 竖版，前置展示，不模糊；按候选链逐级回退）
  Widget _audioCoverCard(List<String> coverUrls) {
    const double w = 190;
    const double h = 253;
    final Widget placeholder = Container(
      width: w,
      height: h,
      color: Colors.white10,
      child: const Icon(Icons.music_note, size: 84, color: Colors.white38),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: CoverImage(
        urls: coverUrls,
        width: w,
        height: h,
        fit: BoxFit.cover,
        placeholder: placeholder,
      ),
    );
  }

  /// 音频控制小按钮（图标+文字竖排）
  Widget _audioCtrlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 26, color: Colors.white),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}