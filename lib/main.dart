import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/common/constants.dart';
import 'package:fmlink/routes/app_router.dart';
import 'package:fmlink/screens/privacy/privacy_consent_screen.dart';
import 'package:fmlink/services/prepay_service.dart';
import 'package:fmlink/services/privacy_consent_service.dart';
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

  runApp(
    ChangeNotifierProvider(
      create: (context) => TabProvider(),
      child: const MyApp(),
    ),
  );

}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<bool> _consentFuture = _loadConsent();
  bool _hasConsent = false;
  bool _initializedAfterConsent = false;

  Future<bool> _loadConsent() async {
    final bool hasConsent = await PrivacyConsentService().loadConsent();
    if (hasConsent) {
      Constants.hasPrivacyConsent = true;
      _initializeAfterConsent();
    }
    return hasConsent;
  }

  Future<void> _onAccepted() async {
    if (!mounted) return;
    Constants.hasPrivacyConsent = true;
    setState(() => _hasConsent = true);
    _initializeAfterConsent();
  }

  void _initializeAfterConsent() {
    if (_initializedAfterConsent) return;
    _initializedAfterConsent = true;

    unawaited(
      ThirdPartyManager.initWeChat().catchError((Object error) {
        print('同意隐私政策后初始化微信失败: $error');
      }),
    );

    // 隐私同意后才初始化本地缓存及生命周期监听。
    CacheService().init();

    // 隐私同意后才恢复可能触发设备/账号信息读取与网络请求的支付订单。
    unawaited(
      PrepayService().recoverHuaweiPurchases().then<void>(
        (_) {},
        onError: (Object error) {
          print('同意隐私政策后恢复华为支付订单失败: $error');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _consentFuture,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        final bool consentGranted =
            snapshot.connectionState == ConnectionState.done &&
                snapshot.data == true;
        if (consentGranted || _hasConsent) {
          Constants.hasPrivacyConsent = true;
          return _buildRouterApp();
        }
        return MaterialApp(
          title: '泛媒关联',
          theme: AppTheme.lightTheme,
          home: PrivacyConsentScreen(onAccepted: _onAccepted),
        );
      },
    );
  }

  Widget _buildRouterApp() {
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
