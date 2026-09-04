import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 视频进度滑动条（包装 Slider，监听 controller 位置变化）
class VideoProgressSlider extends StatefulWidget {
  final VideoPlayerController controller;
  final void Function(Duration) onSeek;

  const VideoProgressSlider({
    super.key,
    required this.controller,
    required this.onSeek,
  });

  @override
  State<VideoProgressSlider> createState() => _VideoProgressSliderState();
}

class _VideoProgressSliderState extends State<VideoProgressSlider> {
  bool _dragging = false;
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController vc = widget.controller;
    final Duration duration = vc.value.duration;
    final double max =
        duration.inMilliseconds > 0 ? duration.inMilliseconds / 1000.0 : 1;
    final double current = vc.value.position.inMilliseconds / 1000.0;
    final double value =
        _dragging ? _dragValue : current.clamp(0.0, max).toDouble();
    return Slider(
      value: value,
      max: max,
      onChanged: (double v) {
        setState(() {
          _dragging = true;
          _dragValue = v;
        });
      },
      onChangeEnd: (double v) {
        widget.onSeek(Duration(milliseconds: (v * 1000).round()));
        setState(() => _dragging = false);
      },
    );
  }
}