import 'package:flutter/material.dart';

class TabProvider extends ChangeNotifier {
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  // 外部调用：切换 Tab
  void switchTab(int index) {
    _currentIndex = index;
    notifyListeners(); // 通知页面刷新
  }
}
