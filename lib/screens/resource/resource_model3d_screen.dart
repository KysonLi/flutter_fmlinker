import 'package:flutter/material.dart';

/// 3D 模型展示页（占位）
///
/// 由资源模块入口跳转，标题可经 [title] 传入，
/// 3D 渲染能力接入前先展示占位提示。
class ResourceModel3dScreen extends StatelessWidget {
  final String? title;

  const ResourceModel3dScreen({super.key, this.title});

  @override
  Widget build(BuildContext context) {
    final String t = (title ?? '').trim();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        title: Text(
          t.isEmpty ? '3D 模型' : t,
          style: const TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.view_in_ar_outlined,
              size: 64,
              color: Color(0xFFBFBFBF),
            ),
            SizedBox(height: 16),
            Text(
              '3D 模型展示开发中',
              style: TextStyle(fontSize: 14, color: Color(0xFF8C8C8C)),
            ),
          ],
        ),
      ),
    );
  }
}
