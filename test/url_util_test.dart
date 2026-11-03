import 'package:flutter_test/flutter_test.dart';
import 'package:fmlink/utils/url_util.dart';

void main() {
  group('toHttpsUrl', () {
    test('http 资源地址升级为 https', () {
      expect(
        toHttpsUrl('http://img.mpreader.com/image/a.jpg'),
        'https://img.mpreader.com/image/a.jpg',
      );
      expect(
        toHttpsUrl('HTTP://lsdmedia.ilikereader.com/data/a.mp4'),
        'https://lsdmedia.ilikereader.com/data/a.mp4',
      );
    });

    test('已是 https / 相对路径 / 空值原样返回', () {
      expect(toHttpsUrl('https://a.com/x.png'), 'https://a.com/x.png');
      expect(toHttpsUrl('assets/images/a.png'), 'assets/images/a.png');
      expect(toHttpsUrl(null), '');
      expect(toHttpsUrl('  '), '');
    });

    test('本机与局域网地址保持不变（本地媒体服务不能升级）', () {
      const String local = 'http://127.0.0.1:53211/media/a.m3u8';
      expect(toHttpsUrl(local), local);
      expect(toHttpsUrl('http://localhost:8080/x'), 'http://localhost:8080/x');
      expect(toHttpsUrl('http://10.0.0.8/x'), 'http://10.0.0.8/x');
      expect(toHttpsUrl('http://192.168.1.7/x'), 'http://192.168.1.7/x');
      expect(toHttpsUrl('http://172.20.1.2/x'), 'http://172.20.1.2/x');
    });

    test('清理反引号与首尾空白', () {
      expect(toHttpsUrl('`http://a.com/x.jpg`'), 'https://a.com/x.jpg');
      expect(toHttpsUrl('  http://a.com/y.jpg  '), 'https://a.com/y.jpg');
    });
  });

  group('upgradeUrlsToHttps', () {
    test('递归处理 Map / List 中的地址', () {
      final dynamic result = upgradeUrlsToHttps(<String, dynamic>{
        'goodsImage': 'http://img.mpreader.com/cover.jpg',
        'list': <dynamic>[
          <String, dynamic>{'url': 'http://lsdmedia.ilikereader.com/a.mp4'},
          <String, dynamic>{'url': 'https://already.com/b.jpg'},
        ],
        'count': 2,
      });

      expect(result['goodsImage'], 'https://img.mpreader.com/cover.jpg');
      expect(
          result['list'][0]['url'], 'https://lsdmedia.ilikereader.com/a.mp4');
      expect(result['list'][1]['url'], 'https://already.com/b.jpg');
      expect(result['count'], 2);
    });

    test('富文本（HTML/含空白）保持原样', () {
      const String html = '<p><img src="http://img.mpreader.com/a.jpg"></p>';
      expect(upgradeUrlsToHttps(html), html);
    });

    test('本地地址在嵌套结构中也保持原样', () {
      final dynamic result = upgradeUrlsToHttps(<String, dynamic>{
        'playUrl': 'http://127.0.0.1:53211/media/a.m3u8',
      });
      expect(result['playUrl'], 'http://127.0.0.1:53211/media/a.m3u8');
    });
  });
}
