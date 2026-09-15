import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 统一错误信息处理（全项目错误文案的唯一出口）
///
/// 数据源：`assets/json/FMErrorStrings.json`（服务端错误码 → 中英文文案，服务端维护）
///
/// 展示兜底顺序（自上而下，命中即返回）：
/// 1. **连接层错误**：无网络、超时、HTTP 4xx/5xx 等，返回固定的中文文案，
///    **不透出 Dio / 系统异常的英文原文**
/// 2. **服务端错误码**：命中 JSON 配置 → 用配置里的中文文案
/// 3. **接口返回的 message**：JSON 未定义该码时使用，但仅当它适合直接展示
///    （过滤掉异常串、超长英文、JSON 片段等技术性内容）
/// 4. **通用兜底**：[genericMessage]
class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  /// 错误码配置文件（与服务端定义保持一致）
  static const String assetPath = 'assets/json/FMErrorStrings.json';

  /// 无网络 / 连接失败
  static const String networkMessage = '网络连接异常，请检查网络后重试';

  /// 通用兜底文案
  static const String genericMessage = '操作失败，请稍后重试';

  /// 纯英文内容的最大可展示长度（超过视为「一长串英文」，改用通用提示）
  static const int _maxAsciiLength = 60;

  /// 任意文案的最大可展示长度
  static const int _maxMessageLength = 80;

  /// 技术性关键字：命中则判定为不适合直接展示给用户
  static const List<String> _technicalKeywords = <String>[
    'exception',
    'dioexception',
    'socket',
    'errno',
    'stack',
    'failed host lookup',
    'connection refused',
    'connection closed',
    'xmlhttprequest',
    'statuscode',
    'stacktrace',
    'null check operator',
    'type \'',
    'instance of',
  ];

  Map<String, Map<String, String>> _errorMap = <String, Map<String, String>>{};
  Future<void>? _loading;
  bool _loaded = false;

  /// 应用启动时调用（未调用时首次查询会自动懒加载）
  Future<void> init() => _ensureLoaded();

  bool get isLoaded => _loaded;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final String raw = await rootBundle.loadString(assetPath);
      final dynamic json = jsonDecode(raw);
      if (json is Map) {
        final Map<String, Map<String, String>> parsed =
            <String, Map<String, String>>{};
        json.forEach((dynamic key, dynamic value) {
          if (value is Map) {
            parsed[key.toString()] = <String, String>{
              'cn': value['cn']?.toString() ?? '',
              'en': value['en']?.toString() ?? '',
            };
          }
        });
        _errorMap = parsed;
      }
      _loaded = true;
      print('错误码配置加载完成: ${_errorMap.length} 条');
    } catch (e) {
      // 资源缺失/解析失败时不影响功能，后续走通用兜底
      print('错误码配置加载失败($assetPath): $e');
    }
  }

  // ==================== 对外入口 ====================

  /// 统一的错误提示文案
  ///
  /// [code] 服务端返回的错误码（resultCode/status）
  /// [serverMessage] 接口返回的 message（resultMsg/message）
  /// [statusCode] HTTP 状态码
  /// [error] 捕获到的异常（连接层错误）
  String messageFor({
    String? code,
    String? serverMessage,
    int? statusCode,
    Object? error,
  }) {
    // 1. 连接层错误：异常或 HTTP 4xx/5xx，统一用中文文案
    if (error != null) return fromError(error);
    final String? statusText = statusMessage(statusCode);
    if (statusText != null) return statusText;

    // 2. 服务端错误码命中配置
    final String byCode = getErrorMessage(code);
    if (byCode.isNotEmpty) return byCode;

    // 3. 接口返回的 message（仅当适合直接展示）
    final String server = (serverMessage ?? '').trim();
    if (isDisplayable(server)) return server;

    // 4. 通用兜底
    return genericMessage;
  }

  /// 错误码 → 文案；未命中返回空串（由调用方决定兜底）
  String getErrorMessage(String? errorCode, {String language = 'cn'}) {
    if (errorCode == null) return '';
    final String code = errorCode.trim();
    if (code.isEmpty) return '';
    if (!_loaded) unawaited(_ensureLoaded());
    final Map<String, String>? item = _errorMap[code];
    if (item == null) return '';
    return (item[language] ?? item['cn'] ?? '').trim();
  }

  /// HTTP 状态码 → 中文文案；非错误状态返回 null（表示不适用，继续走后续兜底）
  String? statusMessage(int? statusCode) {
    if (statusCode == null || statusCode < 400) return null;
    switch (statusCode) {
      case 400:
        return '请求参数有误，请稍后重试';
      case 401:
        return '登录已过期，请重新登录';
      case 403:
        return '没有访问该资源的权限';
      case 404:
        return '请求的资源不存在';
      case 405:
        return '请求方式不被允许';
      case 406:
        return '请求被拒绝，请稍后重试';
      case 408:
        return '请求超时，请稍后重试';
      case 413:
        return '文件过大，请更换后重试';
      case 415:
        return '不支持的文件格式';
      case 429:
        return '操作过于频繁，请稍后重试';
      case 500:
        return '服务器开小差了，请稍后重试';
      case 501:
        return '服务暂未实现，请稍后重试';
      case 502:
      case 503:
        return '服务暂时不可用，请稍后重试';
      case 504:
        return '服务响应超时，请稍后重试';
    }
    if (statusCode >= 500) return '服务器开小差了，请稍后重试';
    return '请求失败，请稍后重试';
  }

  /// 异常 → 中文文案（避免把英文异常/堆栈直接抛给用户）
  String fromError(Object? error, {String fallback = genericMessage}) {
    if (error == null) return fallback;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return '网络超时，请稍后重试';
        case DioExceptionType.badCertificate:
          return '安全证书校验失败，请检查网络环境';
        case DioExceptionType.badResponse:
          return statusMessage(error.response?.statusCode) ?? genericMessage;
        case DioExceptionType.cancel:
          return '请求已取消';
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          // unknown 多数是 Socket/DNS 层异常，其原始文案为英文，这里统一收敛
          return networkMessage;
      }
    }
    if (error is SocketException) return networkMessage;
    if (error is TimeoutException) return '网络超时，请稍后重试';
    if (error is HandshakeException) return '安全连接失败，请检查网络环境';
    if (error is FormatException) return '数据解析失败，请稍后重试';
    // 其它异常不透出原始文案
    return fallback;
  }

  /// 接口返回的 message 是否适合直接展示给用户
  ///
  /// 服务端偶尔会把异常描述、英文堆栈或 JSON 片段塞进 message，
  /// 这类内容直接提示体验很差，命中以下任一条件即判定为不适合：
  /// - 空白、超长（中文 >80 字；纯英文 >60 字符）
  /// - 含换行、技术性关键字（exception/socket/stack...）
  /// - 形如 JSON / URL 的片段
  bool isDisplayable(String? message) {
    final String text = (message ?? '').trim();
    if (text.isEmpty) return false;
    if (text.length > _maxMessageLength) return false;
    if (text.contains('\n') || text.contains('\r')) return false;

    final String lower = text.toLowerCase();
    for (final String keyword in _technicalKeywords) {
      if (lower.contains(keyword)) return false;
    }
    if (text.contains('{') ||
        text.contains('}') ||
        lower.contains('http://') ||
        lower.contains('https://')) {
      return false;
    }
    // 纯英文（无中文）且较长时视为「一长串英文」
    final bool hasCjk = RegExp(r'[\u4e00-\u9fa5]').hasMatch(text);
    if (!hasCjk && text.length > _maxAsciiLength) return false;
    return true;
  }
}
