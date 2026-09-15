import 'package:fmlink/services/api_service.dart';

class LinkService {
  static final LinkService _instance = LinkService._internal();
  factory LinkService() => _instance;

  final ApiService _apiService = ApiService();

  LinkService._internal();

  // 获取商品扫码历史
  Future<Map<String, dynamic>> getGoodsScanHistory(String unificationId,
      {int page = 1, int pageSize = 20}) async {
    String path = '/target-goods/app/v1/goods/link/$unificationId';
    return await _apiService.get(path, queryParameters: {
      'pageIndex': page,
      'pageSize': pageSize,
    });
  }

  // 获取资源扫码历史
  Future<Map<String, dynamic>> getSourceScanHistory(
      {int page = 1, int pageSize = 20}) async {
    return await _apiService
        .get('/target-goods/app/v1/source/link', queryParameters: {
      'pageIndex': page,
      'pageSize': pageSize,
    });
  }

  // 根据ISLI编码获取资源
  Future<Map<String, dynamic>> getTargetsWithIsliCode(String isliCode) async {
    return await _apiService
        .get('/target-goods/app/v1/targets', queryParameters: {
      'isli_code': isliCode,
    });
  }

  // 根据ISLI编码获取多个资源
  Future<Map<String, dynamic>> getMultiTargetsWithIsliCode(
      String isliCode) async {
    return await _apiService.get(
        '/chain-server/api/link_code_system/multi_targetsAll',
        queryParameters: {
          'isli_code': isliCode,
        });
  }

  // 扫码获取资源（V2版本）
  Future<Map<String, dynamic>> getTargetsWithIsliCodeV2(String isliCode) async {
    return await _apiService
        .get('/target-goods/app/v1/source/scan', queryParameters: {
      'isli_code': isliCode,
    });
  }

  // 获取资源地址
  Future<Map<String, dynamic>> getResourcesAddress() async {
    return await _apiService.get('/target-goods/app/v1/resources-address');
  }

  // 根据前缀码获取章节
  Future<Map<String, dynamic>> getBookChapterWithPrefixCode(
      String prefixCode) async {
    return await _apiService
        .get('/target-goods/app/v1/targets/chapter', queryParameters: {
      'prefix_code': prefixCode,
    });
  }

  // 根据ISLI编码获取更多资源
  Future<Map<String, dynamic>> getSourceTargetsWithIsliCode(
      String isliCode) async {
    return await _apiService
        .get('/target-goods/app/v1/targets-more', queryParameters: {
      'isli_code': isliCode,
    });
  }

  // 删除商品关联记录
  Future<Map<String, dynamic>> deleteGoodsLink(
      String unificationId, String goodsIds) async {
    String path = '/target-goods/app/v1/goods/link/$unificationId';
    return await _apiService.delete(path, queryParameters: {
      'goodsIds': goodsIds,
    });
  }

  // 获取扫码历史记录
  Future<Map<String, dynamic>> getScanHistory(
    String unificationId, {
    String? goodsId,
    int pageIndex = 1,
    int pageSize = 20,
    String orderBy = 'ORDER_BY_LINK',
  }) async {
    String path = '/target-goods/app/v1/source/link/$unificationId';
    Map<String, dynamic> params = {
      'pageIndex': pageIndex,
      'pageSize': pageSize,
      'orderBy': orderBy,
    };
    if (goodsId != null && goodsId.isNotEmpty) {
      params['goodsId'] = goodsId;
    }
    return await _apiService.get(path, queryParameters: params);
  }

  // 删除扫码历史记录
  Future<Map<String, dynamic>> deleteScanHistory(
      String unificationId, String sourceIdentifiers) async {
    String path = '/target-goods/app/v1/source/link/$unificationId';
    return await _apiService.delete(path, queryParameters: {
      'sourceIdentifiers': sourceIdentifiers,
    });
  }
}
