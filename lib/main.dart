import 'package:flutter/material.dart';
import 'package:fmlink/routes/app_router.dart';
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
    ..maskColor = Color(0xFF409EFF).withValues(alpha: 0.1)
    ..textStyle = const TextStyle(color: Color(0xFF333333), fontSize: 12.0)
    ..userInteractions = true
    ..dismissOnTap = false
    ..boxShadow = [
      BoxShadow(
        color: const Color(0xFF409EFF).withValues(alpha: 0.15),
        blurRadius: 20,
        spreadRadius: 2,
        offset: const Offset(0, 4),
      ),
    ];

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
      builder: EasyLoading.init(),
    );
  }
}
