import 'dart:io';

class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  
  late Map<String, Map<String, String>> _errorMap;
  
  ErrorHandler._internal() {
    _loadErrorStrings();
  }
  
  // 加载错误字符串配置
  void _loadErrorStrings() {
    try {
      // 读取FMErrorStrings.plist文件
      // TODO(清理): 以下为硬编码的个人 macOS 路径，在 Android/iOS/OHOS 上恒不存在，
      // 错误映射表实际从未生效；且 ErrorHandler 目前无调用方，可择机整体删除。
      final file = File('/Users/lilj/Desktop/Flutter/FMErrorStrings.plist');
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        _parsePlist(content);
      } else {
        _errorMap = {};
      }
    } catch (e) {
      print('Error loading FMErrorStrings.plist: $e');
      _errorMap = {};
    }
  }
  
  // 解析plist文件
  void _parsePlist(String content) {
    // 这里使用简单的解析方式，实际项目中可能需要使用更专业的plist解析库
    _errorMap = {};
    
    // 简单的XML解析逻辑
    final lines = content.split('\n');
    String? currentKey;
    Map<String, String>? currentError;
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine.startsWith('<key>') && trimmedLine.endsWith('</key>')) {
        final key = trimmedLine.substring(5, trimmedLine.length - 6);
        if (currentKey == null) {
          currentKey = key;
          currentError = {};
        } else {
          // 子键（cn或en）
          currentError?[key] = '';
        }
      } else if (trimmedLine.startsWith('<string>') && trimmedLine.endsWith('</string>')) {
        final value = trimmedLine.substring(8, trimmedLine.length - 9);
        if (currentError != null && currentError.isNotEmpty) {
          final subKey = currentError.keys.last;
          currentError[subKey] = value;
        }
      } else if (trimmedLine.startsWith('</dict>')) {
        if (currentKey != null && currentError != null) {
          _errorMap[currentKey] = currentError;
          currentKey = null;
          currentError = null;
        }
      }
    }
  }
  
  // 根据错误码获取错误信息
  String getErrorMessage(String errorCode) {
    if (_errorMap.containsKey(errorCode)) {
      // 默认返回中文错误信息
      return _errorMap[errorCode]?['cn'] ?? '未知错误';
    }
    return '未知错误';
  }
  
  // 统一处理API响应
  Map<String, dynamic> handleApiResponse(dynamic response, int? statusCode) {
    // 处理网络错误
    if (statusCode != null && (statusCode >= 400 && statusCode < 500)) {
      return {
        'error': true,
        'message': getErrorMessage(statusCode.toString()),
      };
    }
    // 处理其他错误
    return {
      'error': true,
      'message': getErrorMessage(response.toString()),
    };
  }
}