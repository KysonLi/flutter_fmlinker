import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:fmlink/routes/app_router.dart';
import 'package:fmlink/services/third_party_manager.dart';
import 'package:fmlink/themes/app_theme.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:provider/provider.dart';
import 'provider/tab_provider.dart';

void main() {
  // 配置 EasyLoading 全局样式
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..loadingStyle = EasyLoadingStyle.custom
    ..indicatorSize = 45.0
    ..radius = 10.0
    ..backgroundColor = Colors.white
    ..indicatorColor = Color(0xFF409EFF)
    ..textColor = Color(0xFF333333)
    ..maskColor = Color(0xFF409EFF).withOpacity(0.1)
    ..textStyle = const TextStyle(color: Color(0xFF333333), fontSize: 12.0)
    ..userInteractions = true
    ..dismissOnTap = false
    ..boxShadow = [
      BoxShadow(
        color: const Color(0xFF409EFF).withOpacity(0.15),
        blurRadius: 20,
        spreadRadius: 2,
        offset: const Offset(0, 4),
      ),
    ];

  // 初始化微信
  ThirdPartyManager.initWeChat();

  runApp(
    ChangeNotifierProvider(
      create: (context) => TabProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '泛媒关联',
      theme: AppTheme.lightTheme,
      routerConfig: AppRouter.router,
      builder: _buildAppBuilder,
    );
  }

  /// 按屏宽等比放大字号（仅 iOS）：设计基准 375pt。
  /// iPhone 逻辑宽 390~430pt、物理密度高于 Android，同字号观感偏小；
  /// 这里统一放大 textScaleFactor，Android/鸿蒙保持原值不受影响。
  static Widget _buildAppBuilder(BuildContext context, Widget? child) {
    final Widget app = EasyLoading.init()(context, child);
    if (!Platform.isIOS) return app;
    final mq = MediaQuery.of(context);
    final scale = (mq.size.width / 375.0).clamp(1.0, 1.2).toDouble();
    return MediaQuery(
      data: mq.copyWith(textScaleFactor: mq.textScaleFactor * scale),
      child: app,
    );
  }
}
