import 'dart:async';

import 'package:fluwx/fluwx.dart' as fluwx;

class ThirdPartyManager {
  static const String _wechatAppId = 'wxdcb4f64316ee1d04';

  /// iOS 微信 Universal Link（仅 iOS 生效，Android/OHOS 不校验）。
  ///
  /// 生效需三处保持一致，改动时务必同步：
  /// 1. `ios/Runner/Runner.entitlements` 的 `applinks:apigateway.mpreader.com`
  ///    （由 Xcode Associated Domains 能力读取）；
  /// 2. 微信开放平台「移动应用 - iOS」填写的 Universal Link；
  /// 3. 服务端 `https://apigateway.mpreader.com/.well-known/apple-app-site-association`
  ///    的 AASA 文件，`paths` 需覆盖 `/wxul/*`（teamId.bundleId 为 K57V7V2MH5.com.fanmei.Linker）。
  ///
  /// 微信 SDK 要求：https 协议、以 `/` 结尾。
  static const String weChatUniversalLink =
      'https://apigateway.mpreader.com/wxul/';

  static final fluwx.Fluwx _fluwx = fluwx.Fluwx();
  static fluwx.FluwxCancelable? _weChatResponseSubscription;

  static Future<void> initWeChat() async {
    try {
      await _fluwx.registerApi(
        appId: _wechatAppId,
        universalLink: weChatUniversalLink,
      );
    } catch (e) {
      print('微信初始化失败: $e');
      rethrow;
    }
  }

  static Future<bool> isWeChatInstalled() async {
    try {
      return await _fluwx.isWeChatInstalled;
    } catch (e) {
      print('检查微信安装状态失败: $e');
      return false;
    }
  }

  static Future<bool> weChatLogin() async {
    try {
      bool installed = await isWeChatInstalled();
      if (!installed) {
        throw Exception('微信未安装');
      }

      final result = await _fluwx.authBy(
          which: fluwx.NormalAuth(
              scope: 'snsapi_userinfo', state: 'wechat_login'));
      if (!result) {
        throw Exception('微信登录调用失败');
      }

      return result;
    } catch (e) {
      print('微信登录失败: $e');
      return false;
    }
  }

  // 订阅微信登录结果（fluwx 5.x addSubscriber 返回可取消句柄）
  static void listenWeChatResult(
      void Function(fluwx.WeChatResponse) subscriber) {
    removeWeChatResultListener();
    _weChatResponseSubscription = _fluwx.addSubscriber(subscriber);
  }

  // 移除监听微信登录结果
  static void removeWeChatResultListener() {
    _weChatResponseSubscription?.cancel();
    _weChatResponseSubscription = null;
  }
}
