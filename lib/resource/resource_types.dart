import 'package:flutter/material.dart';

/// 资源播放模块基础工具
///
/// 资源类型语义（资源播放模块统一口径，与旧 Constants.resourceType* 不同，勿混用）：
/// 1=文本 2=图片 3=音频 4=视频 5=web 6=3D
///
/// 资源类型
enum ResourceType {
  text(1, '文本'),
  image(2, '图片'),
  audio(3, '音频'),
  video(4, '视频'),
  web(5, '网页'),
  model3d(6, '3D模型'),
  unknown(0, '资源');

  const ResourceType(this.value, this.label);

  /// 接口返回的原始值（字符串或数字）
  final int value;
  final String label;

  static ResourceType fromRaw(dynamic raw) {
    int v = 0;
    if (raw is int) {
      v = raw;
    } else if (raw is String) {
      v = int.tryParse(raw.trim()) ?? 0;
    } else if (raw is num) {
      v = raw.toInt();
    }
    for (final ResourceType t in ResourceType.values) {
      if (t.value == v) return t;
    }
    return ResourceType.unknown;
  }
}

/// 资源类型 UI 呈现相关工具
class ResourceTypeUi {
  static IconData icon(ResourceType type) {
    switch (type) {
      case ResourceType.text:
        return Icons.description_outlined;
      case ResourceType.image:
        return Icons.image_outlined;
      case ResourceType.audio:
        return Icons.headset_outlined;
      case ResourceType.video:
        return Icons.play_circle_outline;
      case ResourceType.web:
        return Icons.language;
      case ResourceType.model3d:
        return Icons.view_in_ar_outlined;
      case ResourceType.unknown:
        return Icons.folder_outlined;
    }
  }

  static Color color(ResourceType type) {
    switch (type) {
      case ResourceType.text:
        return const Color(0xFF67C23A);
      case ResourceType.image:
        return const Color(0xFFE6A23C);
      case ResourceType.audio:
        return const Color(0xFF9B59B6);
      case ResourceType.video:
      case ResourceType.web:
        return const Color(0xFF409EFF);
      case ResourceType.model3d:
        return const Color(0xFFE6A23C);
      case ResourceType.unknown:
        return const Color(0xFF909399);
    }
  }
}

/// URL 清洗：后端返回的图片/资源地址常被反引号包裹（如 `http://...`），
/// 统一去除首尾反引号与空白后使用。
String cleanUrl(dynamic url) {
  if (url == null) return '';
  final String s = url.toString().trim();
  return s.replaceAll('`', '');
}
