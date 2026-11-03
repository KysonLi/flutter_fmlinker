import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fmlink/common/constants.dart';
import 'package:umeng_apm_sdk/umeng_apm_sdk.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';
import 'package:fmlink/utils/app_log.dart';
import 'package:fmlink/utils/platform_compat.dart';

/// 友盟统计（U-App）与崩溃分析（U-APM）的统一入口。
///
/// 合规约束：所有方法都只能在用户同意隐私政策之后调用，
/// 未同意前不得初始化、不得触发任何采集（见 main.dart 的隐私门禁）。
///
/// 当前只使用 SDK 自带的基础能力：
/// - 启动/活跃/设备信息等统计（不发自定义事件）
/// - 原生崩溃采集（Java / Objective-C / ArkTS 由原生 SDK 自动上报）
/// - Dart 异常采集（下一次启动时由 [initDartCrashCapture] 接管）
class UmengService {
  static final UmengService _instance = UmengService._internal();
  factory UmengService() => _instance;
  UmengService._internal();

  bool _analyticsInited = false;
  bool _dartCrashCaptureInited = false;

  /// Android 宿主 Activity 的页面生命周期转发通道（见 MainActivity.kt）。
  static const MethodChannel _pageChannel = MethodChannel('fmlink/umeng_page');

  /// 初始化 U-App 统计（三端）。
  ///
  /// OHOS 端插件内部不接收 AppKey，实际读取
  /// `ohos/AppScope/resources/rawfile/umconfig.json`。
  void initAnalytics() {
    if (_analyticsInited || kIsWeb || !Constants.hasPrivacyConsent) return;
    _analyticsInited = true;
    try {
      UmengCommonSdk.initCommonNew(UmConfig(
        Constants.umengAndroidAppKey,
        Constants.umengIosAppKey,
        Constants.umengChannel,
        null,
      ));
      // 自动页面统计；Android 另需 MainActivity 的 onResume/onPause 配合。
      UmengCommonSdk.setPageCollectionModeAuto();
      if (Platform.isAndroid) {
        // 打开宿主 Activity 的生命周期转发（未同意前该开关保持关闭）。
        _pageChannel.invokeMethod<bool>('enable').then(
          (_) {},
          onError: (Object error) {
            AppLog.d('开启友盟页面统计失败: $error');
          },
        );
      }
    } catch (error) {
      AppLog.d('友盟统计初始化失败: $error');
    }
  }

  /// 初始化 Dart 异常采集（U-APM Flutter 层）。
  ///
  /// U-APM 要求在 `runApp` 之前接管错误处理，与「同意后才初始化」冲突，
  /// 因此只在“已同意 + 本次冷启动”时调用，即同意后的下一次启动生效：
  /// [appRunner] 会在 U-APM 的错误捕获 Zone 内被调用并负责 `runApp`。
  /// 返回 false 表示初始化未成功，调用方需自行 `runApp`，避免白屏。
  bool initDartCrashCapture(
      FutureOr<Widget> Function(NavigatorObserver) appRunner) {
    if (kIsWeb || !Constants.hasPrivacyConsent) return false;
    if (_dartCrashCaptureInited) return true;
    _dartCrashCaptureInited = true;
    try {
      UmengApmSdk(
        name: 'fmlink',
        bver: Constants.appVersion,
        env: UmengApmEnv.Release,
        enableLog: kDebugMode,
        // 复用已初始化的 binding：避免 U-APM 重复创建 Binding
        initFlutterBinding: () {},
      ).init(appRunner: appRunner);
      return true;
    } catch (error) {
      AppLog.d('友盟 Dart 异常采集初始化失败: $error');
      return false;
    }
  }

  /// 是否运行在友盟原生 SDK 已接入的平台（web 等平台直接跳过）。
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || PlatformCompat.isOhos);
}
