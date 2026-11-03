import 'package:flutter_test/flutter_test.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/resource/source_detail.dart';

Map<String, dynamic> _sampleData() => <String, dynamic>{
      'serviceCode': '000000',
      'prefixCode': '0000260045',
      'versionCode': 1,
      'goodsId': 110336,
      'goodsName': '当代大学生军事教育教程（第八版）',
      'goodsImage': 'http://img.mpreader.com/cover.jpg',
      'sourceCount': 7,
      'resourceCount': 853,
      'strategyType': 'CHAIN_UNIFORM_PRICE',
      'source': <String, dynamic>{
        'sourceIdentifier': '000000-000026004500101',
        'sourceNo': 1,
        'bookPageNo': 2,
        'resourceCount': 104,
        'free': false,
        'pay': false,
        'sell': true,
      },
      'targetList': <dynamic>[
        <String, dynamic>{
          'targetIdentifier': '000000-000026004500101',
          'resourceCount': 2,
          'resources': <dynamic>[
            <String, dynamic>{
              'id': 60370,
              'resourceId': '178790508386805100',
              'resourceType': 2,
              'resourceName': '第二章 国家安全_01',
              'resourceNo': 1,
              'resourceSize': '355359',
              'hasLike': true,
              'likeCount': 1,
              'free': false,
            },
            <String, dynamic>{
              'id': 60371,
              'resourceId': '178790508386805101',
              'resourceType': 4,
              'resourceName': '视频资源',
              'resourceNo': 2,
              'second': 95,
              'free': true,
            },
          ],
        },
      ],
    };

void main() {
  group('SourceScanData 解析', () {
    final SourceScanData data = SourceScanData.fromJson(_sampleData());

    test('出版物与统计字段', () {
      expect(data.goodsId, '110336');
      expect(data.goodsName, '当代大学生军事教育教程（第八版）');
      expect(data.goodsImage, 'http://img.mpreader.com/cover.jpg');
      expect(data.sourceCount, 7);
      expect(data.resourceCount, 853);
      expect(data.versionCode, 1);
    });

    test('源信息', () {
      final ChainSourceInfo? source = data.source;
      expect(source, isNotNull);
      expect(source!.sourceIdentifier, '000000-000026004500101');
      expect(source.sourceNo, 1);
      expect(source.bookPageNo, 2);
      expect(source.resourceCount, 104);
      expect(source.accessible, isFalse);
    });

    test('target 与资源列表', () {
      final ScanTarget? target = data.currentTarget;
      expect(target, isNotNull);
      expect(target!.targetIdentifier, '000000-000026004500101');

      final List<ScanResource> resources = data.currentResources;
      expect(resources.length, 2);

      final ScanResource image = resources.first;
      expect(image.id, 60370);
      expect(image.resourceId, '178790508386805100');
      expect(image.type, ResourceType.image);
      expect(image.resourceName, '第二章 国家安全_01');
      expect(image.isCharge, isTrue);
      expect(image.hasLike, isTrue);
      expect(image.likeCount, 1);

      final ScanResource video = resources.last;
      expect(video.type, ResourceType.video);
      expect(video.second, 95);
      expect(video.isCharge, isFalse);
    });

    test('购买策略判定', () {
      expect(data.isUniformStrategy, isTrue);
      expect(data.isAllFreeStrategy, isFalse);
      expect(data.isSourceFree, isFalse);
      expect(data.isSourceAccessible, isFalse);
      expect(data.needPurchase, isTrue);
    });
  });

  group('工具方法', () {
    test('cleanUrl 去除反引号/空白并把 http 升级为 https', () {
      expect(cleanUrl('`http://a.com/x.jpg`'), 'https://a.com/x.jpg');
      expect(cleanUrl('  http://a.com/y.jpg  '), 'https://a.com/y.jpg');
      expect(cleanUrl('http://127.0.0.1:9000/a.jpg'), 'http://127.0.0.1:9000/a.jpg');
      expect(cleanUrl(null), '');
    });

    test('ResourceType.fromRaw 兼容数字与字符串', () {
      expect(ResourceType.fromRaw(2), ResourceType.image);
      expect(ResourceType.fromRaw('4'), ResourceType.video);
      expect(ResourceType.fromRaw('unknown'), ResourceType.unknown);
    });

    test('moneyText 保留两位小数', () {
      expect(moneyText(6), '6.00');
      expect(moneyText(6.5), '6.50');
      expect(moneyText(null), '0.00');
    });
  });
}
