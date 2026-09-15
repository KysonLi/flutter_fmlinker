import 'package:flutter/services.dart';

/// 网络类型
enum NetworkType {
  wifi, // WiFi 环境
  cellular, // 移动网络
  none, // 无网络
  unknown, // 未知/获取失败
}

/// 网络信息工具
///
/// 通过自定义 MethodChannel `fmlink/network_info` 获取当前网络类型，
/// 三端原生实现：
/// - Android：ConnectivityManager.getNetworkCapabilities
/// - iOS：NWPathMonitor
/// - OHOS：@ohos.net.connection（getDefaultNet + getConnectionProperties）
class NetworkInfoUtil {
  static const MethodChannel _channel = MethodChannel('fmlink/network_info');

  /// 获取当前网络类型
  static Future<NetworkType> getNetworkType() async {
    try {
      final String? type =
          await _channel.invokeMethod<String>('getNetworkType');
      switch (type) {
        case 'wifi':
          return NetworkType.wifi;
        case 'cellular':
          return NetworkType.cellular;
        case 'none':
          return NetworkType.none;
        default:
          return NetworkType.unknown;
      }
    } catch (e) {
      print('获取网络类型失败: $e');
      return NetworkType.unknown;
    }
  }

  /// 是否 WiFi 环境
  static Future<bool> isWifi() async {
    return await getNetworkType() == NetworkType.wifi;
  }

  /// 是否移动网络
  static Future<bool> isCellular() async {
    return await getNetworkType() == NetworkType.cellular;
  }
}
