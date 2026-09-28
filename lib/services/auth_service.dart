import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/models/user_info.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();

  AuthService._internal();

  // 获取验证码
  Future<Map<String, dynamic>> getVerificationCode(
      String phoneNumber, String type) async {
    return await _apiService.post(
        '/chain-server/api/link_code_system/login/get_verification_code',
        data: {
          'phoneNumber': phoneNumber,
          'type': type,
        });
  }

  // 手机验证码登录
  Future<Map<String, dynamic>> loginWithSms(String phoneNumber,
      String verificationCode, String deviceId, String deviceName) async {
    Map<String, dynamic> result = await _apiService.post(
        '/chain-server/api/link_code_system/login/v2/login_with_verification_code',
        data: {
          'phoneNumber': phoneNumber,
          'verificationCode': verificationCode,
          'deviceId': deviceId,
          'deviceName': deviceName,
        });

    await _handleLoginResult(result);
    return result;
  }

  // 账号密码登录
  Future<Map<String, dynamic>> loginWithPassword(String phoneNumber,
      String password, String deviceId, String deviceName) async {
    Map<String, dynamic> result = await _apiService.post(
        '/chain-server/api/link_code_system/login/v2/login_with_account',
        data: {
          'account': phoneNumber,
          'password': password,
          'deviceId': deviceId,
          'deviceName': deviceName,
        });

    await _handleLoginResult(result);
    return result;
  }

  // 第三方登录
  Future<Map<String, dynamic>> loginWithThirdParty(String platform,
      String? openId, String code, String deviceId, String deviceName) async {
    Map<String, dynamic> result = await _apiService
        .post('/chain-server/api/link_code_system/login/v2/third_party', data: {
      'platform': platform,
      'openId': openId,
      'code': code,
      'deviceId': deviceId,
      'deviceName': deviceName,
    });

    await _handleLoginResult(result);
    return result;
  }

  // 南方云平台登录（账号密码格式，返回处理与账号密码登录一致）
  Future<Map<String, dynamic>> loginWithSouthCloud(String userName,
      String password, String deviceId, String deviceName) async {
    Map<String, dynamic> result = await _apiService
        .post('/chain-server/api/link_code_system/login/login_spm', data: {
      'userName': userName,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
    });

    await _handleLoginResult(result);
    return result;
  }

  // 登出
  //
  // 不关心服务端登出接口的成功/失败：调用后一律执行本地登出。
  // - 顺序：**先**请求服务端（要带上当前 token），再清本地登录信息；
  //   反之（先清 token）会让登出请求变成匿名请求，服务端无法注销该会话。
  // - 容错：ApiService 不抛异常（失败只返回 status=false），故无需 try/catch；
  //   即便请求超时/断网，本地登录态也照常清除。
  Future<void> logout() async {
    // 忽略返回值：服务端注销失败不影响本地登出
    await _apiService.post('/chain-server/api/link_code_system/logout');

    await _userService.clearUserInfo();
    // 缓存元数据按账号隔离：退出后立即切回未登录视角（文件本体保留供后续账号复用）
    await CacheService().syncAccount();
  }

  // 处理登录结果
  Future<void> _handleLoginResult(Map<String, dynamic> result) async {
    if (result['status'] == true) {
      Map<String, dynamic>? data = result['data'];
      if (data != null) {
        UserInfo userInfo = UserInfo.fromJson(data);
        await _userService.saveUserInfo(userInfo);

        String? token = data['token'];
        if (token != null) {
          await _userService.saveToken(token);
        }

        await _userService.getUserInfo();
        // 缓存元数据按账号隔离：登录后立即加载该账号的缓存状态
        await CacheService().syncAccount();
      }
    }
  }
}
