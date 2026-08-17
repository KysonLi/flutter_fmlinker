import 'dart:ui';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'imagecropper_ohos_method_channel.dart';

abstract class ImagecropperOhosPlatform extends PlatformInterface {
  /// Constructs a ImagecropperOhosPlatform.
  ImagecropperOhosPlatform() : super(token: _token);

  static final Object _token = Object();

  static ImagecropperOhosPlatform _instance = MethodChannelImagecropperOhos();

  /// The default instance of [ImagecropperOhosPlatform] to use.
  ///
  /// Defaults to [MethodChannelImagecropperOhos].
  static ImagecropperOhosPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ImagecropperOhosPlatform] when
  /// they register themselves.
  static set instance(ImagecropperOhosPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> sampleImage({
    required String path,
    required int maximumSize,
  }) {
    throw UnimplementedError('sampleImage() has not been implemented.');
  }

  Future<String?> cropImage({
    required String sourcePath,
    required Rect area,
    double? scale,
    double? angle,
    double? cx,
    double? cy,
  }) {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String?> recoverImage() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
