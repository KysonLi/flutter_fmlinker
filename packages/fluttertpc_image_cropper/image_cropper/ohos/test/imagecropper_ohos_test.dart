import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagecropper_ohos/imagecropper_ohos.dart';
import 'package:imagecropper_ohos/imagecropper_ohos_platform_interface.dart';
import 'package:imagecropper_ohos/imagecropper_ohos_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockImagecropperOhosPlatform
    with MockPlatformInterfaceMixin
    implements ImagecropperOhosPlatform {


  @override
  Future<String?> cropImage({required String sourcePath, required Rect area, double? scale, double? angle, double? cx, double? cy}) async {
    return "cropImage";
  }

  @override
  Future<String?> recoverImage() async{
    return "recoverImage";
  }

  @override
  Future<String?> sampleImage({required String path, required int maximumSize}) async{
    return "sampleImage";
  }
}

void main() {
  final ImagecropperOhosPlatform initialPlatform = ImagecropperOhosPlatform.instance;

  test('$MethodChannelImagecropperOhos is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelImagecropperOhos>());
  });

  test('cropImage', () async {
    ImagecropperOhos imagecropperOhosPlugin = ImagecropperOhos();
    MockImagecropperOhosPlatform fakePlatform = MockImagecropperOhosPlatform();
    ImagecropperOhosPlatform.instance = fakePlatform;

    expect((await imagecropperOhosPlugin.cropImage(file: File("filePath"), area: Rect.zero)).path, 'cropImage');
  });
}
