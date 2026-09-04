import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/resource/resource_service.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/resource/source_detail.dart';
import 'package:fmlink/services/user_service.dart';

/// URL 统一处理：去除反引号/空白后，http 强制转 https 并去掉端口号。
///
/// 参考 uni-app `src/utils/url.ts` 的 normalizeHttpUrl：
/// - http://xxx → https://xxx
/// - http://host:port/... → https://host/...
/// - https:// / 相对路径 / 空值 → 原样返回
String _https(String? url) {
  String s = cleanUrl(url);
  final RegExp httpPrefix = RegExp(r'^http://', caseSensitive: false);
  if (httpPrefix.hasMatch(s)) {
    s = s.replaceFirst(httpPrefix, 'https://');
    // 去掉紧随 host 之后的端口号（走默认 80/443 端口）
    final RegExp portSuffix = RegExp(
      r'^(https://[^/?#]+):\d+(?=/|$|#|\?)',
      caseSensitive: false,
    );
    s = s.replaceFirstMapped(portSuffix, (Match m) => m.group(1) ?? '');
  }
  return s;
}

/// 标志码版权详情页
///
/// 由入口（ResourceEntry.openIsliCopyright）携带 mprCode 进入，
/// 先刷新 token，再请求 /pics/v1/isliContents/:mprCode 获取版权信息。
/// 页面结构复刻小程序 `_template_....txt` 中的 copyright 页：
/// ① 出版物卡片（封面+书名+作者+出版者+定价）
/// ② 版权标识信息（ISLI/MPR/ISBN/ISSN/CN/ISRC/创建/更新时间，仅非空展示）
/// ③ 出版物简介（content 多行文本；仅 contentUrl 时提供“查看”入口）
/// ④ 关联资源入口（跳转 /publication-source-list）
class IsliCopyrightScreen extends StatefulWidget {
  /// 标志码（MPR 编码）
  final String mprCode;

  const IsliCopyrightScreen({super.key, required this.mprCode});

  @override
  State<IsliCopyrightScreen> createState() => _IsliCopyrightScreenState();
}

class _IsliCopyrightScreenState extends State<IsliCopyrightScreen> {
  bool _loading = true;
  String _errorMsg = '';
  IsliCopyrightData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ==================== 数据加载 ====================

