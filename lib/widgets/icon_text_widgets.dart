import 'package:flutter/material.dart';

/// 封装：图标 + 文字 的横向组件
class IconTextWidget extends StatelessWidget {
  final String iconPath; // 图标路径
  final String text; // 显示文字
  final double iconSize; // 图标大小
  final double textSize; // 文字大小
  final Color textColor; // 文字颜色
  final double spacing; // 间距
  final FontWeight fontWeight; // 字体粗细

  // 构造函数（必填：图标+文字；其他提供默认值）
  const IconTextWidget({
    super.key,
    required this.iconPath,
    required this.text,
    this.iconSize = 25,
    this.textSize = 16,
    this.textColor = Colors.black,
    this.spacing = 8,
    this.fontWeight = FontWeight.bold,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          iconPath,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
        ),
        SizedBox(width: spacing),
        Text(
          text,
          style: TextStyle(
            fontSize: textSize,
            fontWeight: fontWeight,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
