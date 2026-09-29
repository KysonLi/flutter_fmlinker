import 'dart:io';

import 'package:flutter/services.dart';

/// 华为账号登录服务（鸿蒙 OHOS 专用）
///
/// 通过自定义 MethodChannel `fmlink/huawei_account` 调用鸿蒙侧的
/// `@kit.AccountKit`（华为账号 Kit）实现「华为账号一键登录」：
/// - 用户已登录华为账号且已授权：静默返回凭证（无弹窗，即一键登录）
/// - 用户未登录：拉起华为账号登录页；用户取消返回 canceled=true
///
/// 原生实现：`ohos/entry/src/main/ets/huawei/HuaweiAccountPlugin.ets`
///
/// 前置条件（缺一不可，否则报 1001502002 应用未授权）：
/// 1. 在 AppGallery Connect 创建应用并开通「华为账号」服务；
/// 2. `ohos/entry/src/main/module.json5` 的 `metadata` 中配置 AGC 应用的 `client_id`；
/// 3. 调试/发布证书的包名（com.mpr.chaincode）与证书指纹已在 AGC 登记。
class HuaweiAccountService {
  static const MethodChannel _channel = MethodChannel('fmlink/huawei_account');

  /// 当前平台是否支持华为账号登录（仅鸿蒙）
  static bool get isSupported => Platform.isOhos;

  /// 拉起华为账号一键登录
  ///
  /// [forceLogin] 为 true 时，若用户未登录华为账号会拉起登录页；
  /// 为 false 时用户未登录将直接返回错误（用于静默登录场景）。
  ///
  /// 返回统一结构：
  /// - 成功：`{'status': true, 'data': {'authorizationCode', 'idToken', 'openID', 'unionID'}, 'msg': '登录成功'}`
  /// - 失败：`{'status': false, 'msg': String, 'canceled': bool}`
  static Future<Map<String, dynamic>> login({bool forceLogin = true}) async {
    if (!isSupported) {
      return _failure('当前平台暂不支持华为账号登录');
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'login',
        <String, dynamic>{'forceLogin': forceLogin},
      );

      if (result == null) {
        return _failure('华为账号登录失败，请重试');
      }

      final Map<String, dynamic> map = Map<String, dynamic>.from(result);
      // 原生侧返回 {'data': {authorizationCode, idToken, openID, unionID}}；
      // 同时兼容扁平结构（无 data 包裹），避免两端结构不一致时静默失败
      final rawData = map['data'];
      final Map<String, dynamic> data =
          rawData is Map ? Map<String, dynamic>.from(rawData) : map;

      // 没有 authorizationCode 就无法换登录态，直接按失败处理（避免上层拿到空值）
      final String code = data['authorizationCode']?.toString() ?? '';
      if (code.isEmpty) {
        print('华为账号登录未返回 authorizationCode: $map');
        return _failure('未获取到华为账号授权信息，请重试');
      }

      print('华为账号登录成功 openID=${data['openID']}');

      return <String, dynamic>{
        'status': true,
        'data': data,
        'msg': '登录成功',
        'canceled': false,
      };
    } on PlatformException catch (e) {
      // USER_CANCELED 由原生侧在用户取消授权时抛出，业务侧不再提示错误
      final bool canceled = e.code == 'USER_CANCELED';
      print('华为账号登录失败 code=${e.code} msg=${e.message} details=${e.details}');
      return <String, dynamic>{
        'status': false,
        'msg': canceled ? '已取消华为账号登录' : (e.message ?? '华为账号登录失败'),
        'canceled': canceled,
      };
    } on MissingPluginException {
      // 非鸿蒙构建或未注册插件（如 Android/iOS/HarmonyOS 老版本）
      return _failure('当前设备不支持华为账号登录');
    } catch (e) {
      print('华为账号登录异常: $e');
      return _failure('华为账号登录失败，请重试');
    }
  }

  static Map<String, dynamic> _failure(String msg) {
    return <String, dynamic>{
      'status': false,
      'msg': msg,
      'canceled': false,
    };
  }
}
