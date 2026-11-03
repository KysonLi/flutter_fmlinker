import 'dart:io';

/// 平台判断兼容层
///
/// 鸿蒙版 Flutter SDK 额外提供了 `Platform.isOhos`，官方 SDK 没有这个成员，
/// 直接使用会导致代码只能在鸿蒙分支的 SDK 下编译（CI / IDE 切官方 SDK 会报错）。
/// 这里统一用 `operatingSystem` 字符串判断，两种 SDK 行为完全一致。
class PlatformCompat {
  PlatformCompat._();

  /// 是否运行在 HarmonyOS / OpenHarmony
  static bool get isOhos => Platform.operatingSystem == 'ohos';
}
