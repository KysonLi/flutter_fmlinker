import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';
import 'package:fmlink/models/publisher_model.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/common/refresh_config.dart';

class PublisherDetailScreen extends StatefulWidget {
  final PublisherModel publisher;

  const PublisherDetailScreen({super.key, required this.publisher});

  @override
  State<PublisherDetailScreen> createState() => _PublisherDetailScreenState();
}

class _PublisherDetailScreenState extends State<PublisherDetailScreen> {
  final PublishService _publishService = PublishService();
  final UserService _userService = UserService();
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier(0.0);

  List<dynamic> _publications = [];
  int _pageIndex = 1;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const double _maxScrollExtent = 150.0;
  String _description = '';
  bool _isDescriptionExpanded = false;
  String _goodsCount = '0';

  double get _scrollOffset => _scrollOffsetNotifier.value;

  @override
  void initState() {
    super.initState();
    _description = widget.publisher.shopBrief ?? '';
    _goodsCount = widget.publisher.goodsCount;
    _scrollController.addListener(_onScroll);
    EasyLoading.show(status: '加载中...');
    _loadPublications();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollOffsetNotifier.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  void _onScroll() {
    double newOffset = _scrollController.offset.clamp(0.0, _maxScrollExtent);
    if ((newOffset - _scrollOffset).abs() > 10) {
      _scrollOffsetNotifier.value = newOffset;
    }
  }

  double get _appBarOpacity {
    if (_scrollOffset <= 0) return 0.0;
    if (_scrollOffset >= _maxScrollExtent) return 1.0;
    return _scrollOffset / _maxScrollExtent;
  }

  Color get _titleColor {
    return _appBarOpacity > 0.5 ? Colors.black : Colors.white;
  }

  String _getShopId() {
    return widget.publisher.shopId;
  }

  Future<void> _loadPublications({bool isRefresh = false}) async {
    if (isRefresh) {
      _pageIndex = 1;
      _hasMore = true;
    }

    if (!_hasMore || _isLoadingMore) return;

    setState(() {
      if (!isRefresh) {
        _isLoadingMore = true;
      }
    });

    try {
      await _userService.refreshToken();

      Map<String, dynamic> response = await _publishService
          .getPublicationsByShopId(
            _getShopId(),
            page: _pageIndex,
            pageSize: _pageSize,
          );

      if (response['status'] && response['data'] != null) {
        List<dynamic> newPublications = response['data']['list'] ?? [];
        String count = response['data']['count']?.toString() ?? '0';
        setState(() {
          if (count.isNotEmpty) {
            _goodsCount = count;
          }
          if (newPublications.isNotEmpty && _description.isEmpty) {
            dynamic book = newPublications[0];
            _description = book['shopBrief']?.toString() ?? '';
          }
          if (isRefresh) {
            _publications = newPublications;
          } else {
            _publications.addAll(newPublications);
          }
          _hasMore = newPublications.length >= _pageSize;
          _pageIndex++;
        });
      }
    } catch (e) {
      EasyLoading.showToast('获取出版物列表失败: $e');
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
      EasyLoading.dismiss();
      if (isRefresh) {
        _refreshController.finishRefresh();
      } else {
        _refreshController.finishLoad(
          _hasMore ? IndicatorResult.success : IndicatorResult.noMore,
        );
      }
    }
  }

  void _onRefresh() {
    _loadPublications(isRefresh: true);
  }

  void _onLoading() {
    _loadPublications();
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(color: Colors.white),
          child: Stack(
            children: [
              Image.asset(
                'assets/images/publisher_header_bg.png',
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
              ),
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: Container(
                  width: double.infinity,
                  height: 100,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/images/publisher_logo_bg.png'),
                      fit: BoxFit.fill,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        child:
                            widget.publisher.logo.isNotEmpty
                                ? CachedNetworkImage(
                                  imageUrl: widget.publisher.logo,
                                  fit: BoxFit.contain,
                                  errorWidget:
                                      (context, url, error) => Image.asset(
                                        'assets/images/publisher_logo_default.png',
                                        fit: BoxFit.contain,
                                      ),
                                )
                                : Image.asset(
                                  'assets/images/publisher_logo_default.png',
                                  fit: BoxFit.contain,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.publisher.shopName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      _description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.left,
                      maxLines: _isDescriptionExpanded ? null : 1,
                      overflow:
                          _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                    ),
                  ),
                  if (!_isDescriptionExpanded)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isDescriptionExpanded = true;
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'MPR出版物（全媒版）数量：$_goodsCount',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                textAlign: TextAlign.left,
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16, color: Color(0xFFEEEEEE)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedBuilder(
          animation: _scrollOffsetNotifier,
          builder: (context, child) {
            double opacity = _appBarOpacity;
            Color titleColor = opacity > 0.5 ? Colors.black : Colors.white;
            return AppBar(
              title: Text(
                '出版者',
                style: TextStyle(fontSize: 14, color: titleColor),
              ),
              backgroundColor:
                  opacity > 0
                      ? Colors.white.withOpacity(opacity)
                      : Colors.transparent,
              centerTitle: true,
              leading: IconButton(
                icon: Icon(Icons.chevron_left, color: titleColor, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              elevation: opacity > 0.5 ? 4 : 0,
            );
          },
        ),
      ),
      body: EasyRefresh(
        controller: _refreshController,
        onRefresh: () => _onRefresh(),
        onLoad: () => _onLoading(),
        header: RefreshConfig.buildHeader(),
        footer: RefreshConfig.buildFooter(),
        // 关键：让 EasyRefresh 充满全屏，不避让 AppBar
        clipBehavior: Clip.none,
        child: ListView.builder(
          controller: _scrollController,
          cacheExtent: 800,
          // 关键：关闭 ListView 默认的顶部 padding
          padding: EdgeInsets.zero,
          itemCount: _publications.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildHeader();
            }
            final publication = _publications[index - 1];
            return Column(
              children: [
                PublicationItem(publication: publication),
                const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 100),
              ],
            );
          },
        ),
      ),
    );
  }
}

class PublicationItem extends StatelessWidget {
  final dynamic publication;

  const PublicationItem({super.key, required this.publication});

  String _getPublicationType(dynamic type) {
    if (type is int) {
      switch (type) {
        case 1:
          return 'ISBN';
        case 2:
          return 'CN';
        case 3:
          return 'ISSN';
        case 4:
          return 'ISRC';
        default:
          return 'ISBN';
      }
    }
    return 'ISBN';
  }

  @override
  Widget build(BuildContext context) {
    String coverUrl = publication['goodsImage'] ?? '';
    String goodsName = publication['goodsName'] ?? '';
    String goodsId = publication['goodsId']?.toString() ?? '';

    return GestureDetector(
      onTap: () {
        if (goodsId.isNotEmpty) {
          context.push('/publication-detail?goodsId=$goodsId');
        }
      },
      child: Container(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              BookCover(imageUrl: coverUrl, width: 80, height: 116),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goodsName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (publication.containsKey('suffixCodeCount'))
                      Text(
                        '链码数量: ${publication['suffixCodeCount']}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    const SizedBox(height: 4),
                    if (publication.containsKey('publication'))
                      Text(
                        '${_getPublicationType(publication['publication']['publicationType'])}: ${publication['publication']['publicationIdentifier'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    const SizedBox(height: 4),
                    if (publication.containsKey('publication') &&
                        publication['publication'].containsKey('publisher'))
                      Text(
                        '${publication['publication']['publisher'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
