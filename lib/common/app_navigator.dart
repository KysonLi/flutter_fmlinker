import 'package:flutter/material.dart';

/// 全局导航 key
///
/// 供无 context 场景（如网络层 token 过期处理）获取导航上下文并跳转页面。
/// 在 `AppRouter.router`（GoRouter）构造时挂载，`currentContext` 即为
/// 当前导航栈的 BuildContext。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
