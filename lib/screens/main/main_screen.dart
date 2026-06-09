import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../provider/tab_provider.dart';
import '../history/history_screen.dart';
import '../publish/publish_screen.dart';
import '../scan/scan_screen.dart';
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
        case 2:
          return const ScanScreen();
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          tabProvider.switchTab(index);
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.link), label: '关联'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: '出版'),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: '扫码',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: '发现'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
