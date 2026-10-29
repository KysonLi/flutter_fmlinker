import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fmlink/models/prepay_product.dart';

/// 泛票档位配置：productId 由代码写死（与 AGC / App Store Connect 配置的商品一致）
///
/// 泛票数只是**本地兜底值**：商店不返回泛票数，档位文案优先用商店返回的商品名，
/// 商店没返回商品名时才用它拼「N泛票」；实际入账泛票数由服务端校验凭证后决定。
///
/// ⚠️ 两平台的商品档位**不完全对应**：同一档位的泛票数可能不同
/// （如 iOS `com.fanmeilinker.fanpiao6` = 198，鸿蒙 `fanpiao_188_188` = 188），故按平台分别配置。
class IapProductConfig {
  const IapProductConfig({
    required this.iosTickets,
    required this.ohosTickets,
    required this.iosProductId,
    required this.ohosProductId,
  });

  /// iOS 商品对应的泛票数量（兜底展示/兜底价格用，App Store Connect 上的档位）
  final double iosTickets;

  /// 鸿蒙商品对应的泛票数量（兜底展示/兜底价格用，AGC 上的档位）
  final double ohosTickets;

  /// iOS（App Store Connect）商品 ID
  final String iosProductId;

  /// 鸿蒙（AGC）商品 ID
  final String ohosProductId;

  /// 当前平台的商品 ID
  String get productId => Platform.isOhos ? ohosProductId : iosProductId;

  /// 当前平台的泛票数量
  double get tickets => Platform.isOhos ? ohosTickets : iosTickets;
}

/// 泛票内购服务（iOS / 鸿蒙）
///
/// 商品列表**不依赖服务端**：productId 写死在 [products]，由平台商店查询商品与本地化价格：
/// - iOS：StoreKit `SKProductsRequest`（工程部署目标 iOS 12，未用 StoreKit 2 的 `Product.products`）
///   → 原生实现见 `ios/Runner/AppDelegate.swift`
/// - 鸿蒙：IAP Kit `iap.queryProducts`（`@kit.IAPKit`）→ 原生实现见
///   `ohos/entry/src/main/ets/iap/IapPlugin.ets`
///
/// 通道名 `fmlink/iap`，方法：
/// - `queryProducts`（入参 `productIds`）→ `{'data': [{productId, name, price, displayPrice, currency}]}`
/// - `buyProduct`（入参 `productId`）→ 鸿蒙 `{productId, purchaseData}`（JSON 字符串）/ iOS `{productId, transactionId, receipt}`
/// - `finishPurchase`（入参 `purchaseToken`、`purchaseOrderId`，仅鸿蒙消耗型商品需要）→ `true`
class IapService {
  static const MethodChannel _channel = MethodChannel('fmlink/iap');

  /// 用户取消支付的错误码（鸿蒙 1001860000、iOS SKError.paymentCancelled 都映射成它）
  static const String _codeUserCanceled = 'USER_CANCELED';

  /// 该商品已有未完成的支付（华为 1001860051）
  ///
  /// 出现这个错误码说明华为侧还有该商品**已付款但未发货**的订单（常见于上次入账失败），
  /// 应先走充值补发而不是提示用户重复购买。
  static const String codeAlreadyOwned = 'ALREADY_OWNED';

  /// 商品信息无效（华为 1001860003：商品不存在或未上架）
  static const String _codeInvalidProduct = 'INVALID_PRODUCT';

  /// 当前平台是否支持泛票内购（Android 走微信支付，不用本通道）
  static bool get isSupported => Platform.isIOS || Platform.isOhos;