  Future<void> _load() async {
    try {
      // 先刷新 token，再拉取版权信息（接口走独立 https 网关）
      await UserService().refreshToken();
      final Map<String, dynamic> res =
          await ResourceService().fetchIsliContents(widget.mprCode);
      if (!mounted) return;

      if (res['status'] == true && res['data'] is Map) {
        final Map<String, dynamic> raw =
            (res['data'] as Map).cast<String, dynamic>();
        if (raw.isEmpty) {
          setState(() {
            _loading = false;
            _errorMsg = '未查询到版权信息';
            _data = null;
          });
          return;
        }
        setState(() {
          _loading = false;
          _errorMsg = '';
          _data = IsliCopyrightData.fromJson(raw);
        });
      } else {
        final String msg = (res['msg']?.toString() ?? '').trim();
        setState(() {
          _loading = false;
          _errorMsg = msg.isEmpty ? '查询失败，请重试' : msg;
          _data = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = '查询失败，请重试';
        _data = null;
      });
    }
  }

  /// 失败/空态重试
  void _retry() {
    setState(() {
      _loading = true;
      _errorMsg = '';
      _data = null;
    });
    _load();
  }

  // ==================== 页面骨架 ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        title: const Text(
          '版权信息',
          style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_data == null) return _buildError();
    return _buildContent(_data!);
  }

  // ---------- 加载中 ----------

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            '加载中...',
            style: TextStyle(fontSize: 14, color: Color(0xFF8C8C8C)),
          ),
        ],
      ),
    );
  }

  // ---------- 失败/空态 ----------

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Color(0xFFBFBFBF)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _errorMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF8C8C8C)),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
              side: const BorderSide(color: Color(0xFF2F7BFF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              '重新加载',
              style: TextStyle(fontSize: 14, color: Color(0xFF2F7BFF)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 成功列表 ----------

  Widget _buildContent(IsliCopyrightData d) {
    final List<Widget> children = <Widget>[
      // ① 出版物卡片
      _card(
        _buildPubCard(d),
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        padding: const EdgeInsets.all(12),
      ),
      // ② 版权标识信息卡
      _card(_buildCodeCard(d)),
    ];

    // ③ 出版物简介（有 content 或 contentUrl 时展示）
    final Widget? intro = _buildIntroCard(d);
    if (intro != null) children.add(intro);

    // ④ 关联资源入口
    final Widget? link = _buildLinkCard(d);
    if (link != null) children.add(link);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  /// 白色圆角卡片容器（背景 F5F7FA 上的通用白卡，圆角 10）
  Widget _card(
    Widget child, {
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(12, 0, 12, 12),
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  // ==================== ① 出版物卡片 ====================

  Widget _buildPubCard(IsliCopyrightData d) {
    final String name = (d.bookName ?? '').trim();
    final String author = (d.author ?? '').trim();
    final String publisher = (d.publisherName ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面：网络图失败时用默认封面兜底
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _cover(_https(d.cover), 90, 126),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? '未知出版物' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              _pubRow(label: '作者：', value: author.isEmpty ? '未知' : author),
              const SizedBox(height: 6),
              _pubRow(
                label: '出版者：',
                value: publisher.isEmpty ? '未知' : publisher,
              ),
              const SizedBox(height: 6),
              // 定价：模板 price 形如 "6,CNY"，统一展示为 ¥6.00
              _pubRow(
                label: '定价：',
                value: _displayPrice(d),
                emphasize: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cover(String url, double width, double height) {
    final Widget fallback = Image.asset(
      'assets/images/default_cover.png',
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
    if (url.isEmpty) return fallback;
    return SizedBox(
      width: width,
      height: height,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            Container(color: const Color(0xFFF0F1F5)),
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }

  Widget _pubRow({
    required String label,
    required String value,
    bool emphasize = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8C8C8C)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 15 : 13,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
              color:
                  emphasize ? const Color(0xFFE11D48) : const Color(0xFF595959),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  /// 解析模板 price："6,CNY" → "¥ 6.00"；非法值原样返回，空值显示 ¥ 0.00
  String _displayPrice(IsliCopyrightData d) {
    final String raw = (d.price ?? '').trim();
    if (raw.isEmpty) return '¥ 0.00';
    final int comma = raw.indexOf(',');
    if (comma > 0) {
      final double? n = double.tryParse(raw.substring(0, comma).trim());
      if (n != null) return '¥ ${n.toStringAsFixed(2)}';
    }
    return raw;
  }

  // ==================== ② 版权标识信息卡 ====================

  Widget _buildCodeCard(IsliCopyrightData d) {
    final List<_CodeItem> items = <_CodeItem>[
      _CodeItem('ISLI 编码', _nonEmpty(d.isliCode), mono: true),
      _CodeItem(
        'MPR 编码',
        _nonEmpty(d.mprCode) ?? _nonEmpty(widget.mprCode),
        mono: true,
      ),
      _CodeItem('ISBN', _nonEmpty(d.isbn), mono: true),
      _CodeItem('ISSN', _nonEmpty(d.issn), mono: true),
      _CodeItem('CN 号', _nonEmpty(d.cn), mono: true),
      _CodeItem('ISRC', _nonEmpty(d.isrc), mono: true),
      _CodeItem('创建时间', _nonEmpty(d.createTime)),
      _CodeItem('更新时间', _nonEmpty(d.updateTime)),
    ]..removeWhere((_CodeItem item) => item.value == null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '版权标识信息',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2329),
          ),
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '暂无版权标识信息',
              style: TextStyle(fontSize: 13, color: Color(0xFF8C8C8C)),
            ),
          )
        else
          ...items.asMap().entries.map(
                (MapEntry<int, _CodeItem> e) => _codeRow(
                  e.value,
                  showDivider: e.key < items.length - 1,
                ),
              ),
      ],
    );
  }

  String? _nonEmpty(String? v) {
    if (v == null) return null;
    final String t = v.trim();
    return t.isEmpty ? null : t;
  }

  Widget _codeRow(_CodeItem item, {required bool showDivider}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFF5F6F8)),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              item.label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8C8C8C)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.value!,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFF1F2329),
                height: 1.5,
                // 编码类字段使用等宽数字 + 轻微字距，呈现“等宽感”
                fontFeatures: item.mono
                    ? const <FontFeature>[FontFeature.tabularFigures()]
                    : null,
                letterSpacing: item.mono ? 0.4 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ③ 出版物简介卡 ====================

  Widget? _buildIntroCard(IsliCopyrightData d) {
    final String content = (d.content ?? '').trim();
    final String contentUrl = _https(d.contentUrl);
    if (content.isEmpty && contentUrl.isEmpty) return null;

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '出版物简介',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2329),
            ),
          ),
          const SizedBox(height: 12),
          if (content.isNotEmpty)
            Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF3B3F46),
                height: 1.7,
              ),
            )
          else
            // 无简介文本但有内容地址时：提供“查看”入口
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openWebview(contentUrl),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      '查看',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF2F7BFF),
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Color(0xFF2F7BFF),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 打开通用 webview（路由 query：url/title）
  void _openWebview(String url) {
    final String name = (_data?.bookName ?? '').trim();
    final String title = name.isEmpty ? '查看' : name;
    context.push(
      '/webview?url=${Uri.encodeComponent(url)}'
      '&title=${Uri.encodeComponent(title)}',
    );
  }

  // ==================== ④ 关联资源入口 ====================

  Widget? _buildLinkCard(IsliCopyrightData d) {
    final String isliCode = (d.isliCode ?? '').trim();
    final String mprCode =
        _nonEmpty(d.mprCode) ?? _nonEmpty(widget.mprCode) ?? '';
    if (isliCode.isEmpty || mprCode.isEmpty) return null;

    return _card(
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openChainCodeList,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: const [
              Icon(Icons.list_alt, size: 22, color: Color(0xFF2F7BFF)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '查看关联资源',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1F2329),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFF8C8C8C),
              ),
            ],
          ),
        ),
      ),
      padding: EdgeInsets.zero,
    );
  }

  /// 跳转链码列表页：serviceCode = isliCode 首段（'-' 分隔），prefixCode = mprCode
  void _openChainCodeList() {
    final IsliCopyrightData d = _data!;
    final String isliCode = (d.isliCode ?? '').trim();
    final String mprCode =
        _nonEmpty(d.mprCode) ?? _nonEmpty(widget.mprCode) ?? '';
    if (isliCode.isEmpty || mprCode.isEmpty) return;
    final String serviceCode =
        isliCode.contains('-') ? isliCode.split('-').first : '';
    final String name = (d.bookName ?? '').trim();

    context.push('/publication-source-list', extra: <String, dynamic>{
      'goodsId': '',
      'goodsName': name,
      'goodsImage': _https(d.cover),
      'serviceCode': serviceCode,
      'prefixCode': mprCode,
      'versionCode': 1,
      'resourceFormats': const <dynamic>[],
    });
  }
}

/// 版权标识信息行数据
class _CodeItem {
  final String label;
  final String? value;
  final bool mono;

  const _CodeItem(this.label, this.value, {this.mono = false});
}
