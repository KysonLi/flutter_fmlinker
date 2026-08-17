import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'imagecropper_ohos_platform_interface.dart';

/// An implementation of [ImagecropperOhosPlatform] that uses method channels.
class MethodChannelImagecropperOhos extends ImagecropperOhosPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('imagecropper');


  @override
  Future<String?> sampleImage({
    required String path,
    required int maximumSize,
  }) async {
    String? sampleFile = await methodChannel.invokeMethod<String>('sampleImage',<String,dynamic>{
      'path':path,
      'maximumWidth':maximumSize,
      'maximumHeight':maximumSize,
    });
    return sampleFile;
  }

  @override
  Future<String?> cropImage(
      {required String sourcePath,
        required Rect area,
        double? scale,
        double? angle,
        double? cx,
        double? cy,
      }) async {

    final path = await methodChannel.invokeMethod<String>('cropImage',{
      'path': sourcePath,
      'left': area.left,
      'top': area.top,
      'right': area.right,
      'bottom': area.bottom,
      'scale': scale ?? 1.0,
      'angle': angle ?? 0,
      'cx': cx ?? 0,
      'cy':cy ?? 0,
    });
    return path;
  }

  @override
  Future<String?> recoverImage() async {
    final path = await methodChannel.invokeMethod<String>('recoverImage');
    return path;
  }
}
