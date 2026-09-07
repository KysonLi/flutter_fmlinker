import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    primaryColor: const Color(0xFF4A90E2),
    primaryColorDark: const Color(0xFF357ABD),
    primaryColorLight: const Color(0xFF74B0F7),
    colorScheme: ColorScheme.fromSwatch(
      primarySwatch: Colors.blue,
      accentColor: const Color(0xFF50E3C2),
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    cardColor: Colors.white,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      // 默认导航栏：白底 + 深色内容，无阴影（发现/出版等未单独配色的页面统一生效）
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF333333),
      // 仅在内容滚动到导航栏下方（页面向上滑动）时显示淡阴影，
      // 初始置顶时无阴影；滚动检测由 Scaffold/AppBar 内建完成，无需逐页配置。
      elevation: 0,
      scrolledUnderElevation: 4,
      shadowColor: Color(0x1A000000),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        // 与 iOS 系统导航栏标题（17pt semibold）保持一致
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: Color(0xFF333333),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const BorderSide(color: Colors.blue);
        }
        return const BorderSide(color: Colors.grey);
      }),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.blue; // 选中时为蓝色
        }
        return Colors.white; // 未选中时为灰色
      }),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(
        color: Color(0xFF333333),
        fontSize: 16,
      ),
      bodyMedium: TextStyle(
        color: Color(0xFF666666),
        fontSize: 14,
      ),
      bodySmall: TextStyle(
        color: Color(0xFF999999),
        fontSize: 12,
      ),
      titleLarge: TextStyle(
        color: Color(0xFF333333),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(
        color: Color(0xFF333333),
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: Color(0xFF333333),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: const Color(0xFF4A90E2),
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: Color(0xFFE0E0E0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: Color(0xFF4A90E2),
          width: 2,
        ),
      ),
      hintStyle: const TextStyle(
        color: Color(0xFF999999),
      ),
    ),
  );
}
