import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/common/constants.dart';
import 'package:fmlink/routes/app_router.dart';
import 'package:fmlink/screens/privacy/privacy_consent_screen.dart';
import 'package:fmlink/services/prepay_service.dart';
import 'package:fmlink/services/privacy_consent_service.dart';
import 'package:fmlink/services/third_party_manager.dart';
import 'package:fmlink/services/umeng_service.dart';
import 'package:fmlink/themes/app_feedback.dart';
import 'package:fmlink/themes/app_theme.dart';
import 'package:fmlink/utils/error_handler.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:provider/provider.dart';
import 'provider/tab_provider.dart';

void main() {
  runZonedGuarded(() async {
    // 先初始化 Flutter binding，否则 initWeChat()（内部调用 MethodChannel）
    // 会因 ServicesBinding 未构造而崩溃（flutter#BindingBase.checkInstance）。
    WidgetsFlutterBinding.ensureInitialized();

    // 加载服务端错误码配置（assets/json/FMErrorStrings.json）
    await ErrorHandler().init();

    // 配置 EasyLoading 全局样式（深色胶囊 + 状态图标，统一轻提示/错误提示观感）
    AppFeedbackTheme.init();

    // 隐私同意状态必须在 runApp 之前确定：
    // 未同意时不得初始化任何采集 SDK；已同意时 U-APM 要求接管 runApp 才能采集 Dart 异常。
    final bool hasConsent = await PrivacyConsentService().loadConsent();
    Constants.hasPrivacyConsent = hasConsent;

    if (hasConsent && UmengService.isSupportedPlatform) {
      // 同意后的每次冷启动：先初始化统计，再由 U-APM 在捕获 Zone 内启动应用。
      UmengService().initAnalytics();
      final bool apmStarted =
          UmengService().initDartCrashCapture((NavigatorObserver observer) async {
        // 仅使用 U-APM 的异常采集，不启用页面性能追踪，故忽略 observer。
        return _buildApp(hasConsent: true);
      });
      // U-APM 初始化失败时兜底启动，避免白屏。
      if (!apmStarted) {
        runApp(_buildApp(hasConsent: true));
      }
      return;
    }

    runApp(_buildApp(hasConsent: hasConsent));
  }, (Object error, StackTrace stack) {
    // 未同意隐私政策期间发生的异常只打印，不上报（合规要求）。
    print('未捕获异常: $error\n$stack');
  });
}

Widget _buildApp({required bool hasConsent}) {
  return ChangeNotifierProvider(
    create: (context) => TabProvider(),
    child: MyApp(initialConsent: hasConsent),
  );
}


class MyApp extends StatefulWidget {
  /// 启动时已读取到的隐私政策同意状态（main() 中同步确定，避免首帧闪烁）。
  final bool initialConsent;

  const MyApp({super.key, required this.initialConsent});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _hasConsent = widget.initialConsent;
  bool _initializedAfterConsent = false;

  @override
  void initState() {
    super.initState();
    if (_hasConsent) {
      _initializeAfterConsent();
    }
    _hideNativeSplash();
  }

  /// 鸿蒙的原生启动层（图标 + 应用名称）在首帧后淡出；其它平台由系统启动页自动消失。
  void _hideNativeSplash() {
    if (kIsWeb || !Platform.isOhos) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MethodChannel('fmlink/splash').invokeMethod<void>('hide').then(
        (_) {},
        onError: (Object error) {
          print('隐藏原生启动页失败: $error');
        },
      );
    });
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

    // 部分场景（如从隐私弹窗当场同意）不会走 main() 的 U-APM 分支，
    // 这里补一次统计初始化；方法内部幂等，重复调用无副作用。
    UmengService().initAnalytics();

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
    if (_hasConsent) {
      return _buildRouterApp();
    }
    return MaterialApp(
      title: '泛媒关联',
      theme: AppTheme.lightTheme,
      home: PrivacyConsentScreen(onAccepted: _onAccepted),
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
