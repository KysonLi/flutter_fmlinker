import 'package:flutter/foundation.dart';

/// 统一日志出口
///
/// 约束：
/// - 默认仅在 debug 构建输出；release 构建直接丢弃，避免日志泄露用户信息（token/手机号/订单等）
/// - 内部测试包可用 `--dart-define=APP_LOG=true` 强制打开 release 日志（排查线上问题用）
/// - 业务代码统一使用 [AppLog]，禁止直接 `print` / `debugPrint`
///
/// 用法：`AppLog.d('加载失败: $e', tag: 'LinkService')`
class AppLog {
  AppLog._();

  /// 内部测试包开关（正式发布包不要带这个 dart-define）
  static const bool _forceInRelease = bool.fromEnvironment('APP_LOG');

  /// 调试信息
  static void d(Object? message, {String? tag}) => _write('D', tag, message);

  /// 一般信息
  static void i(Object? message, {String? tag}) => _write('I', tag, message);

  /// 警告
  static void w(Object? message, {String? tag}) => _write('W', tag, message);

  /// 错误（可带堆栈）
  static void e(Object? message, {String? tag, StackTrace? stack}) {
    _write('E', tag, message);
    if (stack != null) {
      _write('E', tag, stack);
    }
  }

  static void _write(String level, String? tag, Object? message) {
    if (!kDebugMode && !_forceInRelease) return;
    debugPrint(tag == null ? '[$level] $message' : '[$level][$tag] $message');
  }
}
