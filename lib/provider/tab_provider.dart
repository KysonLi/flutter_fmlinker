import 'package:flutter/material.dart';

class TabProvider extends ChangeNotifier {
  /// 底部导航可切换的 tab 下标
  ///
  /// 中间「扫码」按钮是独立路由 `/scan`，**不是** tab 页（MainScreen 没有对应分支），
  /// 因此 2 不在可切换下标内，需要扫码时请用 `context.push('/scan')`。
  static const List<int> tabIndexes = <int>[0, 1, 3, 4];

  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  /// 外部调用：切换 Tab（仅接受 [tabIndexes] 中的下标，其余忽略）
  void switchTab(int index) {
    if (!tabIndexes.contains(index)) return;
    if (_currentIndex == index) return;
    _currentIndex = index;
    notifyListeners(); // 通知页面刷新
  }
}
