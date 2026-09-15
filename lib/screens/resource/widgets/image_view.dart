import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'center_column.dart';

/// 图片资源视图
class ImageView extends StatelessWidget {
  final String url;
  final bool hasAddress;

  /// 本地缓存文件路径（有则直接显示本地图片，不请求网络）
  final String? localPath;

  const ImageView({
    super.key,
    required this.url,
    required this.hasAddress,
    this.localPath,
  });

  @override
  Widget build(BuildContext context) {
    final String? localPath = this.localPath;
    final bool hasLocal = localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();
    if (!hasAddress && !hasLocal) {
      return const CenterColumn(
          icon: Icons.image_not_supported_outlined, text: '该资源暂未提供地址');
    }
    // 本地缓存优先
    if (hasLocal) {
      return Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: Image.file(
            File(localPath),
            fit: BoxFit.contain,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                const CenterColumn(
                    icon: Icons.broken_image_outlined, text: '图片加载失败'),
          ),
        ),
      );
    }
    return Center(
      child: InteractiveViewer(
        maxScale: 4,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (BuildContext c, String u) => const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white54),
            ),
          ),
          errorWidget: (BuildContext c, String u, dynamic e) =>
              const CenterColumn(
                  icon: Icons.broken_image_outlined, text: '图片加载失败'),
        ),
      ),
    );
  }
}