  /// 泛票档位（productId 与商店后台配置一一对应，顺序即页面展示顺序）
  ///
  /// ⚠️ 改动档位需同时改 App Store Connect / AGC 的商品配置，否则商店查不到该商品（会被跳过）。
  /// ⚠️ 两个平台的泛票数并非一一对应，改价/改档位时务必分别核对两侧商店的配置。
  static const List<IapProductConfig> products = <IapProductConfig>[
    IapProductConfig(
      iosTickets: 6,
      ohosTickets: 6,
      iosProductId: 'com.fanmeilinker.fanpiao.1',
      ohosProductId: 'fanpiao_6_6',
    ),
    IapProductConfig(
      iosTickets: 18,
      ohosTickets: 18,
      iosProductId: 'com.fanmeilinker.fanpiao.2',
      ohosProductId: 'fanpiao_18_18',
    ),
    IapProductConfig(
      iosTickets: 30,
      ohosTickets: 30,
      iosProductId: 'com.fanmeilinker.fanpiao3',
      ohosProductId: 'fanpiao_30_30',
    ),
    IapProductConfig(
      iosTickets: 50,
      ohosTickets: 50,
      iosProductId: 'com.fanmeilinker.fanpiao4',
      ohosProductId: 'fanpiao_50_50',
    ),
    IapProductConfig(
      iosTickets: 98,
      ohosTickets: 98,
      iosProductId: 'com.fanmeilinker.fanpiao5',
      ohosProductId: 'fanpiao_98_98',
    ),
    // iOS 该档位为 198 泛票，鸿蒙为 188 泛票
    IapProductConfig(
      iosTickets: 198,
      ohosTickets: 188,
      iosProductId: 'com.fanmeilinker.fanpiao6',
      ohosProductId: 'fanpiao_188_188',
    ),
  ];

  /// 查询商店商品
  ///
  /// 返回统一结构：`{'status': bool, 'data': List<PrepayProduct>, 'msg': String}`
  /// - 只返回商店确实配置了（能查到）的商品；未配置的档位直接跳过，避免用户点到无法下单的档位
  /// - `price` 用商店返回的数值，`displayPrice` 用商店本地化价格文案
  ///
  /// ⚠️ 鸿蒙 `iap.queryProducts` 的批量查询对无效商品不宽容：productIds 里只要有一个在 AGC
  /// 不存在或未上架，整次调用就可能整批失败（`INVALID_PRODUCT` / 1001860003），一个商品都拿不到。
  /// 另外该错误码也可能是**账号**问题：非沙盒测试账号看不到「未上架」的商品（实测：应用/商品
  /// 未上架时必须用 AGC 配置的沙盒测试账号登录 AppGallery）。
  /// 因此批量查询失败时降级为逐个查询，跳过无效商品、保留有效档位。
  static Future<Map<String, dynamic>> queryProducts() async {
    if (!isSupported) {
      return _failure('当前平台暂不支持泛票充值');
    }

    final List<String> productIds =
        products.map((IapProductConfig p) => p.productId).toList();
    print('查询泛票商品 productIds=$productIds');

    try {
      final dynamic result = await _channel.invokeMethod<dynamic>(
        'queryProducts',
        <String, dynamic>{'productIds': productIds},
      );

      final List<PrepayProduct> list = _parseStoreProducts(result);
      if (list.isEmpty) {
        print('商店未返回任何泛票商品: $result');
        return _failure('未获取到充值商品，请稍后重试');
      }
      print('商店返回泛票商品 ${list.length} 个');
      return <String, dynamic>{
        'status': true,
        'data': list,
        'msg': 'ok',
      };
    } on MissingPluginException {
      // 未注册原生通道（如尚未集成内购的构建版本）
      return _failure('当前版本暂不支持充值，请升级后重试');
    } on PlatformException catch (e) {
      print('查询充值商品失败 code=${e.code} msg=${e.message} details=${e.details}');
      // 商品信息无效（某档位在 AGC 不存在/未上架）时逐个重试，避免一个坏档位拖垮整页
      if (Platform.isOhos && e.code == _codeInvalidProduct) {
        final List<PrepayProduct> list =
            await _queryProductsOneByOne(productIds);
        if (list.isNotEmpty) {
          print('逐个查询后返回泛票商品 ${list.length} 个');
          return <String, dynamic>{
            'status': true,
            'data': list,
            'msg': 'ok',
          };
        }
        // 全部查不到时，联调期最常见的原因是账号：未上架的商品只有沙盒测试账号可见
        print('提示：鸿蒙 1001860003 也可能是账号问题——未上架的商品只有 AGC 沙盒测试账号可见，'
            '请确认手机上的华为账号已加入 AGC 沙盒测试名单');
      }
      return _failure(e.message ?? '获取充值商品失败，请稍后重试', code: e.code);
    } catch (e) {
      print('查询充值商品异常: $e');
      return _failure('获取充值商品失败，请稍后重试');
    }
  }

