import 'dart:io' show Platform;

import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/iap_service.dart';
import 'package:fmlink/services/prepay_pending_store.dart';
import 'package:fmlink/services/user_service.dart';

/// 泛票充值（预付费）服务
///
/// 接口基址 `/pos/v1/prepay`（见 `docs/华为应用内支付IAP充值对接文档.md` v1.0）。
/// 商品列表不在这里：档位的 productId 写死在 `IapService`（iOS/鸿蒙），价格由平台商店查询。
///
/// 余额 / 充值记录**按平台独立账户**：`platform=1` iOS、`platform=3` 华为（鸿蒙），
/// 华为充的钱只在华为下单时扣。
///
/// ⚠️ 充值验证（入账）按平台分两套接口，参数完全不同，勿混用（见 [verifyPurchase]）：
/// - iOS：`POST /pos/v1/prepay/prepay_ios_v2`（receipt / unification_id / transaction_id）
/// - 鸿蒙：`POST /pos/v1/prepay/prepay_huawei`（unification_id / purchase_token / purchase_order_id，三个均必填）
class PrepayService {
  static final PrepayService _instance = PrepayService._internal();
  factory PrepayService() => _instance;
  PrepayService._internal();

  final ApiService _apiService = ApiService();

  static const String _base = '/pos/v1/prepay';

  // ==================== 业务码（见对接文档 2.2 / 2.3） ====================

  /// 成功
  static const String resultSuccess = '00000000';

  /// 华为支付凭证已验证（重复提交，幂等命中）——同样按成功处理
  static const String resultHuaweiVerified = '88888822';

  /// 华为支付验证失败（可重试：凭据留本地待补发）
  static const String resultHuaweiVerifyFailed = '88888821';

  /// 获取华为服务端凭证失败（服务端配置问题，可重试）
  static const String resultHuaweiAcsFailed = '88888823';

  /// 华为充值商品不存在（商品配置不一致，不可重试）
  static const String resultHuaweiProductNotFound = '88888824';

  /// 华为订单状态非已购买（含沙盒单在线上被拒、已退款，不可重试）
  static const String resultHuaweiOrderInvalid = '88888825';

  /// 参数错误（不可重试）
  static const String resultParamError = 'POS-000600021';

  /// 系统异常（可重试）
  static const String resultSystemError = '01111111';

  /// 未充值过（该平台账户无充值记录）→ 余额按 0 处理
  static const String resultNotRecharged = '88888804';

  /// 可重试的业务码：服务端未入账，凭据留本地等补发
  static const List<String> retryableCodes = <String>[
    resultHuaweiVerifyFailed,
    resultHuaweiAcsFailed,
    resultSystemError,
  ];

  /// 入账是否成功（幂等命中 [resultHuaweiVerified] 也算成功）
  static bool isVerifySuccess(dynamic resultCode) {
    final String code = resultCode?.toString() ?? '';
    return code == resultSuccess || code == resultHuaweiVerified;
  }

  /// 失败结果是否值得重试
  ///
  /// - 业务码在 [retryableCodes] 内 → 可重试（服务端未入账）
  /// - 根本没拿到业务码（网络异常 / token 过期，`_handleResponse` 会给空 resultCode）→ 也可重试
  /// - 其余业务码（商品不存在、订单状态非法、参数错误）→ 重试无意义
  static bool isRetryable(dynamic resultCode) {
    final String code = resultCode?.toString() ?? '';
    if (code.isEmpty) return true;
    return retryableCodes.contains(code);
  }

  /// 当前设备的平台标识：1 = iOS，3 = 华为（鸿蒙）；余额与充值记录都按它区分账户
  static int get platform => Platform.isOhos ? 3 : 1;

  /// iOS 充值验证 + 入账
  static const String _iosVerifyPath = '$_base/prepay_ios_v2';

  /// 鸿蒙（华为）充值验证 + 入账
  static const String _ohosVerifyPath = '$_base/prepay_huawei';

  /// 用户泛票余额（按平台独立账户）
  ///
  /// GET `/pos/v1/prepay/total_balance?unification_id=xxx&platform=N`
  /// - `platform`：1 = iOS，3 = 华为（鸿蒙）
  /// - 成功：余额取 `data.total_amount`（单位元）
  /// - `88888804` / `POS-000600014`：该平台账户无充值记录 → 按 0 处理，仍算成功
  Future<Map<String, dynamic>> getTotalBalance(String unificationId) async {
    final Map<String, dynamic> response = await _apiService.get(
      '$_base/total_balance',
      queryParameters: <String, dynamic>{
        'unification_id': unificationId,
        'platform': platform,
      },
    );

    final String code = response['resultCode']?.toString() ?? '';
    if (code == resultNotRecharged || code == 'POS-000600014') {
      // 未充值：服务端没有余额记录，按 0 展示（不当作错误）
      return <String, dynamic>{
        'status': true,
        'data': <String, dynamic>{'total_amount': '0'},
        'msg': 'ok',
        'resultCode': code,
      };
    }
    return response;
  }

