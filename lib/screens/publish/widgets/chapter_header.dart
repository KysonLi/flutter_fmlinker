import 'package:flutter/material.dart';

class ChapterHeader extends StatelessWidget {
  final String chapter;
  final String chapterTitle;
  final String? article;

  const ChapterHeader({
    super.key,
    required this.chapter,
    required this.chapterTitle,
    this.article,
  });

  String _buildCatalogText() {
    String articleNum = '';
    String chapterNum = '';
    String title = chapterTitle.isNotEmpty ? ' $chapterTitle' : '';

    if (article != null && article != '0' && article!.isNotEmpty) {
      articleNum = '[第${article!}篇]';
    }

    if (chapter != '0' && chapter.isNotEmpty) {
      chapterNum = ' 第$chapter章';
    }

    return '$articleNum$chapterNum$title';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFF8F8F8),
      child: Text(
        _buildCatalogText(),
        textAlign: TextAlign.left,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}