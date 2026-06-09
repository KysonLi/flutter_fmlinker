class ISLICodeUtil {
  static String calculateCheckBit(String isliCode) {
    String cleanCode = isliCode.replaceAll(RegExp(r'[- ]'), '');

    if (!RegExp(r'^[0-9]+$').hasMatch(cleanCode)) {
      return '';
    }

    int sum = 0;
    for (int i = 1; i <= cleanCode.length; i++) {
      int v = int.parse(cleanCode[cleanCode.length - i]);
      int w = i % 2 == 0 ? 2 : 1;
      int p = v * w;
      int s = p > 9 ? (p % 10 + p ~/ 10) : p;
      sum += s;
    }

    int value = sum % 10;
    return (value > 0 ? 10 - value : 0).toString();
  }

  static String buildISLICode(String serviceCode, String prefixCode, String suffixCode) {
    String isliCode = '$serviceCode$prefixCode$suffixCode';
    String sourceName = '$serviceCode-$prefixCode$suffixCode';
    String checkBit = calculateCheckBit(isliCode);

    if (checkBit.isNotEmpty) {
      sourceName = '$sourceName-$checkBit';
    }

    return sourceName;
  }
}