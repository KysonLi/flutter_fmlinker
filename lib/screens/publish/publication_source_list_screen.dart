import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/resource/resource_entry.dart';
import 'package:fmlink/screens/publish/widgets/book_info_card.dart';
import 'package:fmlink/screens/publish/widgets/chapter_header.dart';
import 'package:fmlink/screens/publish/widgets/source_item.dart';

class PublicationSourceListScreen extends StatefulWidget {
  final String goodsId;
  final String goodsName;
  final String goodsImage;
  final String serviceCode;
  final String prefixCode;
  final int versionCode;
  final List<dynamic> resourceFormats;

  const PublicationSourceListScreen({
    super.key,
    required this.goodsId,
    required this.goodsName,
    required this.goodsImage,
    required this.serviceCode,
    required this.prefixCode,
    required this.versionCode,
    required this.resourceFormats,
  });

  @override
  State<PublicationSourceListScreen> createState() => _PublicationSourceListScreenState();
}

class _PublicationSourceListScreenState extends State<PublicationSourceListScreen> {
  final PublishService _publishService = PublishService();
  final UserService _userService = UserService();
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);
  final ValueNotifier<bool> _showAffixTitle = ValueNotifier(false);
  final GlobalKey _bookInfoKey = GlobalKey();

  List<dynamic> _chapterGroups = [];
  int _totalChapters = 0;
  int _totalSources = 0;
  int _totalCodes = 0;
  bool _isLoading = false;
  double _affixThreshold = 0;
  
  int _pageIndex = 1;
  final int _pageSize = 50;
  bool _hasMore = true;
  List<dynamic> _allSources = [];

  Future<void> _loadSources({bool isRefresh = false}) async {
    if (_isLoading) return;
    if (!isRefresh && !_hasMore) return;
    
    _isLoading = true;
    if (!isRefresh) {
      EasyLoading.show();
    }

    try {
      await _userService.refreshToken();
      
      String? unificationId = await _userService.getUnificationId();
      if (unificationId.isEmpty) {
        unificationId = await DeviceInfoUtil.getDeviceId();
      }

      Map<String, dynamic> response = await _publishService.getPublicationSourceList(
        widget.serviceCode,
        widget.prefixCode,
        versionCode: widget.versionCode,
        unificationId: unificationId,
        page: isRefresh ? 1 : _pageIndex,
        pageSize: _pageSize,
      );

      if (response['status'] && response['data'] != null) {
        Map<String, dynamic> data = response['data'];
        
        setState(() {
          _totalChapters = int.tryParse(data['chapter']?.toString() ?? '0') ?? 0;
          _totalSources = int.tryParse(data['resourceCount']?.toString() ?? '0') ?? 0;
          _totalCodes = int.tryParse(data['sourceCount']?.toString() ?? '0') ?? 0;
          
          List<dynamic> sources = data['sourceList'] ?? [];
          
          if (isRefresh) {
            _allSources = sources;
            _pageIndex = 2; // 已加载第 1 页，下次加载从第 2 页继续
          } else {
            _allSources.addAll(sources);
            _pageIndex++;
          }
          
          _hasMore = sources.length >= _pageSize;
          _chapterGroups = _groupByChapter(_allSources);
        });
        
        _onDataLoaded();
      }
    } catch (e) {
      EasyLoading.showToast('获取链码列表失败: $e');
    } finally {
      _isLoading = false;
      EasyLoading.dismiss();
      if (isRefresh) {
        _refreshController.finishRefresh();
        _refreshController.resetFooter();
      } else {
        _refreshController.finishLoad(
          _hasMore ? IndicatorResult.success : IndicatorResult.noMore,
        );

      }
    }
  }

  List<dynamic> _groupByChapter(List<dynamic> sources) {
    Map<String, dynamic> groups = {};
    
    for (var source in sources) {
      String chapter = source['chapter']?.toString() ?? '';
      String chapterTitle = source['chapterTitle']?.toString() ?? '';
      String article = source['article']?.toString() ?? '';
      
      String key = '$article-$chapter';
      
      if (!groups.containsKey(key)) {
        groups[key] = {
          'article': article,
          'chapter': chapter,
          'chapterTitle': chapterTitle,
          'sources': [],
        };
      }
      groups[key]['sources'].add(source);
    }
    
    return groups.values.toList()..sort((a, b) {
      int articleA = int.tryParse(a['article'] ?? '0') ?? 0;
      int articleB = int.tryParse(b['article'] ?? '0') ?? 0;
      if (articleA != articleB) return articleA.compareTo(articleB);
      int chapterA = int.tryParse(a['chapter'] ?? '0') ?? 0;
      int chapterB = int.tryParse(b['chapter'] ?? '0') ?? 0;
      return chapterA.compareTo(chapterB);
    });
  }

  /// 点击链码条目 → 以 sourceIdentifier 进入资源模块
  void _handleSourceTap(dynamic source) {
    final String? sourceIdentifier = source['sourceIdentifier']?.toString();
    if (sourceIdentifier == null || sourceIdentifier.isEmpty) {
      EasyLoading.showToast('暂无链码信息');
      return;
    }
    ResourceEntry.openFromCode(
      context,
      isliCode: sourceIdentifier.replaceAll('-', ''),
      fromScan: false,
    );
  }

  void _onRefresh() {
    _loadSources(isRefresh: true);
  }

  void _onLoading() {
    _loadSources(isRefresh: false);
  }

  void _onScroll(double offset) {
    _scrollOffset.value = offset;
    _showAffixTitle.value = offset >= _affixThreshold;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      _onScroll(_scrollController.offset);
    });
    _loadSources();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateAffixThreshold();
    });
  }

  void _calculateAffixThreshold() {
    if (_bookInfoKey.currentContext != null) {
      final RenderBox renderBox = _bookInfoKey.currentContext!.findRenderObject() as RenderBox;
      // _affixThreshold = 图书信息卡高度 + 25
      _affixThreshold = renderBox.size.height + 25;
      setState(() {});
    }
  }

  void _onDataLoaded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateAffixThreshold();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollOffset.dispose();
    _showAffixTitle.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '总计章节数: $_totalChapters',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF666666),
            ),
          ),
          Text(
            '链码 $_totalCodes | 资源 $_totalSources',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF666666),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterList() {
    if (_chapterGroups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('暂无链码数据')),
      );
    }

    return Column(
      children: _chapterGroups.map((group) {
        String article = group['article']?.toString() ?? '';
        String chapter = group['chapter']?.toString() ?? '';
        String chapterTitle = group['chapterTitle']?.toString() ?? '';
        List<dynamic> sources = group['sources'] ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChapterHeader(
              article: article,
              chapter: chapter,
              chapterTitle: chapterTitle,
            ),
            ...sources.asMap().entries.map((entry) {
              dynamic source = entry.value;
              return SourceItem(
                sourceNo: source['sourceNo']?.toString() ?? '${entry.key + 1}',
                sourceFragment: source['sourceFragment']?.toString() ?? '',
                sourceIdentifier: source['sourceIdentifier']?.toString() ?? '',
                resourceCount: source['resourceCount'] ?? 0,
                bookPageNo: source['bookPageNo'] ?? 0,
                free: source['free'],
                price: source['price'],
                pay: source['pay'],
                onTap: () => _handleSourceTap(source),
              );
            }),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          widget.goodsImage.isNotEmpty
              ? Image.network(
                  widget.goodsImage,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset('assets/images/default_cover.png', fit: BoxFit.cover);
                  },
                )
              : Image.asset('assets/images/default_cover.png', fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: const Color.fromARGB(150, 0, 0, 0),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedBuilder(
          animation: _showAffixTitle,
          builder: (context, child) {
            bool showAffix = _showAffixTitle.value;
            return AppBar(
              backgroundColor: showAffix ? Colors.white : Colors.transparent,
              elevation: showAffix ? 4 : 0,
              title: showAffix
                  ? Text(
                      widget.goodsName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
              leading: IconButton(
                icon: Icon(
                  Icons.chevron_left,
                  // 透明背景时白色，白底吸顶后变黑色
                  color: showAffix ? Colors.black : Colors.white,
                  size: 28,
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          _buildBackground(),
          EasyRefresh(
            controller: _refreshController,
            onRefresh: () => _onRefresh(),
            onLoad: () => _onLoading(),
            header: const ClassicHeader(
              dragText: '下拉刷新',
              processingText: '加载中...',
              readyText: '释放刷新',
              processedText: '刷新完成',
              textStyle: TextStyle(fontSize: 12, color: Colors.white),
              messageText: '更新于 %T',
              messageStyle: TextStyle(fontSize: 10, color: Colors.white),
              iconTheme: IconThemeData(color: Colors.white),
              triggerOffset: 70,
            ),
            footer: const ClassicFooter(
              processedText: '加载完成',
              processingText: '加载中',
              failedText: '加载失败',
              noMoreText: '暂无更多数据',
              textStyle: TextStyle(fontSize: 12, color: Colors.grey),
              showMessage: false,
              backgroundColor: Colors.white,
            ),
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 40),
              children: [
                BookInfoCard(
                  key: _bookInfoKey,
                  goodsName: widget.goodsName,
                  goodsImage: widget.goodsImage,
                  resourceFormats: widget.resourceFormats,
                ),
                Container(
                  // 数据量少时撑满屏幕剩余高度，避免底部露出模糊背景图
                  // 剩余高度 = 屏高 - 顶部padding(40) - 图书信息卡高度(affixThreshold - 25)
                  constraints: BoxConstraints(
                    minHeight: _affixThreshold > 0
                        ? MediaQuery.of(context).size.height -
                            15 -
                            _affixThreshold
                        : 0,
                  ),
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    color: Colors.white,
                  ),
                  child: Column(
                    children: [
                      _buildHeader(),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      _buildChapterList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
