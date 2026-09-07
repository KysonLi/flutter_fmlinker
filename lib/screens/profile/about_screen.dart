import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  final String _currentVersion = '1.0.0';
  final String _latestVersion = '暂无新版';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于我们', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopSection(),
            const SizedBox(height: 10),
            _buildMiddleSection(),
            const SizedBox(height: 10),
            _buildBottomSection(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      child: Column(
        children: [
          Image.asset('assets/images/about_logo.png', width: 80, height: 80),
          const SizedBox(height: 16),
          const Text.rich(
            TextSpan(
              children: [
                WidgetSpan(child: SizedBox(width: 20)),
                TextSpan(
                  text:
                      '泛媒关联App是通过扫描印刷在MPR出版物上的链码，播放或阅读MPR出版物关联的全媒版多媒体资源的增值阅读应用。\n',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black87,
                    height: 1.6,
                  ),
                ),
                WidgetSpan(child: SizedBox(width: 20)),
                TextSpan(
                  text:
                      '链码是一种被嵌入在纸书文本行空隙之间的、外观类似双下划线的二维码。使用泛媒关联App扫描链码，能够获取纸质媒体关联的图文、音频、视频、小应用、3D模型等全媒体内容。',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black87,
                    height: 1.6,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 16),
          const Text(
            '联系邮箱：service@mpreader.com',
            style: TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '当前版本',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                Text(
                  _currentVersion,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '最新版本',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                Text(
                  _latestVersion,
                  style: TextStyle(
                    fontSize: 12,
                    color: _latestVersion == '暂无新版'
                        ? Colors.grey
                        : const Color(0xFF2376E3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {},
                child: const Text(
                  '《泛媒关联用户协议》',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF2376E3),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {},
                child: const Text(
                  '《隐私政策》',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF2376E3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'ICP备案号：粤ICP备14025123号-8A',
            style: TextStyle(fontSize: 9, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          Text(
            'Copyright©2017-${DateTime.now().year} 深圳市泛媒网络有限公司',
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
