import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fmlink/common/constants.dart';
import 'package:tencent_kit/tencent_kit.dart';

/// QQ 登录授权模式
enum QqAuthMode {
  /// 客户端授权：App 内直接拿到 `openid + access_token`（Android / iOS）
  clientSide,

  /// 服务端授权：只拿到 `authorization code`，由服务端用 appId/appKey 换 token
  serverSide;
}

/// QQ 登录服务（Android / iOS / 鸿蒙）
///
/// 基于 `tencent_kit`（腾讯 QQ 互联 SDK 的 Flutter 封装，6.x 起官方支持鸿蒙）：
/// - Android：客户端授权 `login()` → `openid + access_token`
/// - iOS：客户端授权 `login()` → `openid + access_token`
/// - 鸿蒙：QQ 鸿蒙版 SDK **只支持服务端授权** `loginServerSide()` → `openid + authCode`
///   （SDK 把 authCode 放在 `accessToken` 字段里返回，不能当客户端 token 用，
///   需要服务端用 `appId + appKey` 按官方「通过 Authorization Code 获取 Access Token」
///   接口换取，`redirect_uri` 一般为 `auth://tauth.qq.com/`）
///
/// 前置条件：
/// 1. QQ 互联后台登记的应用包名 / Bundle ID / 签名与当前构建一致；
/// 2. `pubspec.yaml` 顶部 `tencent_kit.app_id`、[Constants.qqAppId]、
///    鸿蒙 `module.json5` 回调 `skills.uris[].host` 三处一致；
/// 3. 鸿蒙需在 `module.json5` 的 `querySchemes` 中加入 `qqopenapi`，
///    并配置 `skills.uris = {scheme: 'qqopenapi', host: <AppID>, path: 'auth', linkFeature: 'Login'}`。
class QqLoginService {
  /// 授权模式开关
  ///
  /// 服务端确认「能处理 authorization code」后，把这里改成 [QqAuthMode.serverSide]，
  /// 三端即可统一走 code（鸿蒙本来就是该模式）；默认 clientSide，保持 Android/iOS
  /// 现有能力（服务端直接拿 access_token 换用户资料）。
  ///
  /// ⚠️ 鸿蒙不受此开关影响：QQ 鸿蒙版 SDK 只有服务端授权，代码里强制 serverSide。
  static QqAuthMode authMode = QqAuthMode.clientSide;

  /// 等待授权结果的超时时间（用户可能长时间停留在 QQ 授权页）
  static const Duration _loginTimeout = Duration(minutes: 5);

  /// 当前平台是否支持 QQ 登录（Android / iOS / 鸿蒙）
  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isOhos;

  /// 是否已向 SDK 注册（registerApp 只需一次）
  static bool _registered = false;

  /// 拉起 QQ 授权登录
  ///
  /// 返回统一结构：
  /// - 成功：`{'status': true, 'data': {'openId', 'code', 'serverSide'}, 'msg': '登录成功'}`
  ///   - `code`：clientSide 模式为 `access_token`，serverSide 模式为 `authorization code`
  /// - 用户取消：`{'status': false, 'msg': '已取消 QQ 登录', 'canceled': true}`
  /// - 失败：`{'status': false, 'msg': String, 'canceled': false}`
  static Future<Map<String, dynamic>> login() async {
    if (!isSupported) {
      return _failure('当前平台暂不支持 QQ 登录');
    }
    if (!await _ensureRegistered()) {
      return _failure('QQ 登录初始化失败，请稍后重试');
    }

    // 鸿蒙 SDK 只实现了服务端授权，其余平台按 [authMode] 走
    final bool serverSide =
        Platform.isOhos || authMode == QqAuthMode.serverSide;

    final Completer<TencentLoginResp> completer = Completer<TencentLoginResp>();
    StreamSubscription<TencentResp>? subscription;

    try {
      // 先订阅再拉起授权，避免回调先于订阅到达（鸿蒙回调走 onNewWant，同样有竞态）
      subscription = TencentKitPlatform.instance.respStream().listen(
        (TencentResp resp) {
          if (resp is TencentLoginResp && !completer.isCompleted) {
            completer.complete(resp);
          }
        },
      );

      if (serverSide) {
        // 服务端授权：scope 用 get_user_info（服务端拿 code 换到 token 后要读用户资料）
        await TencentKitPlatform.instance.loginServerSide(
          scope: <String>[TencentScope.kGetUserInfo],
        );
      } else {
        // 客户端授权：移动端最小权限，足够登录换 token
        await TencentKitPlatform.instance.login(
          scope: <String>[TencentScope.kGetSimpleUserInfo],
        );
      }

      // 用户取消/成功都会回调；超时兜底避免按钮一直不可点
      final TencentLoginResp resp =
          await completer.future.timeout(_loginTimeout);

      if (resp.isCancelled) {
        return <String, dynamic>{
          'status': false,
          'data': null,
          'msg': '已取消 QQ 登录',
          'canceled': true,
        };
      }
      if (!resp.isSuccessful) {
        final String msg = resp.msg?.trim() ?? '';
        print('QQ 授权失败 ret=${resp.ret} msg=$msg');
        return _failure(msg.isEmpty ? 'QQ 授权失败，请重试' : msg);
      }

      final String openId = resp.openid ?? '';
      // serverSide 模式下这里是 authorization code（SDK 复用 accessToken 字段）
      final String code = resp.accessToken ?? '';
      if (code.isEmpty) {
        print('QQ 授权未返回凭证 openId=$openId serverSide=$serverSide');
        return _failure('未获取到 QQ 授权凭证，请重试');
      }
      print('QQ 登录成功 openId=$openId serverSide=$serverSide');

      return <String, dynamic>{
        'status': true,
        'data': <String, dynamic>{
          'openId': openId,
          'code': code,
          'serverSide': serverSide,
        },
        'msg': '登录成功',
        'canceled': false,
      };
    } on TimeoutException {
      return _failure('QQ 授权超时，请重试');
    } on PlatformException catch (e) {
      print('QQ 登录失败 code=${e.code} msg=${e.message}');
      return _failure(e.message ?? 'QQ 登录失败，请重试');
    } on MissingPluginException {
      // 未注册插件（如尚未集成 tencent_kit 的构建版本）
      return _failure('当前版本暂不支持 QQ 登录，请升级后重试');
    } catch (e) {
      print('QQ 登录异常: $e');
      return _failure('QQ 登录失败，请重试');
    } finally {
      await subscription?.cancel();
    }
  }

  /// 向 QQ SDK 注册 AppID（只需成功一次）
  ///
  /// ⚠️ 腾讯 SDK 3.3.1+ 要求：`registerApp` 之前必须先声明已获得隐私授权
  /// （`setIsPermissionGranted`），否则登录会失败。
  static Future<bool> _ensureRegistered() async {
    if (_registered) return true;
    try {
      await TencentKitPlatform.instance.setIsPermissionGranted(granted: true);
      await TencentKitPlatform.instance.registerApp(appId: Constants.qqAppId);
      _registered = true;
      return true;
    } catch (e) {
      print('QQ SDK 注册失败: $e');
      return false;
    }
  }

  static Map<String, dynamic> _failure(String msg) {
    return <String, dynamic>{
      'status': false,
      'data': null,
      'msg': msg,
      'canceled': false,
    };
  }
}
