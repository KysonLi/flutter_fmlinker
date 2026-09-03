import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'center_column.dart';

/// 图片资源视图
class ImageView extends StatelessWidget {
  final String url;
  final bool hasAddress;

  const ImageView({
    Key? key,
    required this.url,
    required this.hasAddress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!hasAddress) {
      return const CenterColumn(
          icon: Icons.image_not_supported_outlined, text: '该资源暂未提供地址');
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