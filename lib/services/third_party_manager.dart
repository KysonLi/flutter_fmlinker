
import 'dart:async';

import 'package:fluwx/fluwx.dart' as fluwx;

class ThirdPartyManager {
  static const String _wechatAppId = 'wxdcb4f64316ee1d04';
  static StreamSubscription<fluwx.BaseWeChatResponse>? _weChatResponseSubscription;

  static Future<void> initWeChat() async {
    try {
      await fluwx.registerWxApi(
        appId: _wechatAppId,
        // TODO(ios): universalLink 为占位值。正式接入微信开放平台后需替换为
        // 与 Apple Associated Domains 一致的 https 链接（并开通 associated domains 能力），
        // 否则 iOS 微信登录/分享回调不可用（Android/OHOS 不受影响）。
        universalLink: 'https://your-domain.com/wechat',
      );
    } catch (e) {
      print('微信初始化失败: $e');
      rethrow;
    }
  }

  static Future<bool> isWeChatInstalled() async {
    try {
      return await fluwx.isWeChatInstalled;
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

      final result = await fluwx.sendWeChatAuth(
          scope: 'snsapi_userinfo', state: 'wechat_login');
      if (!result) {
        throw Exception('微信登录调用失败');
      }

      return result;
    } catch (e) {
      print('微信登录失败: $e');
      return false;
    }
  }

  // 监听微信登录结果
  static void listenWeChatResult(void Function(fluwx.BaseWeChatResponse) subscriber) {
    removeWeChatResultListener();
    _weChatResponseSubscription = fluwx.weChatResponseEventHandler.listen(subscriber);
  }

  // 移除监听微信登录结果
  static void removeWeChatResultListener() {
    _weChatResponseSubscription?.cancel();
    _weChatResponseSubscription = null;
  }
}
