import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BookHelpScreen extends StatefulWidget {
  const BookHelpScreen({Key? key}) : super(key: key);

  @override
  State<BookHelpScreen> createState() => _BookHelpScreenState();
}

class _BookHelpScreenState extends State<BookHelpScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      );
    
    _loadHtmlContent();
  }

  Future<String> _imageToBase64(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return base64Encode(byteData.buffer.asUint8List());
  }

  Future<void> _loadHtmlContent() async {
    try {
      String htmlContent = await rootBundle.loadString('assets/html/book/link_book_help.html');
      
      String mprLogoBase64 = await _imageToBase64('assets/html/book/MPRlogo@3x.png');
      String mpr1Base64 = await _imageToBase64('assets/html/book/mpr1@3x.png');
      String mpr2Base64 = await _imageToBase64('assets/html/book/mpr2@3x.png');
      String mpr3Base64 = await _imageToBase64('assets/html/book/mpr3@3x.png');

      htmlContent = htmlContent
          .replaceAll('./MPRlogo@3x.png', 'data:image/png;base64,$mprLogoBase64')
          .replaceAll('./mpr1@3x.png', 'data:image/png;base64,$mpr1Base64')
          .replaceAll('./mpr2@3x.png', 'data:image/png;base64,$mpr2Base64')
          .replaceAll('./mpr3@3x.png', 'data:image/png;base64,$mpr3Base64');

      _controller.loadRequest(
        Uri.dataFromString(
          htmlContent,
          mimeType: 'text/html',
          encoding: Encoding.getByName('utf-8'),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Error loading HTML: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('出版问题', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
