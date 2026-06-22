
import 'package:fluwx/fluwx.dart';

class ThirdPartyManager {
  static const String _wechatAppId = 'wxdcb4f64316ee1d04';
  static Fluwx fluwx = Fluwx();
  static Future<void> initWeChat() async {
    try {
      await fluwx.registerApi(
        appId: _wechatAppId,
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

      final  result = await fluwx.authBy(which: NormalAuth(scope: 'snsapi_userinfo', state: 'wechat_login'));
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
  static void listenWeChatResult(WeChatResponseSubscriber subscriber) {
    fluwx.addSubscriber(subscriber);
  }
  // 移除监听微信登录结果
  static void removeWeChatResultListener(WeChatResponseSubscriber subscriber) {
    fluwx.removeSubscriber(subscriber);
  }
}