import 'package:flutter/material.dart';
import 'package:fmlink/screens/publish/widgets/chapter_header.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';

/// 链码列表弹层（全书所有链码）API 契约
///
/// 由资源播放页/资源列表页的「链码列表」按钮触发；展示全书链码（按章节分组），
/// 选择某条链码后切换当前资源入口 isliCode。
///
/// 数据来源：PublishService().getPublicationSourceList(serviceCode, prefixCode)
/// 分组方式与 lib/screens/publish/publication_source_list_screen.dart 保持一致。

/// 链码选择结果
class ChainCodeSelection {
  /// 选中链码（纯数字，可作 isliCode 直接请求资源）
  final String isliCode;

  /// 链码序号
  final int? sourceNo;

  /// 所在图书页码
  final int? bookPageNo;

  /// 链码摘要/片段
  final String? sourceFragment;

  const ChainCodeSelection({
    required this.isliCode,
    this.sourceNo,
    this.bookPageNo,
    this.sourceFragment,
  });
}

/// 弹出全书链码选择弹层（底部抽屉），返回选中的链码；取消返回 null。
///
/// [serviceCode]/[prefixCode] 当前出版物的服务码/前缀码；
/// [versionCode] 出版物版本号（可为空，为空时使用链码列表接口返回的 versionCode）；
/// [currentIsliCode] 当前正在播放的链码（纯数字），用于高亮当前项。
Future<ChainCodeSelection?> showChainCodeSheet(
  BuildContext context, {
  required String serviceCode,
  required String prefixCode,
  String? versionCode,
  String? currentIsliCode,
}) {
  return showModalBottomSheet<ChainCodeSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ChainCodeSheet(
      serviceCode: serviceCode,
      prefixCode: prefixCode,
      versionCode: versionCode,
      currentIsliCode: currentIsliCode,
    ),
  );
}

/// 当前链码命中高亮色（与源列表「当前」标记一致）
const Color _kCurrentColor = Color(0xFF00AFFE);

/// 链码列表底部抽屉
class _ChainCodeSheet extends StatefulWidget {
  final String serviceCode;
  final String prefixCode;
  final String? versionCode;
  final String? currentIsliCode;

  const _ChainCodeSheet({
    required this.serviceCode,
    required this.prefixCode,
    this.versionCode,
    this.currentIsliCode,
  });

  @override
  State<_ChainCodeSheet> createState() => _ChainCodeSheetState();
}

class _ChainCodeSheetState extends State<_ChainCodeSheet> {
  final PublishService _publishService = PublishService();
  final UserService _userService = UserService();

  bool _loading = true;
  bool _failed = false;
  String _errorMsg = '加载失败，请重试';

  /// 按 篇/章 分组后的链码（结构同 publication_source_list_screen）
  List<Map<String, dynamic>> _groups = [];

  /// 出版物名（接口 data 中有则展示，无则标题回退「链码列表」）
  String _goodsName = '';

  /// 链码总数（优先接口 sourceCount，其次按已收集条数）
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _digitsOnly(dynamic v) =>
      (v?.toString() ?? '').replaceAll(RegExp(r'\D'), '');

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  /// 当前项与选中码是否相同（currentIsliCode 已为纯数字，做归一比较）
  bool _isCurrent(dynamic source) {
    final String code = _digitsOf(source);
    if (code.isEmpty) return false;
    final String current = _digitsOnly(widget.currentIsliCode);
    if (current.isEmpty) return false;
    return current.length >= 21
        ? code == current
        : code == current.padLeft(21, '0');
  }

  /// 组装该项全量 21 位纯数字链码：
  /// 优先 sourceIdentifier（完整含 serviceCode+prefixCode+suffixCode），
  /// 否则按 serviceCode+prefixCode+suffixCode 拼接，均去掉非数字字符。
  String _digitsOf(dynamic source) {
    if (source is! Map) return '';
    final String identifier = _digitsOnly(source['sourceIdentifier']);
    if (identifier.isNotEmpty && identifier.length == 21) return identifier;

    final String service = _digitsOnly(source['serviceCode']);
    final String prefix = _digitsOnly(source['prefixCode']);
    final String suffix = _digitsOnly(source['suffixCode']);
    final String combined =
        (service.isNotEmpty ? service : _digitsOnly(widget.serviceCode)) +
            (prefix.isNotEmpty ? prefix : _digitsOnly(widget.prefixCode)) +
            suffix;
    final String digits = _digitsOnly(combined);
    if (digits.length == 21) return digits;
    if (identifier.isNotEmpty) return identifier.padLeft(21, '0');
    if (digits.isNotEmpty) return digits.padLeft(21, '0');
    return '';
  }

