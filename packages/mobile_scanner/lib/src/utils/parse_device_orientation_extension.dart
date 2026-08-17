import 'package:flutter/services.dart';

/// This extension defines a utility function for parsing a [DeviceOrientation]
/// from a [String].
extension ParseDeviceOrientation on String {
  /// Parse `this` into a [DeviceOrientation].
  ///
  /// Returns the parsed device orientation.
  /// Throws an [ArgumentError] if `this` is an invalid device orientation.
  DeviceOrientation parseDeviceOrientation() {
    switch (this) {
      case 'PORTRAIT_UP':
        return DeviceOrientation.portraitUp;
      case 'PORTRAIT_DOWN':
        return DeviceOrientation.portraitDown;
      case 'LANDSCAPE_LEFT':
        return DeviceOrientation.landscapeLeft;
      case 'LANDSCAPE_RIGHT':
        return DeviceOrientation.landscapeRight;
      default:
        throw ArgumentError.value(
          this,
          'deviceOrientation',
          'Received an invalid device orientation',
        );
    }
  }
}
