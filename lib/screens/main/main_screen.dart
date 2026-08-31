import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../provider/tab_provider.dart';
import '../history/history_screen.dart';
import '../publish/publish_screen.dart';
import '../discover/discover_screen.dart';
import '../profile/profile_screen.dart';

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
      // 中央凸起的扫码按钮：仅一个图标，无文字，点击进入独立的全屏扫码页（与 tabbar 无关联）
      floatingActionButton: FloatingActionButton(
        heroTag: 'scan_fab',
        onPressed: () => context.push('/scan'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Image.asset(
          'assets/icons/tabbar/scanning.png',
          width: 56,
          height: 56,
          fit: BoxFit.contain,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        color: Colors.white,
        elevation: 2,
        child: SizedBox(
          height: 56,
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
              // 中间凹槽：容纳凸起的扫码按钮
              const SizedBox(width: 56),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            selected ? activeIcon : icon,
            width: 24,
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
    );
  }
}
