import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 华为充值凭据本地暂存（防丢单）
///
/// 对接文档《华为应用内支付IAP充值对接文档》要求：调用 `prepay_huawei` **之前**先把
/// `purchase_token + purchase_order_id + unification_id` 写入本地存储，服务端返回成功
/// （`00000000`）或幂等命中（`88888822`）后再删除；App 启动时遍历补发，保证用户不丢单。
///
/// 服务端按 `purchase_order_id` 幂等，重复提交只会入账一次，因此补发是安全的。
/// 存储结构：SharedPreferences 里一个 JSON 数组，每项：
/// `{unification_id, purchase_token, purchase_order_id, created_at}`
class PrepayPendingStore {
  static const String _key = 'prepay_pending_huawei';

  /// 暂存一条待补发的华为充值凭据（按 purchase_order_id 去重，重复写入直接覆盖）
  static Future<void> add({
    required String unificationId,
    required String purchaseToken,
    required String purchaseOrderId,
  }) async {
    if (unificationId.isEmpty ||
        purchaseToken.isEmpty ||
        purchaseOrderId.isEmpty) {
      // 缺字段的凭据补发不了，不写入，避免脏数据
      print('华为充值凭据不完整，未暂存: orderId=$purchaseOrderId');
      return;
    }
    try {
      final List<Map<String, dynamic>> items = await all();
      items.removeWhere((Map<String, dynamic> e) =>
          e['purchase_order_id'] == purchaseOrderId);
      items.add(<String, dynamic>{
        'unification_id': unificationId,
        'purchase_token': purchaseToken,
        'purchase_order_id': purchaseOrderId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await _save(items);
    } catch (e) {
      print('暂存华为充值凭据失败: $e');
    }
  }

  /// 读取全部待补发凭据
  static Future<List<Map<String, dynamic>>> all() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString(_key) ?? '';
      if (raw.isEmpty) return <Map<String, dynamic>>[];
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((Map e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('读取待补发充值凭据失败: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// 删除已入账（或确定无法入账）的凭据
  static Future<void> remove(String purchaseOrderId) async {
    if (purchaseOrderId.isEmpty) return;
    try {
      final List<Map<String, dynamic>> items = await all();
      items.removeWhere((Map<String, dynamic> e) =>
          e['purchase_order_id'] == purchaseOrderId);
      await _save(items);
    } catch (e) {
      print('清除待补发充值凭据失败: $e');
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> items) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }
}
