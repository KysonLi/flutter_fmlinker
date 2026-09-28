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

  /// 拉起微信支付（App 支付）
  ///
  /// 返回 true 表示已成功调起微信客户端；支付结果通过 [listenWeChatPayResult]
  /// 回调（errCode 0 成功、-2 用户取消）。
  static Future<bool> weChatPay({
    required String appId,
    required String partnerId,
    required String prepayId,
    required String packageValue,
    required String nonceStr,
    required int timeStamp,
    required String sign,
    String? signType,
    String? extData,
  }) async {
    try {
      final bool launched = await _fluwx.pay(
        which: fluwx.Payment(
          appId: appId,
          partnerId: partnerId,
          prepayId: prepayId,
          packageValue: packageValue,
          nonceStr: nonceStr,
          timestamp: timeStamp,
          sign: sign,
          signType: signType,
          extData: extData,
        ),
      );
      return launched;
    } catch (e) {
      print('微信支付调起失败: $e');
      return false;
    }
  }

  /// 订阅微信支付结果（只回传 errCode，errCode 0 成功、-2 用户取消、其他为失败）
  static void listenWeChatPayResult(void Function(int errCode) subscriber) {
    listenWeChatResult((response) {
      if (response is fluwx.WeChatPaymentResponse) {
        subscriber(response.errCode ?? -1);
      }
    });
  }

  // 移除监听微信登录结果
  static void removeWeChatResultListener() {
    _weChatResponseSubscription?.cancel();
    _weChatResponseSubscription = null;
  }
}
