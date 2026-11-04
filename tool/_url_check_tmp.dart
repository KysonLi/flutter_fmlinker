import 'package:fmlink/utils/url_util.dart';

void check(String input, String expected) {
  final actual = toHttpsUrl(input);
  final ok = actual == expected;
  print('${ok ? "PASS" : "FAIL"}  $input\n      -> $actual${ok ? "" : "\n      expect: $expected"}');
  if (!ok) throw Exception('mismatch');
}

void main() {
  check('http://img.mpreader.com:80/image/2019/a.thumbnail.jpg',
      'https://img.mpreader.com/image/2019/a.thumbnail.jpg');
  check('http://apigateway.mpreader.com:11999/x/y', 'https://apigateway.mpreader.com/x/y');
  check('http://img.mpreader.com:80/a.jpg?x=1&y=2', 'https://img.mpreader.com/a.jpg?x=1&y=2');
  check('http://img.mpreader.com/image/a.jpg', 'https://img.mpreader.com/image/a.jpg');
  check('https://a.com:8443/x.png', 'https://a.com:8443/x.png');
  check('http://127.0.0.1:53211/media/a.m3u8', 'http://127.0.0.1:53211/media/a.m3u8');
  check('`http://a.com/x.jpg`', 'https://a.com/x.jpg');
  final nested = upgradeUrlsToHttps(<String, dynamic>{'goodsImage': 'http://img.mpreader.com:80/c.jpg'});
  print('nested -> ${nested['goodsImage']}');
  print('ALL OK');
}
