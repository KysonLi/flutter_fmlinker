/// 链码解析器
///
/// 链码（MPR 出版物编码）为一串数字（可含连字符/空格/其它字符），
/// 有效链码归一化为 21 位：前 6 位 serviceCode、中间 10 位 prefixCode、后 5 位 suffixCode。
///
/// 特殊形态：
/// - serviceCode=000000 且 suffix=99999      → ISBN，有效标志码为第 6~15 位（11 位）
/// - serviceCode=000001 且 suffix 后 3 位=999 → ISSN，有效标志码为第 6~17 位（13 位）
/// - serviceCode=000002                      → ISON（不支持，仅提示）
/// - 其余                                     → 普通链码（走资源数据）
///
/// 参考小程序端 parseChainCode 实现移植。
///
/// 链码解析结果样式
enum ChainCodeStyle { isbn, issn, ison, unknown }

/// 链码解析结果
class ChainCodeInfo {
  final String fullCode;
  final ChainCodeStyle style;

  /// 有效标志码数据（isbn/issn 时非空，其余为空字符串）
  final String markCode;

  const ChainCodeInfo({
    required this.fullCode,
    required this.style,
    required this.markCode,
  });

  /// 是否解析为 ISBN/ISSN（当作标志码处理）
  bool get isMarkStyle => style == ChainCodeStyle.isbn || style == ChainCodeStyle.issn;

  /// 是否 ISON（暂不支持）
  bool get isIson => style == ChainCodeStyle.ison;
}

/// 解析链码：去除非数字字符 → 左补齐到 21 位 → 按前缀/后缀判定形态
ChainCodeInfo parseChainCode(String code) {
  final String digits = code.replaceAll(RegExp(r'\D'), '');
  final String fullCode = digits.padLeft(21, '0');
  if (fullCode.length != 21) {
    return ChainCodeInfo(fullCode: fullCode, style: ChainCodeStyle.unknown, markCode: '');
  }

  final String prefixCode = fullCode.substring(0, 6);
  final String suffixCode = fullCode.substring(16, 21);

  if (prefixCode == '000000') {
    if (suffixCode == '99999') {
      // ISBN：第 5~15 位（substring(5, 16)）
      return ChainCodeInfo(
        fullCode: fullCode,
        style: ChainCodeStyle.isbn,
        markCode: fullCode.substring(5, 16),
      );
    }
  } else if (prefixCode == '000001') {
    if (suffixCode.substring(2, 5) == '999') {
      // ISSN：第 5~17 位（substring(5, 18)）
      return ChainCodeInfo(
        fullCode: fullCode,
        style: ChainCodeStyle.issn,
        markCode: fullCode.substring(5, 18),
      );
    }
  } else if (prefixCode == '000002') {
    return ChainCodeInfo(fullCode: fullCode, style: ChainCodeStyle.ison, markCode: '');
  }

  return ChainCodeInfo(fullCode: fullCode, style: ChainCodeStyle.unknown, markCode: '');
}