  /// 充值记录（仅已入账记录，倒序）
  ///
  /// GET `/pos/v1/prepay/prepay_record?unification_id=xxx&platform=N`
  /// ⚠️ 对接文档未定义分页参数，一次返回全部记录（客户端不做翻页）。
  Future<Map<String, dynamic>> getPrepayRecords({
    required String unificationId,
  }) async {
    return await _apiService.get(
      '$_base/prepay_record',
      queryParameters: <String, dynamic>{
        'unification_id': unificationId,
        'platform': platform,
      },
    );
  }

  // ==================== 充值验证（验证 + 入账） ====================
  //
  // 参考流程：平台内购（iOS StoreKit / 鸿蒙 IAP Kit）拉起支付 → 拿到交易凭证
  // → 调对应平台接口验证并入账 → 重新拉取余额（total_balance）。
  // Android 走微信支付，不使用这里的泛票充值接口。

  /// 充值验证 + 入账（iOS）
  ///
  /// POST `/chain-server/api/link_code_system/prepay/prepay_ios_v2`
  /// body 与 iOS 端实现一致：`receipt`（App Store 收据 base64）、`unification_id`、
  /// `transaction_id`（StoreKit 交易号）——服务端拿到收据向苹果校验后再入账。
  Future<Map<String, dynamic>> prepayIosV2({
    required String unificationId,
    required String receipt,
    required String transactionId,
  }) async {
    return await _apiService.post(
      _iosVerifyPath,
      data: <String, dynamic>{
        'receipt': receipt,
        'unification_id': unificationId,
        'transaction_id': transactionId,
      },
    );
  }

  /// 充值验证 + 入账（鸿蒙 / 华为应用市场内购）——**底层调用，业务请用 [verifyHuaweiPurchase]**
  ///
  /// POST `/pos/v1/prepay/prepay_huawei`（三个参数均必填）
  /// - `unification_id`：用户统一标识（`UserService.getUnificationId()`）
  /// - `purchase_token`：`iap.purchase` 返回的 `purchaseToken`
  /// - `purchase_order_id`：`iap.purchase` 返回的 `purchaseOrderId`
  ///
  /// 服务端以 `purchase_order_id` 幂等：同一订单重复提交只入账一次，第二次返回 `88888822`。
  Future<Map<String, dynamic>> prepayHuawei({
    required String unificationId,
    required String purchaseToken,
    required String purchaseOrderId,
  }) async {
    return await _apiService.post(
      _ohosVerifyPath,
      data: <String, dynamic>{
        'unification_id': unificationId,
        'purchase_token': purchaseToken,
        'purchase_order_id': purchaseOrderId,
      },
    );
  }

  /// 华为充值验证入账（含**凭据本地暂存 + 失败留待补发**，对接文档「客户端必做事项」）
  ///
  /// 流程：先把凭据写入本地 → 调服务端 → 成功后删除本地记录；
  /// 可重试的失败（见 [retryableCodes]、连接层错误）保留记录，由 [retryPendingHuawei] 补发。
  /// 返回值在归一化 map 上追加：`retryable`（是否已暂存待补发）、`pending`（同义，便于 UI 判断）。
  Future<Map<String, dynamic>> verifyHuaweiPurchase({
    required String unificationId,
    required String purchaseToken,
    required String purchaseOrderId,
  }) async {
    // 先落本地再请求：中途断网 / 崩溃也不会丢单（服务端幂等，可安全重试）
    await PrepayPendingStore.add(
      unificationId: unificationId,
      purchaseToken: purchaseToken,
      purchaseOrderId: purchaseOrderId,
    );

    final Map<String, dynamic> response = await prepayHuawei(
      unificationId: unificationId,
      purchaseToken: purchaseToken,
      purchaseOrderId: purchaseOrderId,
    );
    final String code = response['resultCode']?.toString() ?? '';

    if (isVerifySuccess(code)) {
      await PrepayPendingStore.remove(purchaseOrderId);
      return response;
    }

    final bool retryable = isRetryable(code);
    if (!retryable) {
      // 参数错误 / 商品不存在 / 订单状态非法：重试也没用，清掉本地凭据
      await PrepayPendingStore.remove(purchaseOrderId);
    } else {
      print('华为充值未入账 resultCode=$code，凭据已暂存待补发 orderId=$purchaseOrderId');
    }

    return <String, dynamic>{
      ...response,
      'retryable': retryable,
      'pending': retryable,
    };
  }

