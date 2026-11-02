import 'dart:async';

import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';

class EventReportService {
  static final EventReportService _instance = EventReportService._internal();
  factory EventReportService() => _instance;
  EventReportService._internal();

  static const String _eventPath = '/data-collection/v1/handle';
  static const String _resourceReadPath =
      '/target-goods/app/v1/resource/read';

  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();

  void reportScanCode({
    String? prefixCode,
    String? suffixCode,
    String? goodsId,
    String? shopId,
  }) {
    _reportEvent(<String, dynamic>{
      'data_type': 2,
      'prefix_code': prefixCode,
      'suffix_code': suffixCode,
      'goods_id': goodsId,
      'shop_id': shopId,
    });
  }

  void reportMediaRead({
    String? goodsId,
    String? shopId,
    String? targetId,
    String? targetType,
    required int durationMilliseconds,
  }) {
    _reportEvent(<String, dynamic>{
      'data_type': 0,
      'goods_id': goodsId,
      'shop_id': shopId,
      'target_id': targetId,
      'target_type': targetType,
      'times_diff': durationMilliseconds.toString(),
    });
  }

  void reportDownload({
    String? goodsId,
    String? shopId,
    String? targetId,
    String? targetType,
  }) {
    _reportEvent(<String, dynamic>{
      'data_type': 1,
      'goods_id': goodsId,
      'shop_id': shopId,
      'target_id': targetId,
      'target_type': targetType,
    });
  }

  void reportUserRegister() {
    _reportEvent(<String, dynamic>{'data_type': 8});
  }

  void reportApplePay({
    String? goodsId,
    String? shopId,
    String? targetId,
    String? targetType,
    String? prefixCode,
    String? suffixCode,
    required String price,
  }) {
    _reportEvent(<String, dynamic>{
      'data_type': 3,
      'goods_id': goodsId,
      'shop_id': shopId,
      'target_id': targetId,
      'target_type': targetType,
      'prefix_code': prefixCode,
      'suffix_code': suffixCode,
      'pay_platform': 'flipay',
      'price': price,
    });
  }

  void reportResourceRead({
    required String goodsId,
    required String resourceId,
  }) {
    if (goodsId.isEmpty || resourceId.isEmpty) {
      print('资源阅读上报缺少 goodsId 或 resourceId');
      return;
    }
    unawaited(_sendResourceRead(goodsId, resourceId));
  }

  void _reportEvent(Map<String, dynamic> event) {
    unawaited(_sendEvent(event));
  }

  Future<void> _sendEvent(Map<String, dynamic> event) async {
    await _userService.refreshToken();
    final Map<String, dynamic> payload = Map<String, dynamic>.from(event)
      ..removeWhere((String key, dynamic value) =>
          value == null || (value is String && value.isEmpty));

    final userInfo = await _userService.getUserInfo();
    if (userInfo != null) {
      _addIfNotEmpty(payload, 'unification_id', userInfo.unificationId);
      _addIfNotEmpty(payload, 'user_id', userInfo.userId);
      _addIfNotEmpty(payload, 'consumer_phone', userInfo.phoneNumber);
      _addIfNotEmpty(payload, 'consumer_id', userInfo.userId);
    }

    payload['create_time'] = DateTime.now().millisecondsSinceEpoch;
    payload['device_id'] = await DeviceInfoUtil.getDeviceId();

    final Map<String, dynamic> result =
        await _apiService.post(_eventPath, data: payload);
    if (result['status'] != true) {
      print('事件上报失败: ${result['msg']}');
    }
  }

  Future<void> _sendResourceRead(String goodsId, String resourceId) async {
    await _userService.refreshToken();
    final Map<String, dynamic> payload = <String, dynamic>{
      'goodsId': goodsId,
      'resourceId': resourceId,
    };
    final String unificationId = await _userService.getUnificationId();
    _addIfNotEmpty(payload, 'unificationId', unificationId);

    final Map<String, dynamic> result = await _apiService.post(
      _resourceReadPath,
      data: payload,
      queryParameters: payload,
    );
    if (result['status'] != true) {
      print('资源阅读上报失败: ${result['msg']}');
    }
  }

  void _addIfNotEmpty(
      Map<String, dynamic> payload, String key, String value) {
    if (value.isNotEmpty) payload[key] = value;
  }
}
