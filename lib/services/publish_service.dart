import 'package:fmlink/services/api_service.dart';

class PublishService {
  static final PublishService _instance = PublishService._internal();
  factory PublishService() => _instance;

  final ApiService _apiService = ApiService();

  PublishService._internal();

  // ==================== 支付下单参数 ====================

  /// 下单接口固定参数（App 端取值）
  ///
  /// 小程序端为 pay_type=4 / payService='pay.jsapi' /
  /// payCode='weixin.wx.chaincode' / platform=2，App 端按后端要求改为下列取值。
  static const int payTypeApp = 1;
  static const String payServiceApp = 'APP';
  static const String payCodeWechatApp = 'weixin.app.chaincode';
  static const int platformApp = 0;

  /// 整书购买时 source_id 的固定取值
  static const String wholePublicationSourceId = 'WHOLE_PUBLICATION';

  /// 下单接口 resultCode
  ///
  /// 88888805/88888812 表示服务端已处理完成（已购买 / 支付成功），
  /// 无需再拉起微信支付。
  static const String payResultSuccess = '00000000';
  static const String payResultAlreadyOwned = '88888805';
  static const String payResultPaid = '88888812';
  static const String payResultUnauthorized = '44444444';

  // 获取出版物列表（searchText 可选，传则搜索）
  Future<Map<String, dynamic>> getPublications(
      {int page = 1, int pageSize = 20, String? searchText}) async {
    final queryParameters = <String, dynamic>{
      'pageIndex': page,
      'pageSize': pageSize,
    };
    if (searchText != null && searchText.isNotEmpty) {
      queryParameters['searchText'] = searchText;
    }
    return await _apiService.get('/target-goods/app/v1/goods',
        queryParameters: queryParameters);
  }

  // 获取出版者列表（searchText 可选，传则搜索）
  Future<Map<String, dynamic>> getPublishers(
      {int page = 1, int pageSize = 20, String? searchText}) async {
    final queryParameters = <String, dynamic>{
      'pageIndex': page,
      'pageSize': pageSize,
    };
    if (searchText != null && searchText.isNotEmpty) {
      queryParameters['searchText'] = searchText;
    }
    return await _apiService.get('/target-goods/app/v1/publications',
        queryParameters: queryParameters);
  }

  // 获取出版物详情
  Future<Map<String, dynamic>> getPublicationDetail(String goodsId) async {
    return await _apiService.get('/target-goods/app/v1/goods/$goodsId');
  }

  // 获取出版者详情
  Future<Map<String, dynamic>> getPublisherDetail(String publisherId) async {
    return await _apiService
        .get('/target-goods/app/v1/publications', queryParameters: {
      'shopId': publisherId,
    });
  }

  // 获取指定出版者的出版物列表
  Future<Map<String, dynamic>> getPublicationsByShopId(String shopId,
      {int page = 1, int pageSize = 20}) async {
    return await _apiService
        .get('/target-goods/app/v1/goods', queryParameters: {
      'pageIndex': page.toString(),
      'pageSize': pageSize.toString(),
      'shopId': shopId,
    });
  }

  // 获取出版物更新记录
  Future<Map<String, dynamic>> getPublicationUpdateRecord(
      String goodsId) async {
    return await _apiService.get('/target-goods/app/v1/goods/history/$goodsId');
  }

  // 获取出版物链码列表
  Future<Map<String, dynamic>> getPublicationSourceList(
    String serviceCode,
    String prefixCode, {
    int versionCode = 1,
    int page = 1,
    int pageSize = 20,
    String? article,
    String? chapter,
    String? unificationId,
  }) async {
    Map<String, dynamic> params = {
      'versionCode': versionCode.toString(),
      'pageIndex': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (article != null) params['article'] = article;
    if (chapter != null) params['chapter'] = chapter;
    if (unificationId != null) params['unificationId'] = unificationId;
    return await _apiService.get(
        '/target-goods/app/v1/source/$serviceCode/$prefixCode',
        queryParameters: params);
  }

  // 获取优惠出版物
  Future<Map<String, dynamic>> getDiscountPublications() async {
    return await _apiService.get('/target-goods/app/v1/derate-goods');
  }

  // 获取已购源减免金额（购买页展示整书优惠时调用）
  // data.deratePrice：已购买过的源的价格，整书购买时需从整书价中减免
  // data.identifier：出版物标识，生成支付订单时作为 goods_identifier 使用
  Future<Map<String, dynamic>> fetchDeratePrice(
    String unificationId,
    String goodsId, {
    int? versionCode,
    String? sourceIdentifier,
  }) async {
    Map<String, dynamic> queryParameters = {};
    if (versionCode != null) {
      queryParameters['versionCode'] = versionCode.toString();
    }
    if (sourceIdentifier != null && sourceIdentifier.isNotEmpty) {
      queryParameters['sourceIdentifier'] = sourceIdentifier;
    }
    return await _apiService.get(
      '/target-goods/app/v1/derate-goods/$unificationId/$goodsId',
      queryParameters: queryParameters,
    );
  }

  // 获取购买记录（/pos/v1/order/target）
  // userId 对应登录后的 unificationId；分页参数 key 名固定为 page/pageCount
  Future<Map<String, dynamic>> getPurchaseOrders({
    required String userId,
    int page = 1,
    int pageCount = 20,
  }) async {
    return await _apiService.get('/pos/v1/order/target', queryParameters: {
      'userId': userId,
      'page': page,
      'pageCount': pageCount,
    });
  }

  /// 生成支付订单（对应小程序端 createPayOrder）
  ///
  /// POST /pos/v1/app/pay
  ///
  /// 固定参数（App）：pay_type=1、payService='APP'、
  /// payCode='weixin.app.chaincode'、platform=0
  ///
  /// 返回归一化结果，其中 `resultCode` 为服务端原始返回码：
  /// - 00000000：成功，data 为微信支付参数
  /// - 88888805：已购买 / 88888812：支付成功（服务端已处理完成，无需再拉起微信支付）
  /// - 44444444：登录过期或未登录
  Future<Map<String, dynamic>> createPayOrder({
    required String unificationId,
    required String goodsId,
    String? shopId,
    String? sourceId,
    String? goodsIdentifier,
    String payCode = payCodeWechatApp,
  }) async {
    // 入参 key 沿用小程序端下单接口约定（snake_case）
    final Map<String, dynamic> body = <String, dynamic>{
      'unification_id': unificationId,
      'goods_id': goodsId,
      'pay_type': payTypeApp,
      'payService': payServiceApp,
      'payCode': payCode,
      'platform': platformApp,
    };
    if (shopId != null && shopId.isNotEmpty) body['shop_id'] = shopId;
    if (sourceId != null && sourceId.isNotEmpty) body['source_id'] = sourceId;
    if (goodsIdentifier != null && goodsIdentifier.isNotEmpty) {
      body['goods_identifier'] = goodsIdentifier;
    }

    return await _apiService.post('/pos/v1/app/pay', data: body);
  }
}