  /// 逐个查询商品（批量查询失败时的降级方案）
  ///
  /// 只用于鸿蒙：某个 productId 在 AGC 无效会拖垮整批查询，逐个查可以拿到其余有效档位；
  /// 无效的 productId 会打印出来，方便和 AGC 后台核对。
  static Future<List<PrepayProduct>> _queryProductsOneByOne(
    List<String> productIds,
  ) async {
    final List<PrepayProduct> list = <PrepayProduct>[];
    final List<String> invalid = <String>[];
    for (final String productId in productIds) {
      try {
        final dynamic result = await _channel.invokeMethod<dynamic>(
          'queryProducts',
          <String, dynamic>{
            'productIds': <String>[productId],
          },
        );
        final List<PrepayProduct> parsed = _parseStoreProducts(result);
        if (parsed.isEmpty) {
          invalid.add(productId);
        } else {
          list.addAll(parsed);
        }
      } on PlatformException catch (e) {
        print('商品 $productId 查询失败 code=${e.code} msg=${e.message}');
        invalid.add(productId);
      }
    }
    if (invalid.isNotEmpty) {
      print('商店查不到的商品（请检查 AGC 商品 ID 与上架状态）: $invalid');
    }
    return list;
  }

  /// 拉起平台内购（购买单个泛票商品）
  ///
  /// 返回统一结构：`{'status': bool, 'data': Map, 'msg': String, 'canceled': bool}`
  /// - 成功时 `data` 含：`productId`、`purchaseToken` / `purchaseOrderId`（鸿蒙 IAP Kit）、
  ///   `transactionId` / `receipt`（iOS StoreKit）——由 `PrepayService.verifyPurchase` 交给服务端验证入账
  /// - 用户取消时 `status=false` 且 `canceled=true`（调用方静默处理，不弹错误提示）
  static Future<Map<String, dynamic>> purchase(String productId) async {
    if (!isSupported) {
      return _failure('当前平台暂不支持泛票充值');
    }

    try {
      final dynamic result = await _channel.invokeMethod<dynamic>(
        'buyProduct',
        <String, dynamic>{'productId': productId},
      );
      print('内购支付原始返回: $result');

      final Map<String, dynamic> data = _parsePurchaseResult(productId, result);
      print('内购支付结果: $data');

      // 凭证校验：鸿蒙必须有 purchaseToken（服务端验证华为订单用），iOS 至少有交易号
      if ((data['purchaseToken']?.toString() ?? '').isEmpty &&
          (data['transactionId']?.toString() ?? '').isEmpty) {
        return _failure('支付结果异常，请稍后在充值记录中查看');
      }

      return <String, dynamic>{
        'status': true,
        'data': data,
        'msg': 'ok',
      };
    } on MissingPluginException {
      // 未注册原生通道（如尚未集成内购的构建版本）
      return _failure('当前版本暂不支持充值，请升级后重试');
    } on PlatformException catch (e) {
      print('内购支付失败 code=${e.code} msg=${e.message} details=${e.details}');
      if (e.code == _codeUserCanceled) {
        return <String, dynamic>{
          'status': false,
          'data': null,
          'msg': '已取消支付',
          'canceled': true,
        };
      }
      // 带上错误码：ALREADY_OWNED 需要走充值补发而不是提示重复购买
      return _failure(e.message ?? '充值失败，请稍后重试', code: e.code);
    } catch (e) {
      print('内购支付异常: $e');
      return _failure('充值失败，请稍后重试');
    }
  }

