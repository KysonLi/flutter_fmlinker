import 'package:fmlink/services/api_service.dart';

class PublishService {
  static final PublishService _instance = PublishService._internal();
  factory PublishService() => _instance;

  final ApiService _apiService = ApiService();

  PublishService._internal();

  // 获取出版物列表
  Future<Map<String, dynamic>> getPublications({int page = 1, int pageSize = 20}) async {
    return await _apiService.get('/target-goods/app/v1/goods', queryParameters: {
      'pageIndex': page,
      'pageSize': pageSize,
    });
  }

  // 获取出版者列表
  Future<Map<String, dynamic>> getPublishers({int page = 1, int pageSize = 20}) async {
    return await _apiService.get('/target-goods/app/v1/publications', queryParameters: {
      'pageIndex': page,
      'pageSize': pageSize,
    });
  }

  // 获取出版物详情
  Future<Map<String, dynamic>> getPublicationDetail(String goodsId) async {
    return await _apiService.get('/target-goods/app/v1/goods/$goodsId');
  }

  // 获取出版者详情
  Future<Map<String, dynamic>> getPublisherDetail(String publisherId) async {
    return await _apiService.get('/target-goods/app/v1/publications', queryParameters: {
      'shopId': publisherId,
    });
  }

  // 获取指定出版者的出版物列表
  Future<Map<String, dynamic>> getPublicationsByShopId(String shopId, {int page = 1, int pageSize = 20}) async {
    return await _apiService.get('/target-goods/app/v1/goods', queryParameters: {
      'pageIndex': page.toString(),
      'pageSize': pageSize.toString(),
      'shopId': shopId,
    });
  }

  // 获取出版物更新记录
  Future<Map<String, dynamic>> getPublicationUpdateRecord(String goodsId) async {
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
    return await _apiService.get('/target-goods/app/v1/source/$serviceCode/$prefixCode', queryParameters: params);
  }

  // 获取优惠出版物
  Future<Map<String, dynamic>> getDiscountPublications() async {
    return await _apiService.get('/target-goods/app/v1/derate-goods');
  }
}