import 'package:flutter/material.dart';

class SourceItem extends StatelessWidget {
  final String sourceNo;
  final String sourceFragment;
  final String sourceIdentifier;
  final int resourceCount;
  final int bookPageNo;
  final bool isCurrentTarget;
  // 收费/已购状态：free、price 判断收费，pay 判断已购（source 为动态 JSON，用 dynamic 兼容 bool/int/String）
  final dynamic free;
  final dynamic price;
  final dynamic pay;
  final VoidCallback? onTap;

  const SourceItem({
    super.key,
    required this.sourceNo,
    required this.sourceFragment,
    this.sourceIdentifier = '',
    required this.resourceCount,
    required this.bookPageNo,
    this.isCurrentTarget = false,
    this.free,
    this.price,
    this.pay,
    this.onTap,
  });

  String _getSourceName() {
    if (sourceFragment.isNotEmpty) {
      return sourceFragment;
    }
    // source 数据中没有 serviceCode/prefixCode，为空时回退到 sourceIdentifier
    if (sourceIdentifier.isNotEmpty) {
      return sourceIdentifier;
    }
    return '链码';
  }

  /// 是否已购：pay 为 true/1/'1'/'true'
  bool get _isPaid => pay == true || pay == 1 || pay == '1' || pay == 'true';

  /// 是否免费：free 为 true/1/'1'/'true'，或 price 为空/≤0
  bool get _isFree {
    if (free == true || free == 1 || free == '1' || free == 'true') {
      return true;
    }
    if (price is num) {
      return (price as num) <= 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final Widget row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSerialNumber(),
          const SizedBox(width: 12),
          _buildInfoSection(),
          _buildStatusTag(),
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: row,
      );
    }
    return row;
  }

  Widget _buildSerialNumber() {
    // 动态宽度：不固定宽度、不换行
    return Text(
      sourceNo.isNotEmpty ? sourceNo : '1',
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: 11,
        color: isCurrentTarget ? const Color(0xFF00AFFE) : const Color(0xFF4F5960),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// 行尾状态标签：免费不显示；收费未购买显示「收费」；收费已购买显示「已购」
  Widget _buildStatusTag() {
    if (_isFree) {
      return const SizedBox.shrink();
    }
    if (_isPaid) {
      return _statusTag('已购', const Color(0xFF00AFFE));
    }
    return _statusTag('收费', const Color(0xFFFF8F00));
  }

  Widget _statusTag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 8, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9, color: Colors.white),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceName(),
          const SizedBox(height: 4),
          _buildResourceAndPage(),
        ],
      ),
    );
  }

  Widget _buildSourceName() {
    return Text(
      _getSourceName(),
      style: TextStyle(
        fontSize: 13,
        color: isCurrentTarget ? const Color(0xFF00AFFE) : const Color(0xFF585959),
      ),
    );
  }

  Widget _buildResourceAndPage() {
    return Row(
      children: [
        Text(
            '资源 $resourceCount',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF666666),
            ),
          ),
        const SizedBox(width: 12),
        Text(
          bookPageNo > 0 ? '页码 P$bookPageNo' : '页码 P-',
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF999999),
          ),
        ),
      ],
    );
  }
}