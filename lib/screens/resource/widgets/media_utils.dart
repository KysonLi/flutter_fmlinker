// 媒体展示相关工具

/// 格式化时长（mm:ss），供视频/音频进度条展示
String fmtDuration(Duration d) {
  final int s = d.inSeconds;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';
}