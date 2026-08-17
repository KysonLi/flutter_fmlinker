import 'package:flutter/material.dart';

class ScanHelpScreen extends StatelessWidget {
  const ScanHelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码帮助', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              _buildHelpItem(
                question: '1. MPR链码是什么？',
                answer:
                    '链码是一种嵌入在纸书文本行空隙之间的、外观类似双下划线的二维码。链码用于标识纸质图文内容与线上数字内容之间的关联，通过关联构建产生更高的价值。',
                imagePath: 'assets/images/scan_help_1.png',
                imageCaption: 'MPR链码示例',
              ),
              const Divider(height: 20, color: Color(0xFFEEEEEE)),
              _buildHelpItem(
                question: '2. 哪些书籍有链码？',
                answer:
                    '印有链码的MPR出版物称之为MPR出版物（全媒版），封面上印有“MPR”标志。已有多家出版社出版了印有链码的书籍，如广东高等教育出版社、华南理工大学出版社、暨南大学出版社、广东科技出版社、广东教育出版社、广东海燕电子音像出版社等。\n\n书籍封面印有“MPR”标志的出版物除了全媒版，还有点读版，点读版的书籍仅支持用识读器点读。在APP[出版物列表]，可查看支持扫链码的书籍。',
                imagePath: 'assets/images/scan_help_2.png',
              ),
              const Divider(height: 20, color: Color(0xFFEEEEEE)),
              _buildHelpItem(
                question: '3. 如何使用扫链码功能？',
                answer: '安装泛媒关联APP后，允许APP访问设备相机，点击扫码（默认扫链码），对准链码的位置扫码即可。',
              ),
              const Divider(height: 20, color: Color(0xFFEEEEEE)),
              _buildHelpItem(
                question: '4. 扫码后会获得什么信息？',
                answer: '扫链码能够查看被标识内容关联的图文、视频、音频、3D等数字媒体内容，丰富认知，体验增值阅读的乐趣。',
              ),
              const Divider(height: 20, color: Color(0xFFEEEEEE)),
              _buildHelpItem(
                question: '5. 什么是ISLI？',
                answer:
                    'ISLI是国际标准关联标识符（International Standard Link Identifier）英文首字母的缩写。ISLI国际标准是在国际信息与文献标识符标准领域首次由中国提案并主导、由国际标准化组织（ISO）主持制定的一项标准。\n\nISLI国际标准规定了信息与文献领域中可被唯一识别的实体之间关联的标识符。\n\nISLI国际标准规定了源和目标之间的关联模型，关联模型包含了三个基本要素：源、目标、源和目标的关联。源和目标是分别的实体，源是作为关联起点的实体，目标是作为关联终点的实体，源与目标的关联是ISLI所标识的对象。',
                imagePath: 'assets/images/scan_help_5.png',
              ),
              const Divider(height: 20, color: Color(0xFFEEEEEE)),
              _buildHelpItem(
                question: '6. ISLI标志码是什么？',
                answer:
                    'ISLI标志码是内容产品应用ISLI标准的标志。基于ISLI标志码为出版企业出版的每一本图书分配标识唯一身份ID的编码，实现正版图书版权保护和鉴伪能力。\n\n注：ISLI标志码位于书籍封底\n\n如下图所示的ISLI标志码，可以用泛媒关联APP扫码识别，也可以用识读器点读识别：',
                imagePath: 'assets/images/scan_help_6_1.png',
                imageCaption: '标志码示例',
                additionalImages: [
                  _HelpImage(
                    'assets/images/scan_help_6_2.png',
                    '如下图所示的ISLI标志码，仅支持识读器点读识别：',
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFEEEEEE)),
              _buildHelpItem(
                question: '7. 扫描ISLI标志码会获得什么信息？',
                answer: '在线获取图书版权认证信息、图书简介等。',
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpItem({
    required String question,
    required String answer,
    String? imagePath,
    String? imageCaption,
    List<_HelpImage>? additionalImages,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Text(
            answer,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              height: 1.6,
            ),
          ),
        ),
        if (imagePath != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFEEEEEE)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Image.asset(imagePath, fit: BoxFit.contain),
            ),
          ),
          if (imageCaption != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 20),
              child: Center(
                child: Text(
                  imageCaption,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
        ],
        if (additionalImages != null && additionalImages.isNotEmpty)
          ...additionalImages.map((item) {
            return Padding(
              padding: const EdgeInsets.only(left: 20, right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    item.caption,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Image.asset(item.path, fit: BoxFit.contain),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _HelpImage {
  final String path;
  final String caption;
  const _HelpImage(this.path, this.caption);
}
