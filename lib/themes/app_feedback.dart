import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

/// 全局轻提示样式（EasyLoading）
///
/// 目标：**只留文字，干净利落**。
/// - 提示类（成功/失败/信息）**不显示任何图标**，只有文案（13px / 1.4 行高）
/// - 浅色胶囊（白底 + 深灰字）与页面白色卡片风格一致；
///   黑色沉浸式播放页上白底也足够醒目
/// - 仅 loading 状态带一个品牌蓝小转圈（与文案的间距由转圈自持，保证文字居中）
///
/// 注：EasyLoading 在 `loadingStyle: custom` 下所有提示共用同一种底色，
/// 图标只能通过 `errorWidget/successWidget/infoWidget` 替换，故这里统一置为空。
class AppFeedbackTheme {
  AppFeedbackTheme._();

  /// 胶囊底色：浅色（97% 白，透一点背景更柔和）
  static const Color _background = Color(0xF7FFFFFF);

  /// 文案色：与 App 主文字色一致
  static const Color _textColor = Color(0xFF333333);

  /// 转圈/进度色：品牌蓝
  static const Color _indicatorColor = Color(0xFF409EFF);

  /// 浅色底需要柔和阴影，否则与白色页面/白色卡片粘在一起分不出边界
  static const List<BoxShadow> _shadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  /// 加载转圈尺寸与它到文案的间距
  static const double _spinnerSize = 24;
  static const double _spinnerGap = 10;

  /// 应用启动时调用一次
  static void init() {
    EasyLoading.instance
      ..loadingStyle = EasyLoadingStyle.custom
      ..backgroundColor = _background
      ..textColor = _textColor
      ..indicatorColor = _indicatorColor
      ..progressColor = _indicatorColor
      ..radius = 10
      ..textAlign = TextAlign.center
      ..textStyle = const TextStyle(
        color: _textColor,
        fontSize: 13,
        height: 1.4,
        decoration: TextDecoration.none,
      )
      ..contentPadding =
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14)
      // 间距已包含在 indicatorWidget 里，这里置零，避免文字被顶偏
      ..textPadding = EdgeInsets.zero
      ..displayDuration = const Duration(milliseconds: 2000)
      ..animationStyle = EasyLoadingAnimationStyle.opacity
      ..toastPosition = EasyLoadingToastPosition.center
      ..userInteractions = true
      ..dismissOnTap = false
      ..boxShadow = _shadow
      ..indicatorWidget = _loadingIndicator()
      // 提示类只显示文字：置空后不再渲染图标
      ..successWidget = const SizedBox.shrink()
      ..errorWidget = const SizedBox.shrink()
      ..infoWidget = const SizedBox.shrink();
  }

  /// loading 转圈：品牌蓝细弧，下方自带宽 10px 间距
  static Widget _loadingIndicator() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: _spinnerSize,
          height: _spinnerSize,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(_indicatorColor),
          ),
        ),
        SizedBox(height: _spinnerGap),
      ],
    );
  }
}
