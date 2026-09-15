import 'dart:async';

import 'package:fluwx/fluwx.dart' as fluwx;

class ThirdPartyManager {
  static const String _wechatAppId = 'wxdcb4f64316ee1d04';
  static final fluwx.Fluwx _fluwx = fluwx.Fluwx();
  static fluwx.FluwxCancelable? _weChatResponseSubscription;

  static Future<void> initWeChat() async {
    try {
      await _fluwx.registerApi(
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
