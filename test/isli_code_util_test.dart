import 'package:flutter_test/flutter_test.dart';
import 'package:fmlink/utils/isli_code_util.dart';

void main() {
  group('ISLICodeUtil.calculateCheckBit', () {
    test('按加权模 10 计算校验位', () {
      // 真实链码 000000-000026004500101 的前 20 位载荷
      expect(ISLICodeUtil.calculateCheckBit('00000000002600450010'), '5');
      expect(ISLICodeUtil.calculateCheckBit('12345678901234567890'), '4');
    });

    test('忽略连字符与空格', () {
      expect(
        ISLICodeUtil.calculateCheckBit('000000-00002600450010'),
        ISLICodeUtil.calculateCheckBit('00000000002600450010'),
      );
      expect(
        ISLICodeUtil.calculateCheckBit('000000 00002600450010'),
        ISLICodeUtil.calculateCheckBit('00000000002600450010'),
      );
    });

    test('非数字输入返回空串', () {
      expect(ISLICodeUtil.calculateCheckBit('000000-0000260045001X'), '');
      expect(ISLICodeUtil.calculateCheckBit(''), '');
    });
  });

  group('ISLICodeUtil.buildISLICode', () {
    test('按 服务码-前缀+后缀-校验位 组装', () {
      expect(
        ISLICodeUtil.buildISLICode('000000', '0000260045', '0101'),
        '000000-00002600450101-5',
      );
    });

    test('服务码与后续部分用连字符分隔', () {
      final String code =
          ISLICodeUtil.buildISLICode('111111', '0000260045', '0101');
      expect(code.substring(0, 7), '111111-');
      expect(code.split('-').length, 3);
    });
  });
}
