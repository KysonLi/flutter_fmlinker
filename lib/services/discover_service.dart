import 'package:fmlink/services/api_service.dart';

class DiscoverService {
  static final DiscoverService _instance = DiscoverService._internal();
  factory DiscoverService() => _instance;

  final ApiService _apiService = ApiService();

  DiscoverService._internal();

  // 获取发现页面数据
  Future<Map<String, dynamic>> getDiscoverData() async {
    return await _apiService
        .get('/target-goods/app/v1/goods/find', queryParameters: {
      'adType': 'FIND',
    });
  }
}
