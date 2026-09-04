import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 封面候选图组件（候选链逐级失败回退）
class CoverImage extends StatelessWidget {
  final List<String> urls;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;

  const CoverImage({
    super.key,
    required this.urls,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: urls.first,
      width: width,
      height: height,
      fit: fit,
      placeholder: (BuildContext c, String u) => placeholder,
      errorWidget: (BuildContext c, String u, dynamic e) => CoverImage(
        urls: urls.sublist(1),
        width: width,
        height: height,
        fit: fit,
        placeholder: placeholder,
      ),
    );
  }
}