  /// 结束交易（鸿蒙消耗型商品的发货确认）
  ///
  /// ⚠️ 按充值对接文档，订单**发货确认由服务端完成**（服务端验证 + confirm），
  /// 正常流程客户端无需调用；这里保留作为服务端未确认发货时的补救手段。
  /// iOS 由原生在交易完成时 `finishTransaction`，这里空跑。
  static Future<Map<String, dynamic>> finishPurchase({
    required String purchaseToken,
    required String purchaseOrderId,
  }) async {
    if (!Platform.isOhos) {
      return <String, dynamic>{'status': true, 'data': null, 'msg': 'ok'};
    }
    if (purchaseToken.isEmpty || purchaseOrderId.isEmpty) {
      return _failure('缺少订单凭证，无法确认交易');
    }

    try {
      await _channel.invokeMethod<dynamic>('finishPurchase', <String, dynamic>{
        'purchaseToken': purchaseToken,
        'purchaseOrderId': purchaseOrderId,
      });
      return <String, dynamic>{'status': true, 'data': null, 'msg': 'ok'};
    } on MissingPluginException {
      return _failure('当前版本暂不支持充值，请升级后重试');
    } on PlatformException catch (e) {
      print('结束交易失败 code=${e.code} msg=${e.message} details=${e.details}');
      return _failure(e.message ?? '充值确认失败，请稍后在充值记录中查看');
    } catch (e) {
      print('结束交易异常: $e');
      return _failure('充值确认失败，请稍后在充值记录中查看');
    }
  }

  /// 查询华为侧的已购订单——充值补发用
  ///
  /// 用于覆盖「本地没存下凭据」的情况（旧版本、换机、请求发出前崩溃、服务端当时验证失败
  /// 而未落库）。返回统一结构：`{'status': bool, 'data': List<Map>, 'msg': String}`，
  /// 每项：`{productId, purchase_token, purchase_order_id}`。
  ///
  /// - `queryType = 1`（默认，UNFINISHED）：已支付但未发货/未完成的订单
  /// - `queryType = 0`（ALL）：全部已购订单（兵底用；华为侧状态与预期不一致时靠它找回）
  ///
  /// iOS 无对应机制（StoreKit 队列由原生处理），直接返回空列表。
  static Future<Map<String, dynamic>> queryPendingPurchases(
      {int queryType = 1}) async {
    if (!Platform.isOhos) {
      return <String, dynamic>{
        'status': true,
        'data': <Map<String, dynamic>>[],
        'msg': 'ok',
      };
    }

    try {
      final dynamic result = await _channel.invokeMethod<dynamic>(
        'queryPendingPurchases',
        <String, dynamic>{'queryType': queryType},
      );
      print('华为已购订单原始返回(queryType=$queryType): $result');
      final List<Map<String, dynamic>> list =
          _parsePendingPurchases(result, queryType: queryType);
      print('华为未完成订单 ${list.length} 条(queryType=$queryType)');
      return <String, dynamic>{
        'status': true,
        'data': list,
        'msg': 'ok',
      };
    } on MissingPluginException {
      return _failure('当前版本暂不支持充值，请升级后重试');
    } on PlatformException catch (e) {
      print('查询未完成订单失败 code=${e.code} msg=${e.message} details=${e.details}');
      return _failure(e.message ?? '查询未完成订单失败，请稍后重试');
    } catch (e) {
      print('查询未完成订单异常: $e');
      return _failure('查询未完成订单失败，请稍后重试');
    }
  }

