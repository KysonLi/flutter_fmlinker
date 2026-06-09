import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String? title;

  const WebViewScreen({super.key, required this.url, this.title});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _pageTitle;
  bool _loadFailed = false;
  String? _errorMessage;
  bool _pageLoaded = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'Flutter',
        onMessageReceived: (JavaScriptMessage message) {
          print('JavaScript message: ${message.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();
            
            if (_isExternalProtocol(url)) {
              _launchExternalUrl(url);
              return NavigationDecision.prevent;
            }
            
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            print('Page started loading: $url');
          },
          onPageFinished: (String url) {
            print('Page finished loading: $url');
            setState(() {
              _isLoading = false;
              _loadFailed = false;
              _errorMessage = null;
              _pageLoaded = true;
            });
            _controller.getTitle().then((title) {
              setState(() {
                _pageTitle = title;
              });
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView resource error: ${error.description}, code: ${error.errorCode}, url: ${error.url}');
            
            if (!_pageLoaded) {
              setState(() {
                _isLoading = false;
                _loadFailed = true;
                _errorMessage = error.description;
              });
            }
          },
        ),
      );

    _loadUrl();
  }

  bool _isExternalProtocol(String url) {
    final protocols = [
      'tel:', 
      'mailto:', 
      'sms:', 
      'intent:',
      'market:',
      'geo:',
      'maps:',
      'fb:',
      'twitter:',
      'whatsapp:',
      'weixin:',
      'alipays:',
      'mpr:',
      'itms-apps:',
      'itms-services:',
      'android-app:',
    ];
    
    for (final protocol in protocols) {
      if (url.startsWith(protocol)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _launchExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        print('Cannot launch URL: $url');
        EasyLoading.showError('无法打开此链接');
      }
    } catch (e) {
      print('Failed to launch URL: $e');
      EasyLoading.showError('打开链接失败');
    }
  }

  Future<void> _loadUrl() async {
    try {
      String url = widget.url.trim();
      
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      
      final uri = Uri.parse(url);
      print('Loading URL: $uri');
      _controller.loadRequest(uri);
    } catch (e) {
      print('Error loading URL: $e');
      setState(() {
        _isLoading = false;
        _loadFailed = true;
        _errorMessage = 'URL解析失败: $e';
      });
    }
  }

  void _refresh() {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
      _errorMessage = null;
      _pageLoaded = false;
    });
    _loadUrl();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? _pageTitle ?? '网页', style: const TextStyle(fontSize: 14)),
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
          if (_isLoading && !_pageLoaded)
            const Center(child: CircularProgressIndicator()),
          if (_loadFailed)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('加载失败'),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(_errorMessage!),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('重新加载'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
