import 'package:flutter/material.dart';

/// 居中提示列（图标+文案+可选按钮），深色沉浸式页面通用占位
class CenterColumn extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? button;

  const CenterColumn({
    super.key,
    required this.icon,
    required this.text,
    this.button,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 52, color: Colors.white38),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white60),
          ),
          if (button != null) ...<Widget>[
            const SizedBox(height: 12),
            button!,
          ],
        ],
      ),
    );
  }
}
