import 'package:flutter/material.dart';

/// 轻量骨架占位组件。
///
/// 替代第三方库 `skeletonizer`（其所有发布版本均要求 Dart >=3.0.0，
/// 与当前 OHOS Flutter 工具链 Dart 2.19.6 不兼容）。
///
/// 仅透传子节点——调用方已用灰色 `Container` 自行搭建骨架外观，
/// 此处保持 API 与原 `Skeletonizer({child})` 一致以便后续无缝替换。
class Skeletonizer extends StatelessWidget {
  final Widget child;

  const Skeletonizer({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
