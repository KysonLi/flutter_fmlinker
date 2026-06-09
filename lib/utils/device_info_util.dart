import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class DeviceInfoUtil {
  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  static const String _kDeviceIdKey = 'device_id';

  /// 获取设备唯一ID（稳定且唯一）
  static Future<String> getDeviceId() async {
    try {
      // 先从本地存储获取
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString(_kDeviceIdKey);
      
      if (deviceId != null) {
        return deviceId;
      }

      // 如果没有，生成新的设备ID
      deviceId = await _generateDeviceId();
      
      // 保存到本地存储
      await prefs.setString(_kDeviceIdKey, deviceId);
      
      return deviceId;
    } catch (e) {
      // 异常情况下生成随机ID
      return _generateRandomId();
    }
  }

  /// 生成设备ID
  static Future<String> _generateDeviceId() async {
    try {
      // 根据不同平台获取设备信息
      if (await _isAndroid()) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        // 使用Android ID（需要注意：某些设备可能会有相同的Android ID）
        // 为了增加唯一性，我们结合其他信息
        String androidId = androidInfo.id ;
        String model = androidInfo.model ;
        String manufacturer = androidInfo.manufacturer ;
        return _hashString('$androidId-$model-$manufacturer');
      } else if (await _isIOS()) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        // 使用identifierForVendor（需要注意：卸载重装后会改变）
        // 为了增加稳定性，我们结合其他信息
        String identifierForVendor = iosInfo.identifierForVendor ?? '';
        String model = iosInfo.model ;
        String name = iosInfo.name ;
        return _hashString('$identifierForVendor-$model-$name');
      } else {
        // 其他平台生成随机ID
        return _generateRandomId();
      }
    } catch (e) {
      // 异常情况下生成随机ID
      return _generateRandomId();
    }
  }

  /// 生成随机ID
  static String _generateRandomId() {
    final random = Random();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 对字符串进行哈希处理
  static String _hashString(String input) {
    // 使用简单的哈希算法，实际项目中可以使用更复杂的算法
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = input.codeUnitAt(i) + ((hash << 5) - hash);
    }
    String result = '';
    for (int i = 0; i < 8; i++) {
      int value = (hash >> (i * 4)) & 0xF;
      result += value.toRadixString(16);
    }
    return result;
  }

  /// 获取设备名称
  static Future<String> getDeviceName() async {
    try {
      if (await _isAndroid()) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        return androidInfo.model ;
      } else if (await _isIOS()) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.name ;
      } else {
        return 'Unknown Device';
      }
    } catch (e) {
      return 'Unknown Device';
    }
  }

  /// 获取设备型号
  static Future<String> getDeviceModel() async {
    try {
      if (await _isAndroid()) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        return androidInfo.model ;
      } else if (await _isIOS()) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.model ;
      } else {
        return 'Unknown Model';
      }
    } catch (e) {
      return 'Unknown Model';
    }
  }

  /// 获取设备系统版本
  static Future<String> getSystemVersion() async {
    try {
      if (await _isAndroid()) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        return androidInfo.version.release ;
      } else if (await _isIOS()) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.systemVersion ;
      } else {
        return 'Unknown Version';
      }
    } catch (e) {
      return 'Unknown Version';
    }
  }

  /// 检查是否为Android平台
  static Future<bool> _isAndroid() async {
    try {
      await _deviceInfoPlugin.androidInfo;
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// 检查是否为iOS平台
  static Future<bool> _isIOS() async {
    try {
      await _deviceInfoPlugin.iosInfo;
      return true;
    } on PlatformException {
      return false;
    }
  }
}
