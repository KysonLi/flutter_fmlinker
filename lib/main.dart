import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/routes/app_router.dart';
import 'package:fmlink/services/third_party_manager.dart';
import 'package:fmlink/themes/app_feedback.dart';
import 'package:fmlink/themes/app_theme.dart';
import 'package:fmlink/utils/error_handler.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:provider/provider.dart';
import 'provider/tab_provider.dart';

void main() async {
  // 先初始化 Flutter binding，否则 initWeChat()（内部调用 MethodChannel）
  // 会因 ServicesBinding 未构造而崩溃（flutter#BindingBase.checkInstance）。
  WidgetsFlutterBinding.ensureInitialized();

  // 加载服务端错误码配置（assets/json/FMErrorStrings.json）
  await ErrorHandler().init();

  // 配置 EasyLoading 全局样式（深色胶囊 + 状态图标，统一轻提示/错误提示观感）
  AppFeedbackTheme.init();

  // 初始化微信
  ThirdPartyManager.initWeChat();

  runApp(
    ChangeNotifierProvider(
      create: (context) => TabProvider(),
      child: const MyApp(),
    ),
  );

  // 初始化缓存服务：加载缓存记录、注册生命周期观察者、询问未完成任务
  CacheService().init();
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
      data: mq.copyWith(
          textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * scale)),
      child: app,
    );
  }
}
