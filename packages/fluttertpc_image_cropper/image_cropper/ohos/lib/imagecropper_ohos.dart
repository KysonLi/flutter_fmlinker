import 'dart:io';
import 'dart:ui';

import 'imagecropper_ohos_platform_interface.dart';

class ImagecropperOhos {

  Future<File?> sampleImage({
    required String path,
    required int maximumSize,
  }) async {
    String? filePath = await ImagecropperOhosPlatform.instance.sampleImage(path: path,maximumSize: maximumSize);
    return File(filePath!);
  }

  Future<File> cropImage({
    required File file,
    required Rect area,
    double? scale,
    double? angle,
    double? cx,
    double? cy,
  }) async {
    String? path = await ImagecropperOhosPlatform.instance.cropImage(
      sourcePath: file.path,
      area: area,
      scale: scale,
      angle: angle,
      cx: cx,
      cy: cy,
        );
    return File(path!);
  }

  Future<String?> recoverImage() async {
    return await ImagecropperOhosPlatform.instance.recoverImage();
  }
}
