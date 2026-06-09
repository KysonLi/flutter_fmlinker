import 'package:flutter/material.dart';
import 'package:fmlink/utils/isli_code_util.dart';

class SourceItem extends StatelessWidget {
  final String sourceNo;
  final String sourceFragment;
  final int resourceCount;
  final int bookPageNo;
  final String? serviceCode;
  final String? prefixCode;
  final String? suffixCode;
  final bool isCurrentTarget;

  const SourceItem({
    super.key,
    required this.sourceNo,
    required this.sourceFragment,
    required this.resourceCount,
    required this.bookPageNo,
    this.serviceCode,
    this.prefixCode,
    this.suffixCode,
    this.isCurrentTarget = false,
  });

  String _getSourceName() {
    if (sourceFragment.isNotEmpty) {
      return sourceFragment;
    }

    String service = serviceCode ?? '';
    String prefix = prefixCode ?? '';
    String suffix = suffixCode ?? '';

    if (service.isEmpty && prefix.isEmpty && suffix.isEmpty) {
      return '链码';
    }

    return ISLICodeUtil.buildISLICode(service, prefix, suffix);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
        ],
      ),
    );
  }

  Widget _buildSerialNumber() {
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Text(
          sourceNo.isNotEmpty ? sourceNo : '1',
          style: TextStyle(
            fontSize: 11,
            color: isCurrentTarget ? const Color(0xFF00AFFE) : const Color(0xFF4F5960),
            fontWeight: FontWeight.bold,
          ),
        ),
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