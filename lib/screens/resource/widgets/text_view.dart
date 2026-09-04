import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/material.dart';

import 'center_column.dart';

/// 文本资源视图
class TextView extends StatefulWidget {
  final String url;
  final bool hasAddress;

  const TextView({
    super.key,
    required this.url,
    required this.hasAddress,
  });

  @override
  State<TextView> createState() => _TextViewState();
}

class _TextViewState extends State<TextView> {
  String? _text;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.hasAddress) {
      _loadText();
    }
  }

  Future<void> _loadText() async {
    setState(() => _loading = true);
    try {
      final Response<List<int>> resp = await Dio().get<List<int>>(
        widget.url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (int? s) => s != null && s >= 200 && s < 300,
        ),
      );
      final List<int>? bytes = resp.data;
      if (!mounted) return;
      setState(() {
        _text = (bytes == null || bytes.isEmpty)
            ? ''
            : _decodeText(
                bytes,
                resp.headers.value(Headers.contentTypeHeader),
              );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _text = null;
        _loading = false;
      });
    }
  }

  /// 文本解码：优先按响应头 charset；未声明或声明 UTF-8 时先严格按 UTF-8 解码，
  /// 失败（中文文本常见 GBK/GB2312 编码）再回退 GBK，避免乱码。
  static String _decodeText(List<int> bytes, String? contentType) {
    final String charset = _charsetOf(contentType);
    final bool declaredGbk = charset.isNotEmpty && !charset.contains('utf');
    if (declaredGbk) {
      try {
        return gbk.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      try {
        return gbk.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
  }

  /// 从 Content-Type 中提取 charset（如 text/plain; charset=gbk）
  static String _charsetOf(String? contentType) {
    if (contentType == null) return '';
    final Match? m = RegExp(
      "charset\\s*=\\s*[\"']?([^\"';,\\s]+)",
      caseSensitive: false,
    ).firstMatch(contentType);
    return m == null ? '' : m.group(1)!.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    final String? text = _text;
    if (text == null) {
      return const CenterColumn(icon: Icons.error_outline, text: '文本加载失败');
    }
    if (text.isEmpty) {
      return const CenterColumn(
          icon: Icons.article_outlined, text: '该资源暂无文本内容');
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 120),
      // 仅展示，不做选中/复制；单击事件交由外层 GestureDetector 控制栏显隐
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, height: 1.7, color: Colors.white),
      ),
    );
  }
}