  /// 解析已购订单列表
  ///
  /// 原生返回 `purchaseDataList`（每项为订单 JSON 字符串）。不同版本可能是订单本体，
  /// 也可能是 `{purchaseData: "<json>", signature: ...}` 包装，两种都兼容，
  /// 统一取出 `purchaseToken` / `purchaseOrderId`（字段名多命名兼容）。
  static List<Map<String, dynamic>> _parsePendingPurchases(
    dynamic result, {
    int queryType = 1,
  }) {
    dynamic raw = result;
    if (raw is Map && raw['data'] != null) raw = raw['data'];
    if (raw is! List) return <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
    for (final dynamic item in raw) {
      final Map<String, dynamic> data = _decodePurchaseItem(item);
      if (data.isEmpty) continue;
      final String purchaseToken =
          _pickValue(data, const <String>['purchaseToken', 'purchase_token']);
      if (purchaseToken.isEmpty) {
        // 排查用：字段名与预期不一致时能看到原始订单
        print('订单缺少 purchaseToken，已跳过(queryType=$queryType): $data');
        continue;
      }
      list.add(<String, dynamic>{
        'productId':
            _pickValue(data, const <String>['productId', 'product_id']),
        'purchase_token': purchaseToken,
        'purchase_order_id': _pickValue(data, const <String>[
          'purchaseOrderId',
          'purchase_order_id',
          'orderId',
          'order_id',
        ]),
        'purchase_state':
            _pickValue(data, const <String>['purchaseState', 'purchase_state']),
      });
    }
    return list;
  }

  /// 订单项解码：兼容三种结构
  ///
  /// 1. 订单本体 JSON 字符串（`createPurchase` 的 `purchaseData` 是这种）；
  /// 2. `{purchaseData: "<json>", signature: ...}` 包装；
  /// 3. `{type: 0, jwsPurchaseOrder: "<JWS>"}` —— **`queryPurchases` 实测返回的是这种**，
  ///    JWS = `header.payload.signature`（base64url），订单数据在 payload 里
  ///    （含 purchaseOrderId / purchaseToken / productId / purchaseTime）。
  static Map<String, dynamic> _decodePurchaseItem(dynamic item) {
    dynamic value = item;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (e) {
        // 不是 JSON，可能本身就是一段 JWS 字符串
        final String payload = _decodeJwsPayload(value.toString());
        if (payload.isEmpty) {
          print('解析未完成订单失败: $e');
          return <String, dynamic>{};
        }
        value = payload;
      }
    }
    if (value is! Map) return <String, dynamic>{};
    final Map<String, dynamic> map = Map<String, dynamic>.from(value);

    // 3) JWS 包装：解开 payload 与外层合并
    final dynamic jws = map['jwsPurchaseOrder'];
    if (jws is String && jws.isNotEmpty) {
      final dynamic decoded = _decodeJwsPayload(jws);
      if (decoded is Map) {
        return <String, dynamic>{...map, ...Map<String, dynamic>.from(decoded)};
      }
      print('解析 jwsPurchaseOrder 失败，原始长度=${jws.length}');
    }

