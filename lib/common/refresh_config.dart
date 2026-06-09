import 'package:flutter/material.dart';
import 'package:easy_refresh/easy_refresh.dart';

class RefreshConfig {
  static Header buildHeader() {
    return const ClassicHeader(
      dragText: '下拉刷新',
      armedText: '松开立即刷新',
      processingText: '加载中...',
      readyText: '准备加载',
      processedText: '刷新完成',
      textStyle: TextStyle(fontSize: 12, color: Color(0xFF666666)),
      messageText: '更新于 %T',
      messageStyle: TextStyle(fontSize: 10, color: Color(0xFF666666)),
    );
  }

  static Footer buildFooter() {
    return const ClassicFooter(
      dragText: '上拉加载更多',
      armedText: '松开立即加载更多',
      readyText: '准备加载',
      processedText: '加载完成',
      processingText: '加载中',
      failedText: '加载失败',
      noMoreText: '暂无更多数据',
      textStyle: TextStyle(fontSize: 12, color: Color(0xFF666666)),
      showMessage: false,
    );
  }
}
