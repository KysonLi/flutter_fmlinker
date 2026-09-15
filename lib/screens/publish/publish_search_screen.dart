import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/models/publisher_model.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';

/// 出版物/出版者搜索页
class PublishSearchScreen extends StatefulWidget {
  const PublishSearchScreen({super.key});

  @override
  State<PublishSearchScreen> createState() => _PublishSearchScreenState();
}

class _PublishSearchScreenState extends State<PublishSearchScreen> {
  static const String _historyKey = 'publish_search_history';
  static const int _maxHistory = 10;

  final PublishService _publishService = PublishService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // 历史记录
  List<String> _history = [];

  // 搜索结果
  List<dynamic> _publications = [];
  List<PublisherModel> _publishers = [];

  bool _hasSearched = false;
  bool _isSearching = false;
  String? _errorMessage;
  String _lastKeyword = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------- 历史记录 ----------

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _history = prefs.getStringList(_historyKey) ?? [];
    });
  }

  Future<void> _saveHistory(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(_history);
    list
      ..remove(keyword)
      ..insert(0, keyword);
    if (list.length > _maxHistory) {
      list.removeRange(_maxHistory, list.length);
    }
    await prefs.setStringList(_historyKey, list);
    if (mounted) {
      setState(() => _history = list);
    }
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) {
      setState(() => _history = []);
    }
  }

  // ---------- 搜索 ----------

  void _search(String keyword) {
    final text = keyword.trim();
    if (text.isEmpty) return;
    _controller.text = text;
    _focusNode.unfocus();
    _saveHistory(text);
    _performSearch(text);
  }

  Future<void> _performSearch(String text) async {
    setState(() {
      _hasSearched = true;
      _isSearching = true;
      _errorMessage = null;
      _publications = [];
      _publishers = [];
      _lastKeyword = text;
    });

    // 同时请求出版物列表与出版者列表
    final results = await Future.wait([
      _publishService.getPublications(
        page: 1,
        pageSize: 20,
        searchText: text,
      ),
      _publishService.getPublishers(
        page: 1,
        pageSize: 20,
        searchText: text,
      ),
    ]);
    if (!mounted) return;

    final publicationsResponse = results[0];
    final publishersResponse = results[1];

    List<dynamic> publications = [];
    final bool publicationsOk = publicationsResponse['status'] == true;
    if (publicationsOk) {
      publications = _extractList(publicationsResponse['data']);
    }

    List<PublisherModel> publishers = [];
    final bool publishersOk = publishersResponse['status'] == true;
    if (publishersOk) {
      publishers = _extractList(publishersResponse['data'])
          .map((item) => PublisherModel.fromJson(item))
          .toList();
    }

    final bool allFailed = !publicationsOk && !publishersOk;
    setState(() {
      _publications = publications;
      _publishers = publishers;
      _isSearching = false;
      if (allFailed) {
        _errorMessage =
            (publicationsResponse['msg'] ?? publishersResponse['msg'])
                    ?.toString() ??
                '搜索失败，请稍后重试';
      }
    });
  }

  // 兼容后端两种返回结构：{shopList:[...]} / {list:[...]} / 直接 [...]
  List<dynamic> _extractList(dynamic data) {
    if (data is Map) {
      if (data.containsKey('shopList') && data['shopList'] is List) {
        return data['shopList'];
      }
      if (data.containsKey('list') && data['list'] is List) {
        return data['list'];
      }
    } else if (data is List) {
      return data;
    }
    return [];
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '搜索出版物 / 出版者',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 38,
                      ),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.cancel, size: 16),
                              color: Colors.grey,
                              onPressed: () {
                                _controller.clear();
                                _focusNode.requestFocus();
                              },
                            ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _search(_controller.text),
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasSearched) {
      return _buildHistoryView();
    }
    // 已搜索：优先展示结果/错误/空态
    final bool hasPublications = _publications.isNotEmpty;
    final bool hasPublishers = _publishers.isNotEmpty;
    if (_errorMessage != null && !hasPublications && !hasPublishers) {
      return _buildErrorView();
    }
    if (!hasPublications && !hasPublishers) {
      return _buildEmptyView();
    }
    return _buildResults(hasPublications, hasPublishers);
  }

  // ----- 历史记录 -----

  Widget _buildHistoryView() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 60,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              '输入关键字搜索出版物和出版者',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '历史记录',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _clearHistory,
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '清空',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _history.map((keyword) {
              return ActionChip(
                label: Text(keyword),
                labelStyle: const TextStyle(fontSize: 13),
                backgroundColor: const Color(0xFFE4E8EC),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onPressed: () => _search(keyword),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ----- 搜索结果 -----

  Widget _buildResults(bool hasPublications, bool hasPublishers) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // 第一组：出版物
        if (hasPublications) ...[
          _buildSectionHeader('出版物', _publications.length),
          ..._publications.map(_buildPublicationTile),
        ],
        if (hasPublications && hasPublishers)
          const Divider(height: 8, color: Color(0xFFF0F1F3)),
        // 第二组：出版者
        if (hasPublishers) ...[
          _buildSectionHeader('出版者', _publishers.length),
          ..._publishers.map(_buildPublisherTile),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8F9FA),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicationTile(dynamic item) {
    final String? goodsId = item['goodsId']?.toString();
    return InkWell(
      onTap: goodsId == null
          ? null
          : () => context.push('/publication-detail?goodsId=$goodsId'),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(
              imageUrl: _publicationImageOf(item),
              width: 60,
              height: 84,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['goodsName']?.toString() ?? '未知出版物',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (item.containsKey('suffixCodeCount'))
                    Text(
                      '链码: ${item['suffixCodeCount']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (item['publication'] is Map &&
                      (item['publication'] as Map).containsKey('publisher'))
                    Text(
                      '${item['publication']['publisher']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublisherTile(PublisherModel publisher) {
    return InkWell(
      onTap: publisher.shopId.isEmpty
          ? null
          : () => context.push('/publisher-detail', extra: publisher),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: publisher.logo.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: publisher.logo,
                      fit: BoxFit.contain,
                      errorWidget: (context, url, error) =>
                          _initialAvatar(publisher),
                    )
                  : _initialAvatar(publisher),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    publisher.shopName.isNotEmpty
                        ? publisher.shopName
                        : '未知出版者',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (publisher.goodsCount.isNotEmpty)
                    Text(
                      '出版物: ${publisher.goodsCount}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _initialAvatar(PublisherModel publisher) {
    return Center(
      child: Text(
        publisher.nameInitial,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _publicationImageOf(dynamic item) {
    for (final key in ['goodsImage', 'image_url', 'imageUrl', 'logo']) {
      if (item.containsKey(key) && item[key] != null) {
        return item[key].toString();
      }
    }
    return '';
  }

  // ----- 空态 / 错误 -----

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            '未找到与“$_lastKeyword”相关的内容',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? '搜索失败，请稍后重试',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _performSearch(_lastKeyword),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
