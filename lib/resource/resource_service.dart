import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';

/// 资源播放模块接口封装
///
/// 统一口径（与后端约定）：
/// - isliCode 传【去连字符后的纯数字】（如扫码/其它入口进来先 replaceAll('-','')）
/// - unificationId 未登录默认传 deviceId
/// - hasScanUse：由扫码界面进入传 'false'，其它页面传 'true'
/// - orderBy 默认 ORDER_BY_PUBLISH_TIME
class ResourceService {
  static final ResourceService _instance = ResourceService._internal();
  factory ResourceService() => _instance;

  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();

  ResourceService._internal();

  /// ISLI 编码去连字符/空白 → 纯数字
  String isliDigits(String code) {
    return code.replaceAll(RegExp(r'\D'), '');
  }

  /// 解析请求使用的 unificationId：登录取用户 unificationId，否则取 deviceId
  Future<String> resolveUnificationId() async {
    final String uid = await _userService.getUnificationId();
    if (uid.isNotEmpty) return uid;
    return DeviceInfoUtil.getDeviceId();
  }

  /// 拉取链码资源数据
  ///
  /// [isliCode] 完整 ISLI 编码（可带连字符，内部归一为纯数字）
  /// [fromScan] 是否由扫码界面进入（决定 hasScanUse）
  /// 返回 ApiService 统一结果 {status, data, msg}
  Future<Map<String, dynamic>> fetchSourceScan(
    String isliCode, {
    int pageIndex = 1,
    int pageSize = 20,
    String? orderBy,
    bool fromScan = false,
    String? unificationId,
    String? versionCode,
  }) async {
    final String code = isliDigits(isliCode);
    final String finalUid = unificationId ?? await resolveUnificationId();
    final Map<String, dynamic> query = <String, dynamic>{
      'pageIndex': pageIndex.toString(),
      'pageSize': pageSize.toString(),
      'orderBy': orderBy ?? 'ORDER_BY_PUBLISH_TIME',
      'hasScanUse': fromScan ? 'false' : 'true',
      'unificationId': finalUid,
    };
    if (versionCode != null && versionCode.isNotEmpty) {
      query['versionCode'] = versionCode;
    }
    return _apiService.get(
      '/target-goods/app/v1/source/scan/$code',
      queryParameters: query,
    );
  }

  /// 整书购买优惠/已购减免：/target-goods/app/v1/derate-goods/:unificationId/:goodsId
  ///
  /// data.deratePrice：已购源减免金额（整书价中扣除）
  /// data.identifier：出版物标识（生成支付订单用 goods_identifier）
  Future<Map<String, dynamic>> fetchDerateGoods(
    String goodsId, {
    String? unificationId,
    int? versionCode,
    String? sourceIdentifier,
  }) async {
    final String finalUid = unificationId ?? await resolveUnificationId();
    return PublishService().fetchDeratePrice(
      finalUid,
      goodsId,
      versionCode: versionCode,
      sourceIdentifier: sourceIdentifier,
    );
  }

  /// 标志码版权信息：/pics/v1/isliContents/:mprCode
  ///
  /// 该接口与主业务（:11999）端口不同，走 https 完整 URL。
  Future<Map<String, dynamic>> fetchIsliContents(String mprCode) async {
    final String code = mprCode.trim();
    return _apiService.get(
      'https://apigateway.mpreader.com/pics/v1/isliContents/$code',
    );
  }
}
