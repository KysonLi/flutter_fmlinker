import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../provider/tab_provider.dart';
import '../history/history_screen.dart';
import '../publish/publish_screen.dart';
import '../discover/discover_screen.dart';
import '../profile/profile_screen.dart';

/// 自绘 tabbar 顶部边框：中间向上微凸（弧形凸起），无边框线，扫码按钮与 tabbar 融为一体
class _TabbarCurvePainter extends CustomPainter {
  _TabbarCurvePainter({
    required this.fillColor,
    required this.bumpWidth,
    required this.bumpHeight,
  });

  final Color fillColor;
  final double bumpWidth;
  final double bumpHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // 顶边：左侧平直 → 中间凸起圆弧 → 右侧平直
    // 用真正的圆弧（arcTo）而非贝塞尔曲线，曲率恒定、顶部圆润不尖。
    // 过两端点 (cx±half, 0) 与顶点 (cx, -bumpHeight) 的圆：
    //   圆心 (cx, yc)，yc = (half² - h²) / 2h，半径 r = h + yc
    final double half = bumpWidth / 2;
    final double cx = w / 2;
    final double yc = (half * half - bumpHeight * bumpHeight) / (2 * bumpHeight);
    final double r = bumpHeight + yc;
    final double startAngle = math.atan2(-yc, -half);
    final double sweepAngle = math.atan2(-yc, half) - startAngle;

    final Path top = Path()
      ..moveTo(0, 0)
      ..lineTo(cx - half, 0)
      ..arcTo(Rect.fromCircle(center: Offset(cx, yc), radius: r), startAngle, sweepAngle, false)
      ..lineTo(w, 0);

    // 背景填充：顶边 + 三条边包围到底，确保整个 tabbar（含凸起区域）铺满白色
    final Path fill = Path.from(top)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    // 顶部淡阴影：沿整根 tabbar 轮廓（含凸起弧线）向上偏移 + 高斯模糊，
    // 两层叠加（一层紧贴边缘、一层软扩散）复刻系统 tabbar 的投影效果
    final Path silhouette = Path.from(fill);
    final Paint tightShadow = Paint()
      ..color = const Color(0x05000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(silhouette.shift(const Offset(0, -1)), tightShadow);
    final Paint softShadow = Paint()
      ..color = const Color(0x03000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(silhouette.shift(const Offset(0, -3.5)), softShadow);

    // 白色填充盖住落在栏内的阴影部分
    canvas.drawPath(fill, Paint()..color = fillColor);
  }

  @override
  bool shouldRepaint(covariant _TabbarCurvePainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.bumpWidth != bumpWidth ||
        oldDelegate.bumpHeight != bumpHeight;
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tabProvider = Provider.of<TabProvider>(context);
    int currentIndex = tabProvider.currentIndex;

    Widget getCurrentPage() {
      switch (currentIndex) {
        case 0:
          return const HistoryScreen();
        case 1:
          return const PublishScreen();
        case 3:
          return const DiscoverScreen();
        case 4:
          return const MyScreen();
        default:
          return const HistoryScreen();
      }
    }

    return Scaffold(
      body: getCurrentPage(),
      bottomNavigationBar: SizedBox(
        // 栏高 58 + 底部安全区
        height: 56 + MediaQuery.of(context).padding.bottom,
        child: CustomPaint(
          painter: _TabbarCurvePainter(
            fillColor: Colors.white,
            bumpWidth: 60,
            bumpHeight: 15,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTabItem(
                  context,
                  0,
                  '关联',
                  'assets/icons/tabbar/linker.png',
                  'assets/icons/tabbar/linker_active.png',
                  tabProvider,
                ),
                _buildTabItem(
                  context,
                  1,
                  '出版',
                  'assets/icons/tabbar/publish.png',
                  'assets/icons/tabbar/publish_active.png',
                  tabProvider,
                ),
                _buildScanItem(context),
                _buildTabItem(
                  context,
                  3,
                  '发现',
                  'assets/icons/tabbar/discover.png',
                  'assets/icons/tabbar/discover_active.png',
                  tabProvider,
                ),
                _buildTabItem(
                  context,
                  4,
                  '我的',
                  'assets/icons/tabbar/mine.png',
                  'assets/icons/tabbar/mine_active.png',
                  tabProvider,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 中间扫码按钮：沿用原图标，无文字，尺寸更大并向上凸起（嵌入凸起弧线区域）
  Widget _buildScanItem(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -10),
      child: GestureDetector(
        onTap: () => context.push('/scan'),
        behavior: HitTestBehavior.opaque,
        child: Image.asset(
          'assets/icons/tabbar/scanning.png',
          width: 60,
          height: 60,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildTabItem(
    BuildContext context,
    int index,
    String label,
    String icon,
    String activeIcon,
    TabProvider tabProvider,
  ) {
    final bool selected = tabProvider.currentIndex == index;
    return InkWell(
      onTap: () => tabProvider.switchTab(index),
      child: SizedBox(
        // 固定等宽，保证 spaceAround 布局下左右两组总宽一致、中间扫码按钮严格居中，
        // 否则图标宽度差异（关联图标宽于其他方形图标）会把中间按钮挤偏，与凸起错位
        width: 44,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              selected ? activeIcon : icon,
              // 只约束高度，宽度按源图宽高比自适应：
              // 关联图标源图是 102x84（宽>高），若同时约束 24x24 + contain 会被等比缩小，显得比方形图标小
              height: 24,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? const Color(0xFF4A90E2)
                    : const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
