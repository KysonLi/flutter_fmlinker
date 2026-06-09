import 'dart:convert';
import 'package:dio/dio.dart' as dio;
import 'package:fmlink/common/constants.dart';
import 'package:fmlink/models/user_info.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/utils/device_info_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final ApiService _apiService = ApiService();
  UserInfo? _cachedUserInfo;

  // 检查登录状态
  Future<bool> checkLoginStatus() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString(Constants.kToken);
      return token != null && token.isNotEmpty;
    } catch (e) {
      print('检查登录状态失败: $e');
      return false;
    }
  }

  // 获取用户信息
  Future<UserInfo?> getUserInfo() async {
    try {
      if (_cachedUserInfo != null) {
        return _cachedUserInfo;
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userInfoStr = prefs.getString(Constants.kUserInfo);
      
      if (userInfoStr == null || userInfoStr.isEmpty) {
        return null;
      }

      Map<String, dynamic> userInfoMap = jsonDecode(userInfoStr);
      UserInfo userInfo = UserInfo.fromJson(userInfoMap);
      _cachedUserInfo = userInfo;
      return userInfo;
    } catch (e) {
      print('获取用户信息失败: $e');
      return null;
    }
  }

  // 获取UnificationId
  Future<String> getUnificationId() async {
    try {
      UserInfo? userInfo = await getUserInfo();
      return userInfo?.unificationId ?? '';
    } catch (e) {
      print('获取UnificationId失败: $e');
      return '';
    }
  }

  // 获取Token
  Future<String?> getToken() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString(Constants.kToken);
    } catch (e) {
      print('获取Token失败: $e');
      return null;
    }
  }

  // 刷新Constants.token
  Future<void> refreshToken() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString(Constants.kToken);
      if (token != null && token.isNotEmpty) {
        Constants.token = token;
        print('刷新Token成功: ${token.substring(0, 10)}...');
      }
    } catch (e) {
      print('刷新Token失败: $e');
    }
  }

  // 保存用户信息
  Future<bool> saveUserInfo(UserInfo userInfo) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String userInfoStr = jsonEncode(userInfo.toJson());
      await prefs.setString(Constants.kUserInfo, userInfoStr);
      _cachedUserInfo = userInfo;
      return true;
    } catch (e) {
      print('保存用户信息失败: $e');
      return false;
    }
  }

  // 保存Token
  Future<bool> saveToken(String token) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(Constants.kToken, token);
      Constants.token = token;
      return true;
    } catch (e) {
      print('保存Token失败: $e');
      return false;
    }
  }

  // 清除用户信息（退出登录）
  Future<bool> clearUserInfo() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(Constants.kToken);
      await prefs.remove(Constants.kUserInfo);
      await prefs.remove(Constants.kUserId);
      Constants.token = '';
      _cachedUserInfo = null;
      return true;
    } catch (e) {
      print('清除用户信息失败: $e');
      return false;
    }
  }

  // 获取脱敏手机号
  Future<String> getMaskedPhone() async {
    try {
      UserInfo? userInfo = await getUserInfo();
      String phone = userInfo?.phoneNumber ?? '';
      if (phone.length >= 11) {
        return '${phone.substring(0, 3)}****${phone.substring(7)}';
      }
      return phone;
    } catch (e) {
      print('获取脱敏手机号失败: $e');
      return '';
    }
  }

  // 获取用户昵称
  Future<String> getNickName() async {
    try {
      UserInfo? userInfo = await getUserInfo();
      return userInfo?.nickName ?? '用户';
    } catch (e) {
      print('获取用户昵称失败: $e');
      return '用户';
    }
  }

  // 是否已设置用户名
  Future<bool> hasSetUserName() async {
    try {
      UserInfo? userInfo = await getUserInfo();
      return userInfo?.hasSetUserName ?? false;
    } catch (e) {
      print('获取hasSetUserName失败: $e');
      return false;
    }
  }

  // 设置用户名
  Future<bool> setUserName(String userName) async {
    try {
      UserInfo? userInfo = await getUserInfo();
      if (userInfo == null || userInfo.userId.isEmpty) {
        print('用户未登录');
        return false;
      }

      String deviceId = await DeviceInfoUtil.getDeviceId();

      Map<String, dynamic> result = await _apiService.post(
        '/chain-server/api/link_code_system/login/change_user_name',
        data: {
          'userId': userInfo.userId,
          'userName': userName,
          'deviceId': deviceId,
        },
      );

      if (result['status'] == true) {
        Map<String, dynamic>? data = result['data'];
        if (data != null) {
          UserInfo newUserInfo = UserInfo.fromJson(data);
          await saveUserInfo(newUserInfo);
        }
        return true;
      } else {
        String error = result['message'] ?? '设置失败';
        print('设置用户名失败: $error');
        return false;
      }
    } catch (e) {
      print('设置用户名失败: $e');
      return false;
    }
  }

  // 获取头像URL
  Future<String> getAvatarUrl() async {
    try {
      UserInfo? userInfo = await getUserInfo();
      return userInfo?.avatarUrl ?? '';
    } catch (e) {
      print('获取头像URL失败: $e');
      return '';
    }
  }

  // 上传头像
  Future<bool> uploadAvatar(String imagePath) async {
    try {
      UserInfo? userInfo = await getUserInfo();
      if (userInfo == null || userInfo.unificationId.isEmpty) {
        print('用户未登录或unificationId为空');
        return false;
      }

      await refreshToken();

      String unificationId = userInfo.unificationId;
      String deviceId = await DeviceInfoUtil.getDeviceId();

      String timestamp = DateTime.now().toString().replaceAll(RegExp(r'[^0-9]'), '');
      String fileName = '${unificationId}_$timestamp.jpg';

      dio.FormData formData = dio.FormData.fromMap({
        'imageFile': await dio.MultipartFile.fromFile(
          imagePath,
          filename: fileName,
        ),
      });

      String url = '/target-goods/app/v1/image/upload?unificationId=$unificationId&deviceId=$deviceId';
      
      Map<String, dynamic> result = await _apiService.upload(url, formData);

      if (result['status'] == true) {
        Map<String, dynamic>? data = result['data'];
        if (data != null) {
          UserInfo newUserInfo = UserInfo.fromJson(data);
          await saveUserInfo(newUserInfo);
        }
        return true;
      } else {
        String error = result['message'] ?? '上传失败';
        print('上传头像失败: $error');
        return false;
      }
    } catch (e) {
      print('上传头像失败: $e');
      return false;
    }
  }

  // 发送短信验证码
  Future<Map<String, dynamic>> sendSmsCode(String phone, String type) async {
    try {
      Map<String, dynamic> result = await _apiService.get(
        '/chain-server/api/link_code_system/login/send_code',
        queryParameters: {
          'phone': phone,
          'type': type,
        },
      );
      return result;
    } catch (e) {
      print('发送验证码失败: $e');
      return {'status': false, 'msg': '发送失败'};
    }
  }

  // 注销账户
  Future<Map<String, dynamic>> deleteAccount(String code, String password) async {
    try {
      await refreshToken();

      UserInfo? userInfo = await getUserInfo();
      if (userInfo == null) {
        return {'status': false, 'msg': '用户未登录'};
      }

      String deviceId = await DeviceInfoUtil.getDeviceId();

      Map<String, dynamic> result = await _apiService.post(
        '/chain-server/api/link_code_system/login/delete_account',
        data: {
          'userId': userInfo.userId,
          'deviceId': deviceId,
          'verificationCode': code,
          'password': password,
        },
      );
      return result;
    } catch (e) {
      print('注销账户失败: $e');
      return {'status': false, 'msg': '注销失败'};
    }
  }
}