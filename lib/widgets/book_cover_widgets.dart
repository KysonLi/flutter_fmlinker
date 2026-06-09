import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BookCover extends StatelessWidget {
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final bool showShadow;

  const BookCover({
    super.key,
    required this.imageUrl,
    this.width = 100,
    this.height = 140,
    this.fit = BoxFit.cover,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      // 这里加阴影
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4), // 轻微圆角更自然
        boxShadow: showShadow ? [
          BoxShadow(
            color: Colors.black12, // 淡淡的阴影色
            blurRadius: 2,
            offset: Offset(0, 1),
            spreadRadius: 0,
          ),
        ] : null,
      ),
      // 防止图片溢出阴影
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: fit,
          cacheKey: imageUrl,
          placeholder: (context, url) => Container(color: Colors.grey[200]),
          errorWidget:
              (context, url, error) => Container(
                color: Colors.grey[200],
                child: Image.asset('assets/images/default_cover.png'),
              ),
        ),
      ),
    );
  }
}
