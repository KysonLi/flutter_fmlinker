import 'package:flutter/material.dart';

/// 底部操作栏删除按钮：胶囊渐变样式，禁用时显示为浅灰
class DeleteActionButton extends StatelessWidget {
  const DeleteActionButton({
    super.key,
    required this.enabled,
    this.onPressed,
    this.label = '删除',
  });

  /// 是否可点击（选中数量为 0 时禁用）
  final bool enabled;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(18);
    return SizedBox(
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFFFF5B5B), Color(0xFFE02020)],
                )
              : null,
          color: enabled ? null : const Color(0xFFE2E2E2),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF5B5B).withOpacity(0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
