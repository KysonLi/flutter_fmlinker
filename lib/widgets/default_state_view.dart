import 'package:flutter/material.dart';

import 'package:fmlink/utils/error_handler.dart';

/// 占位类型：数据为空 / 加载失败 / 网络异常
///
/// 素材与默认文案集中在此，避免各页面各写一套导致样式不一致。
enum DefaultStateType {
  /// 列表/详情无数据
  empty('assets/images/default_list_empty.png', '暂无数据'),

  /// 请求失败（服务端返回失败或数据异常）
  loadFailed('assets/images/default_load_failed.png', '加载失败，请稍后重试'),

  /// 无网络 / 连接失败 / 超时
  netError('assets/images/default_net_error.png', '网络连接异常，请检查网络后重试');

  const DefaultStateType(this.asset, this.defaultText);

  /// 占位图（透明底蓝色线稿，适配浅色页面）
  final String asset;

  /// 默认文案（调用方可通过 text 覆盖，如保留后端返回的具体原因）
  final String defaultText;
}

/// 页面「空数据 / 加载失败 / 网络异常」统一占位
///
/// 统一内容：占位图 + 13px 灰字说明 +（可选）蓝色胶囊重试按钮。
/// 用法：
/// ```dart
/// DefaultStateView.empty()                                  // 无数据
/// DefaultStateView.netError(onRetry: _load)                 // 无网络
/// DefaultStateView.loadFailed(text: msg, onRetry: _load)    // 请求失败（保留后端文案）
/// DefaultStateView.fromError(_error, onRetry: _load)        // 按错误文案自动选图
/// ```
///
/// [compact] 用于弹窗 / 底部面板等小区域（图更小、间距更紧）。
class DefaultStateView extends StatelessWidget {
  /// 占位类型
  final DefaultStateType type;

  /// 自定义文案；为空时用 [DefaultStateType.defaultText]
  final String? text;

  /// 副文案（可选，用于补充引导语，如「去逛逛，发现精彩内容」）
  final String? subText;

  /// 重试回调；为空则不显示重试按钮
  final VoidCallback? onRetry;

  /// 重试按钮文字
  final String retryText;

  /// 占位图高度（宽度按比例自适应，保证三张图视觉高度一致）
  final double imageHeight;

  /// 外边距
  final EdgeInsetsGeometry padding;

  /// 紧凑模式（弹窗 / 底部面板）
  final bool compact;

  const DefaultStateView({
    super.key,
    required this.type,
    this.text,
    this.subText,
    this.onRetry,
    this.retryText = '重新加载',
    this.imageHeight = 132,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
    this.compact = false,
  });

  /// 数据为空
  factory DefaultStateView.empty({
    Key? key,
    String? text,
    String? subText,
    VoidCallback? onRetry,
    String retryText = '去浏览',
    bool compact = false,
  }) {
    return DefaultStateView(
      key: key,
      type: DefaultStateType.empty,
      text: text,
      subText: subText,
      onRetry: onRetry,
      retryText: retryText,
      compact: compact,
    );
  }

  /// 请求失败（可带后端返回的具体原因）
  factory DefaultStateView.loadFailed({
    Key? key,
    String? text,
    VoidCallback? onRetry,
    String retryText = '重新加载',
    bool compact = false,
  }) {
    return DefaultStateView(
      key: key,
      type: DefaultStateType.loadFailed,
      text: text,
      onRetry: onRetry,
      retryText: retryText,
      compact: compact,
    );
  }

  /// 网络异常
  factory DefaultStateView.netError({
    Key? key,
    String? text,
    VoidCallback? onRetry,
    String retryText = '重新加载',
    bool compact = false,
  }) {
    return DefaultStateView(
      key: key,
      type: DefaultStateType.netError,
      text: text,
      onRetry: onRetry,
      retryText: retryText,
      compact: compact,
    );
  }

  /// 按错误文案自动选择占位样式
  ///
  /// 文案含「网络 / 超时 / 连接」→ 网络异常图；其余（含空文案）→ 加载失败图。
  /// 文案本身是 [ErrorHandler] 产出的用户可读中文，直接透传展示。
  factory DefaultStateView.fromError({
    Key? key,
    String? message,
    VoidCallback? onRetry,
    bool compact = false,
  }) {
    final String msg = (message ?? '').trim();
    final bool isNetwork =
        msg.contains('网络') || msg.contains('超时') || msg.contains('连接');
    return DefaultStateView(
      key: key,
      type: isNetwork ? DefaultStateType.netError : DefaultStateType.loadFailed,
      text: msg.isEmpty ? null : msg,
      onRetry: onRetry,
      compact: compact,
    );
  }

  /// 无网络时由 [ErrorHandler] 产出的标准文案（供页面判定使用）
  static bool isNetworkMessage(String? message) {
    final String msg = (message ?? '').trim();
    if (msg == ErrorHandler.networkMessage) return true;
    return msg.contains('网络') || msg.contains('超时') || msg.contains('连接');
  }

  @override
  Widget build(BuildContext context) {
    final String label =
        (text ?? '').trim().isEmpty ? type.defaultText : text!.trim();
    return Center(
      child: Padding(
        padding: compact ? const EdgeInsets.all(16) : padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              type.asset,
              // 只约束高度：三张图高度基准一致（336px），宽度按各自比例自适应
              height: compact ? 88 : imageHeight,
              fit: BoxFit.contain,
            ),
            SizedBox(height: compact ? 10 : 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                height: 1.5,
                color: const Color(0xFF999999),
              ),
            ),
            if ((subText ?? '').trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                subText!.trim(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  height: 1.5,
                  color: const Color(0xFFBFBFBF),
                ),
              ),
            ],
            if (onRetry != null) ...<Widget>[
              SizedBox(height: compact ? 12 : 20),
              _retryButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _retryButton() {
    return SizedBox(
      width: compact ? 116 : 144,
      height: 36,
      child: ElevatedButton(
        onPressed: onRetry,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF409EFF),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(retryText),
      ),
    );
  }
}