    // 2) purchaseData 包装
    final dynamic inner = map['purchaseData'];
    if (inner is String && inner.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(inner);
        if (decoded is Map) {
          return <String, dynamic>{
            ...map,
            ...Map<String, dynamic>.from(decoded),
          };
        }
      } catch (e) {
        print('解析订单 purchaseData 失败: $e');
      }
    }
    return map;
  }

  /// 解开 JWS 的 payload 段（base64url 编码的订单 JSON）
  static dynamic _decodeJwsPayload(String jws) {
    if (jws.isEmpty) return null;
    final List<String> parts = jws.split('.');
    if (parts.length < 2) return null;

    // base64url → base64（补齐 padding）
    String payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    final int remainder = payload.length % 4;
    if (remainder > 0) payload += '=' * (4 - remainder);

    try {
      return jsonDecode(utf8.decode(base64Decode(payload)));
    } catch (e) {
      print('解析 JWS payload 失败: $e');
      return null;
    }
  }

  /// 按多命名取第一个非空值
  static String _pickValue(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  /// 解析原生支付结果
  ///
  /// - 鸿蒙：`IapPlugin.buyProduct` 返回 `{productId, purchaseData}`，`purchaseData` 是 JSON
  ///   字符串（含 purchaseToken / purchaseOrderId / purchaseState 等），这里解析后与外层合并
  /// - iOS：`IapPurchaseManager` 返回 `{productId, transactionId, receipt}`
  ///
  /// 服务端字段名尚未最终确认，取值做多命名兼容，联调后再收敛。
  static Map<String, dynamic> _parsePurchaseResult(
      String productId, dynamic result) {
    dynamic raw = result;
    if (raw is Map && raw['data'] is Map) raw = raw['data'];
    final Map<String, dynamic> outer =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    final Map<String, dynamic> merged = <String, dynamic>{...outer};
    final String purchaseData = outer['purchaseData']?.toString() ?? '';
    if (purchaseData.isNotEmpty) {
      dynamic decoded;
      try {
        decoded = jsonDecode(purchaseData);
      } catch (e) {
        // 新版 IAP Kit 的 createPurchase 也返回 JWS（header.payload.signature），
        // 不是明文 JSON，解开 payload 再取字段
        decoded = _decodeJwsPayload(purchaseData);
        if (decoded is! Map) {
          print('解析 purchaseData 失败(非 JSON 非 JWS): $e');
        }
      }
      if (decoded is Map) {
        merged.addAll(Map<String, dynamic>.from(decoded));
      }
    }

    final String parsedProductId =
        _pickValue(merged, const <String>['productId', 'product_id']);
    return <String, dynamic>{
      'productId': parsedProductId.isEmpty ? productId : parsedProductId,
      'purchaseToken':
          _pickValue(merged, const <String>['purchaseToken', 'purchase_token']),
      'purchaseOrderId': _pickValue(merged, const <String>[
        'purchaseOrderId',
        'purchase_order_id',
        'orderId',
        'order_id',
      ]),
      'transactionId': _pickValue(merged, const <String>[
        'transactionId',
        'transaction_id',
        'transactionIdentifier',
      ]),
      'receipt': _pickValue(merged, const <String>['receipt', 'receiptBase64']),
    };
  }

  /// 把原生返回的商品列表映射为 [PrepayProduct]（按 [products] 配置顺序）
  static List<PrepayProduct> _parseStoreProducts(dynamic result) {
    // 兼容 {'data': [...]} 与直接返回数组两种结构
    dynamic raw = result;
    if (raw is Map && raw['data'] is List) raw = raw['data'];
    if (raw is! List) return <PrepayProduct>[];

    final Map<String, Map<String, dynamic>> storeById =
        <String, Map<String, dynamic>>{};
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(item);
      final String id = map['productId']?.toString() ?? '';
      if (id.isNotEmpty) storeById[id] = map;
    }

    final List<PrepayProduct> list = <PrepayProduct>[];
    for (final IapProductConfig config in products) {
      final Map<String, dynamic>? store = storeById[config.productId];
      if (store == null) {
        print('商店未配置商品 ${config.productId}（${config.tickets}泛票），已跳过');
        continue;
      }
      final num price = _toNum(store['price']);
      list.add(PrepayProduct(
        productId: config.productId,
        name: store['name']?.toString() ?? '',
        tickets: config.tickets,
        // 商店价格取不到时退回配置金额（1元=1泛票）
        price: price > 0 ? price : config.tickets,
        displayPrice: store['displayPrice']?.toString() ?? '',
      ));
    }
    return list;
  }

  static num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic> _failure(String msg, {String code = ''}) {
    return <String, dynamic>{
      'status': false,
      'data': <PrepayProduct>[],
      'msg': msg,
      'code': code,
    };
  }
}