  /// 充值补发（App 启动 / 进入充值页 / 购买遇 ALREADY_OWNED 时调用），返回本次成功入账的笔数
  ///
  /// 覆盖三种「已付款但没入账」的情况，保证用户不丢单：
  /// 1. 本地暂存的凭据（[PrepayPendingStore]）——上次验证失败时留下的；
  /// 2. **华为侧「已支付未发货」订单**（`iap.queryPurchases`，UNFINISHED）；
  /// 3. `deep = true` 时再查**全部已购订单**（ALL）兜底——用于华为侧状态与预期不一致
  ///    （例如订单已被确认发货、但服务端尚未入账）的场景。
  ///
  /// 服务端按 `purchase_order_id` 幂等，重复提交只会入账一次，补发是安全的。
  Future<int> recoverHuaweiPurchases({bool deep = false}) async {
    // 华为内购专属；iOS 由 StoreKit 队列自行重放未完成交易
    if (!Platform.isOhos) return 0;

    // 冷启动后 Constants.token 可能为空，先水合；未登录无法入账
    final String token = await UserService().getToken() ?? '';
    if (token.isEmpty) return 0;
    await UserService().refreshToken();
    final String unificationId = await UserService().getUnificationId();
    if (unificationId.isEmpty) return 0;

    // 汇总待补发凭据：本地暂存 + 华为侧未完成订单（按订单号去重，华为侧数据更权威）
    final Map<String, Map<String, dynamic>> merged =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> item in await PrepayPendingStore.all()) {
      final String orderId = item['purchase_order_id']?.toString() ?? '';
      if (orderId.isNotEmpty) merged[orderId] = item;
    }

    // 先查「已支付未发货」订单（常规）；没查到且要求深查时，再查全部已购订单兜底
    final List<int> queryTypes = deep ? <int>[1, 0] : <int>[1];
    for (final int queryType in queryTypes) {
      final Map<String, dynamic> queried =
          await IapService.queryPendingPurchases(queryType: queryType);
      if (queried['status'] != true) {
        print('查询华为订单失败(queryType=$queryType): ${queried['msg']}');
        continue;
      }

      final List<dynamic> items = queried['data'] as List<dynamic>;
      for (final dynamic raw in items) {
        if (raw is! Map) continue;
        final Map<String, dynamic> item = Map<String, dynamic>.from(raw);
        final String orderId = item['purchase_order_id']?.toString() ?? '';
        final String purchaseToken = item['purchase_token']?.toString() ?? '';
        if (orderId.isEmpty || purchaseToken.isEmpty) continue;
        merged[orderId] = <String, dynamic>{
          'unification_id': unificationId,
          'purchase_token': purchaseToken,
          'purchase_order_id': orderId,
        };
      }

      // 未发货订单已能定位就不必再查全量
      if (items.isNotEmpty) break;
    }

    if (merged.isEmpty) return 0;
    print('开始补发华为充值凭据 ${merged.length} 条');

    int recovered = 0;
    for (final Map<String, dynamic> item in merged.values) {
      final String purchaseToken = item['purchase_token']?.toString() ?? '';
      final String purchaseOrderId =
          item['purchase_order_id']?.toString() ?? '';
      if (purchaseToken.isEmpty || purchaseOrderId.isEmpty) continue;

      // 复用正常入账流程：先落本地 → 调服务端 → 成功/不可重试时清除
      final Map<String, dynamic> response = await verifyHuaweiPurchase(
        unificationId: unificationId,
        purchaseToken: purchaseToken,
        purchaseOrderId: purchaseOrderId,
      );
      print('补发华为充值凭据 orderId=$purchaseOrderId '
          'resultCode=${response['resultCode']}');
      if (isVerifySuccess(response['resultCode'])) recovered++;
    }
    return recovered;
  }

  /// 充值验证统一入口：按平台分发
  ///
  /// - 鸿蒙 → [verifyHuaweiPurchase]（含本地暂存与补发）
  /// - iOS → [prepayIosV2]（服务端拿收据向苹果校验）
  Future<Map<String, dynamic>> verifyPurchase({
    required String unificationId,
    String receipt = '',
    String transactionId = '',
    String purchaseToken = '',
    String purchaseOrderId = '',
  }) async {
    if (Platform.isOhos) {
      if (purchaseToken.isEmpty || purchaseOrderId.isEmpty) {
        return <String, dynamic>{
          'status': false,
          'data': null,
          'msg': '缺少华为内购凭证，无法完成充值',
        };
      }
      return verifyHuaweiPurchase(
        unificationId: unificationId,
        purchaseToken: purchaseToken,
        purchaseOrderId: purchaseOrderId,
      );
    }

    if (receipt.isEmpty && transactionId.isEmpty) {
      return <String, dynamic>{
        'status': false,
        'data': null,
        'msg': '缺少苹果内购凭证，无法完成充值',
      };
    }
    return prepayIosV2(
      unificationId: unificationId,
      receipt: receipt,
      transactionId: transactionId,
    );
  }
}