  /// 拉取全书链码（page/pageSize 循环取全）
  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }

    try {
      await _userService.refreshToken();

      // 未登录时回退设备 ID（与资源模块口径一致）
      String unificationId = await _userService.getUnificationId();
      if (unificationId.isEmpty) {
        unificationId = await DeviceInfoUtil.getDeviceId();
      }

      final List<dynamic> all = <dynamic>[];
      int page = 1;
      const int pageSize = 200;
      int? dataVersion; // 接口返回的版本号，供后续页使用
      final int initVersion = int.tryParse(widget.versionCode ?? '') ?? 1;

      while (true) {
        final Map<String, dynamic> response =
            await _publishService.getPublicationSourceList(
          widget.serviceCode,
          widget.prefixCode,
          versionCode: dataVersion ?? initVersion,
          page: page,
          pageSize: pageSize,
          unificationId: unificationId,
        );

        if (response['status'] != true || response['data'] == null) {
          if (mounted) {
            setState(() {
              _failed = true;
              _loading = false;
              _errorMsg = response['msg']?.toString() ?? '获取链码列表失败';
            });
          }
          return;
        }

        final Map<String, dynamic> data =
            (response['data'] as Map).cast<String, dynamic>();
        final List<dynamic> sources =
            data['sourceList'] is List ? data['sourceList'] as List : <dynamic>[];
        all.addAll(sources);

        if (_goodsName.isEmpty && data['goodsName'] != null) {
          _goodsName = data['goodsName'].toString();
        }
        final int? sourceCount = _toInt(data['sourceCount']);
        if (sourceCount != null) _total = sourceCount;
        final int? pageVersion = _toInt(data['versionCode']);
        if (pageVersion != null) dataVersion = pageVersion;

        // 本页不足一页视为已取全
        if (sources.length < pageSize) break;
        page++;
      }

      if (!mounted) return;
      setState(() {
        if (_total == 0) _total = all.length;
        _groups = _groupByChapter(all);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  /// 分组方式与 publication_source_list_screen.dart 保持一致：
  /// 键 article-chapter，按 篇→章 数值升序
  List<Map<String, dynamic>> _groupByChapter(List<dynamic> sources) {
    final Map<String, Map<String, dynamic>> groups =
        <String, Map<String, dynamic>>{};

    for (final dynamic source in sources) {
      if (source is! Map) continue;
      final String article = source['article']?.toString() ?? '';
      final String chapter = source['chapter']?.toString() ?? '';
      final String chapterTitle = source['chapterTitle']?.toString() ?? '';
      final String key = '$article-$chapter';

      if (!groups.containsKey(key)) {
        groups[key] = <String, dynamic>{
          'article': article,
          'chapter': chapter,
          'chapterTitle': chapterTitle,
          'sources': <dynamic>[],
        };
      }
      (groups[key]!['sources'] as List<dynamic>).add(source);
    }

    final List<Map<String, dynamic>> result = groups.values.toList();
    result.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int articleA = int.tryParse(a['article']?.toString() ?? '') ?? 0;
      final int articleB = int.tryParse(b['article']?.toString() ?? '') ?? 0;
      if (articleA != articleB) return articleA.compareTo(articleB);
      final int chapterA = int.tryParse(a['chapter']?.toString() ?? '') ?? 0;
      final int chapterB = int.tryParse(b['chapter']?.toString() ?? '') ?? 0;
      return chapterA.compareTo(chapterB);
    });
    return result;
  }

  void _selectSource(dynamic source) {
    if (source is! Map) return;
    final String code = _digitsOf(source);
    if (code.isEmpty) return;
    Navigator.of(context).pop(ChainCodeSelection(
      isliCode: code,
      sourceNo: _toInt(source['sourceNo']),
      bookPageNo: _toInt(source['bookPageNo']),
      sourceFragment: source['sourceFragment']?.toString(),
    ));
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final double sheetHeight = MediaQuery.of(context).size.height * 0.78;
    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final String title = _goodsName.isNotEmpty ? _goodsName : '链码列表';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _loading ? '加载中…' : '共 $_total 条链码',
            style: const TextStyle(fontSize: 12, color: Color(0xFF909399)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.wifi_off, size: 48, color: Color(0xFFC0C4CC)),
            const SizedBox(height: 12),
            Text(
              _errorMsg,
              style: const TextStyle(fontSize: 13, color: Color(0xFF909399)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_groups.isEmpty) {
      return const Center(
        child: Text(
          '暂无链码数据',
          style: TextStyle(fontSize: 14, color: Color(0xFF909399)),
        ),
      );
    }
    return _buildList();
  }

  Widget _buildList() {
    final List<Widget> children = <Widget>[];
    int index = 0;
    for (final Map<String, dynamic> group in _groups) {
      children.add(ChapterHeader(
        article: group['article']?.toString(),
        chapter: group['chapter']?.toString() ?? '',
        chapterTitle: group['chapterTitle']?.toString() ?? '',
      ));
      final List<dynamic> sources =
          group['sources'] is List ? group['sources'] as List : <dynamic>[];
      for (final dynamic source in sources) {
        children.add(_buildSourceRow(source, index));
        index++;
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: children,
    );
  }

  Widget _buildSourceRow(dynamic source, int index) {
    if (source is! Map) return const SizedBox.shrink();
    final bool current = _isCurrent(source);
    final String sourceNo = source['sourceNo']?.toString() ?? '${index + 1}';
    final String fragment = source['sourceFragment']?.toString() ?? '';
    final String identifier = source['sourceIdentifier']?.toString() ?? '';
    final String titleText =
        fragment.isNotEmpty ? fragment : (identifier.isNotEmpty ? identifier : '链码');
    final int? bookPageNo = _toInt(source['bookPageNo']);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: InkWell(
        onTap: () => _selectSource(source),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                sourceNo,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: current ? _kCurrentColor : const Color(0xFF4F5960),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      titleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: current ? _kCurrentColor : const Color(0xFF585959),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bookPageNo != null && bookPageNo > 0
                          ? '页码 P$bookPageNo'
                          : '页码 P-',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ),
              if (current) _buildTag('当前', _kCurrentColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 8, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9, color: Colors.white),
      ),
    );
  }
}
