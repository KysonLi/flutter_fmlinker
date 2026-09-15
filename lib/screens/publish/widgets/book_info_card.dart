import 'package:flutter/material.dart';

class BookInfoCard extends StatelessWidget {
  final String goodsName;
  final String goodsImage;
  final List<dynamic> resourceFormats;

  const BookInfoCard({
    super.key,
    required this.goodsName,
    required this.goodsImage,
    required this.resourceFormats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        children: [
          _buildCover(),
          const SizedBox(height: 12),
          _buildInfo(),
        ],
      ),
    );
  }

  Widget _buildCover() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: goodsImage.isNotEmpty
            ? Image.network(
                goodsImage,
                width: 110,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultCover();
                },
              )
            : _buildDefaultCover(),
      ),
    );
  }

  Widget _buildDefaultCover() {
    return Image.asset(
      'assets/images/default_cover.png',
      width: 120,
      height: 150,
      fit: BoxFit.cover,
    );
  }

  Widget _buildInfo() {
    return Column(
      children: [
        Text(
          goodsName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        _buildResourceIcons(),
      ],
    );
  }

  Widget _buildResourceIcons() {
    List<Widget> icons = [];

    for (var format in resourceFormats) {
      int? typeValue;
      if (format is int) {
        typeValue = format;
      } else if (format is String) {
        typeValue = int.tryParse(format);
      }

      if (typeValue != null) {
        icons.add(_getResourceIcon(typeValue));
      }
    }

    if (icons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: icons);
  }

  Widget _getResourceIcon(int typeValue) {
    switch (typeValue) {
      case 1:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_text.png',
            width: 20,
            height: 20,
          ),
        );
      case 2:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_img.png',
            width: 20,
            height: 20,
          ),
        );
      case 3:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_audio.png',
            width: 20,
            height: 20,
          ),
        );
      case 4:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_video.png',
            width: 20,
            height: 20,
          ),
        );
      case 5:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_html.png',
            width: 20,
            height: 20,
          ),
        );
      case 6:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_obj.png',
            width: 20,
            height: 20,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
