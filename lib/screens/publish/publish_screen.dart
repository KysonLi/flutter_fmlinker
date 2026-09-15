import 'package:flutter/material.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/common/constants.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/common/refresh_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/models/publisher_model.dart';

class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final PublishService _publishService = PublishService();

  // 出版物相关状态
  List<dynamic> _publications = [];
  bool _isLoadingPublications = true;
  bool _isLoadingMorePublications = false;
  bool _hasErrorPublications = false;
  String _errorMessagePublications = '';
  int _publicationPage = 1;
  bool _hasMorePublications = true;

  // 出版者相关状态
  List<PublisherModel> _publishers = <PublisherModel>[];
  bool _isLoadingPublishers = true;
  bool _isLoadingMorePublishers = false;
  bool _hasErrorPublishers = false;
  String _errorMessagePublishers = '';
  int _publisherPage = 1;
  bool _hasMorePublishersList = true;

  bool _showPublications = true; // true: 显示出版物, false: 显示出版者
  bool _isCardLayout = true; // true: 卡片布局, false: 列表布局

  final ScrollController _scrollController = ScrollController();
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_showPublications && _publications.isNotEmpty) {
        if (_isLoadingMorePublications) return;
        if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent) {
          _loadMore();
        }
      } else if (!_showPublications && _publishers.isNotEmpty) {
        if (_isLoadingMorePublishers) return;
        if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent) {
          _loadMore();
        }
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_showPublications) {
      // 只有当出版物数据为空时才发起请求
      if (_publications.isEmpty) {
        await _loadPublications();
      }
    } else {
      // 只有当出版者数据为空时才发起请求
      if (_publishers.isEmpty) {
        await _loadPublishers();
      }
    }
  }

  Future<void> _loadPublications() async {
    try {
      setState(() {
        _hasErrorPublications = false;
        _errorMessagePublications = '';
        _isLoadingPublications = true;
      });

      final publicationsResponse = await _publishService.getPublications(
        page: _publicationPage,
        pageSize: Constants.pageSize,
      );
      debugPrint('Publications response: $publicationsResponse');
      if (publicationsResponse['status']) {
        // 处理数据结构
        dynamic data = publicationsResponse['data'];
        List<dynamic> publicationsList = [];

        if (data is Map) {
          if (data.containsKey('shopList') && data['shopList'] is List) {
            publicationsList = data['shopList'];
          } else if (data.containsKey('list') && data['list'] is List) {
            publicationsList = data['list'];
          }
        } else if (data is List) {
          publicationsList = data;
        }

        setState(() {
          if (_publicationPage == 1) {
            _publications = publicationsList;
          } else {
            _publications.addAll(publicationsList);
          }
          // 判断是否有更多数据
          _hasMorePublications = publicationsList.length >= Constants.pageSize;
        });
      } else {
        String errorMessage = publicationsResponse['msg'] ?? '加载出版物失败';
        debugPrint('Failed to load publications: $errorMessage');
        setState(() {
          _hasErrorPublications = true;
          _errorMessagePublications = errorMessage;
        });
      }
    } catch (e) {
      debugPrint('Error loading publications: $e');
      setState(() {
        _hasErrorPublications = true;
        _errorMessagePublications = '加载数据失败，请稍后重试';
      });
    } finally {
      setState(() {
        _isLoadingPublications = false;
        _isLoadingMorePublications = false;
      });
    }
  }

  Future<void> _loadPublishers() async {
    try {
      setState(() {
        _hasErrorPublishers = false;
        _errorMessagePublishers = '';
        _isLoadingPublishers = true;
      });

      final publishersResponse = await _publishService.getPublishers(
        page: _publisherPage,
        pageSize: Constants.pageSize,
      );
      debugPrint('Publishers response: $publishersResponse');
      if (publishersResponse['status']) {
        // 处理数据结构
        dynamic data = publishersResponse['data'];
        List<dynamic> publishersList = [];

        if (data is Map) {
          if (data.containsKey('shopList') && data['shopList'] is List) {
            publishersList = data['shopList'];
          } else if (data.containsKey('list') && data['list'] is List) {
            publishersList = data['list'];
          }
        } else if (data is List) {
          publishersList = data;
        }

        List<PublisherModel> publisherModels = publishersList
            .map((item) => PublisherModel.fromJson(item))
            .toList();

        setState(() {
          if (_publisherPage == 1) {
            _publishers = publisherModels;
          } else {
            _publishers.addAll(publisherModels);
          }
          _hasMorePublishersList = publisherModels.length >= Constants.pageSize;
        });
      } else {
        String errorMessage = publishersResponse['msg'] ?? '加载出版者失败';
        debugPrint('Failed to load publishers: $errorMessage');
        setState(() {
          _hasErrorPublishers = true;
          _errorMessagePublishers = errorMessage;
        });
      }
    } catch (e) {
      debugPrint('Error loading publishers: $e');
      setState(() {
        _hasErrorPublishers = true;
        _errorMessagePublishers = '加载数据失败，请稍后重试';
      });
    } finally {
      setState(() {
        _isLoadingPublishers = false;
        _isLoadingMorePublishers = false;
      });
    }
  }

  Future<void> _refreshData() async {
    if (_showPublications) {
      setState(() {
        _publicationPage = 1;
        _hasMorePublications = true;
      });
      await _loadPublications();
      _refreshController.finishRefresh();
    } else {
      setState(() {
        _publisherPage = 1;
        _hasMorePublishersList = true;
      });
      await _loadPublishers();
      _refreshController.finishRefresh();
    }
  }

  Future<void> _loadMore() async {
    if (_showPublications) {
      if (_isLoadingMorePublications || !_hasMorePublications) {
        _refreshController.finishLoad(IndicatorResult.noMore);
        return;
      }

      setState(() {
        _isLoadingMorePublications = true;
        _publicationPage++;
      });
      await _loadPublications();
      _refreshController.finishLoad(
        _hasMorePublications ? IndicatorResult.success : IndicatorResult.noMore,
      );
    } else {
      if (_isLoadingMorePublishers || !_hasMorePublishersList) {
        _refreshController.finishLoad(IndicatorResult.noMore);
        return;
      }

      setState(() {
        _isLoadingMorePublishers = true;
        _publisherPage++;
      });
      await _loadPublishers();
      _refreshController.finishLoad(
        _hasMorePublishersList
            ? IndicatorResult.success
            : IndicatorResult.noMore,
      );
    }
  }

  void _goToPublicationDetail(String goodsId) {
    context.push('/publication-detail?goodsId=$goodsId');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        // 左侧空白占位与右侧搜索按钮等宽（均为 56），
        // 标题槽在左右两侧之间对称 → 标题真正居中
        leading: const SizedBox.shrink(),
        actions: [
          SizedBox(
            width: kToolbarHeight,
            child: IconButton(
              icon: const Icon(Icons.search, size: 22),
              tooltip: '搜索',
              onPressed: () => context.push('/publish/search'),
            ),
          ),
        ],
        title: SizedBox(
          width: MediaQuery.of(context).size.width * 1 / 2,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (!_showPublications) {
                      setState(() {
                        _showPublications = true;
                      });
                      _loadData();
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                    ), // 缩小控件大小
                    child: Container(
                      // 蓝色下划线只包住文字宽度，而非整行
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _showPublications
                                ? Colors.blue
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        '出版物',
                        style: TextStyle(
                          color: _showPublications ? Colors.blue : Colors.grey,
                          fontWeight: _showPublications
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 13, // 缩小字体大小
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 20, // 缩小分隔线高度
                color: Colors.grey.shade300,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_showPublications) {
                      setState(() {
                        _showPublications = false;
                      });
                      _loadData();
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                    ), // 缩小控件大小
                    child: Container(
                      // 蓝色下划线只包住文字宽度，而非整行
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: !_showPublications
                                ? Colors.blue
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        '出版者',
                        style: TextStyle(
                          color: !_showPublications ? Colors.blue : Colors.grey,
                          fontWeight: !_showPublications
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14, // 缩小字体大小
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // 固定标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(
                0xf8,
                0xf9,
                0xfa,
                1,
              ), // 背景颜色与页面背景保持一致
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _showPublications ? 'MPR出版物（全媒版）' : 'MPR出版物出版者',
                  style: const TextStyle(
                    fontSize: 13, // 缩小文字大小
                  ),
                ),
                if (_showPublications)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isCardLayout = !_isCardLayout;
                      });
                    },
                    child: Image.asset(
                      _isCardLayout
                          ? 'assets/icons/type_list.png'
                          : 'assets/icons/type_card.png',
                      width: 30,
                      height: 30,
                    ),
                  ),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: _showPublications
                ? (_hasErrorPublications
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 60,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessagePublications,
                              style: const TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _refreshData,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : EasyRefresh(
                        controller: _refreshController,
                        onRefresh: () => _refreshData(),
                        onLoad: () => _loadMore(),
                        header: RefreshConfig.buildHeader(),
                        footer: RefreshConfig.buildFooter(),
                        child: _publications.isEmpty && !_isLoadingPublications
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/images/empty_list.png',
                                      width: 80,
                                      height: 80,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      '暂无出版物数据',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _isLoadingPublications && _publications.isEmpty
                                ? _buildPublicationSkeleton()
                                : _isCardLayout
                                    ? SingleChildScrollView(
                                        padding: const EdgeInsets.all(12),
                                        child: Wrap(
                                          alignment: WrapAlignment.start,
                                          spacing: 15,
                                          runSpacing: 15,
                                          children:
                                              _publications.map((publication) {
                                            return SizedBox(
                                              width: (MediaQuery.of(
                                                        context,
                                                      ).size.width -
                                                      24 -
                                                      30) /
                                                  3,
                                              child: _buildPublicationCard(
                                                publication,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _publications.length,
                                        itemBuilder: (context, index) {
                                          final publication =
                                              _publications[index];
                                          return _buildPublicationListTile(
                                            publication,
                                          );
                                        },
                                      ),
                      ))
                : (_hasErrorPublishers
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 60,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessagePublishers,
                              style: const TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _refreshData,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : EasyRefresh(
                        controller: _refreshController,
                        onRefresh: () => _refreshData(),
                        onLoad: () => _loadMore(),
                        header: RefreshConfig.buildHeader(),
                        footer: RefreshConfig.buildFooter(),
                        child: _publishers.isEmpty && !_isLoadingPublishers
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/images/empty_list.png',
                                      width: 80,
                                      height: 80,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      '暂无出版者数据',
                                      style: TextStyle(
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _isLoadingPublishers && _publishers.isEmpty
                                ? _buildPublisherSkeleton()
                                : SingleChildScrollView(
                                    padding: const EdgeInsets.all(12),
                                    child: Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      spacing: 10,
                                      runSpacing: 15,
                                      children: _publishers.map((publisher) {
                                        return SizedBox(
                                          width: (MediaQuery.of(
                                                    context,
                                                  ).size.width -
                                                  24 -
                                                  10) /
                                              2,
                                          child: _buildPublisherCard(
                                            publisher,
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                      )),
          ),
        ],
      ),
    );
  }

  // 出版物加载骨架：三列灰色占位卡片，与真实卡片布局一致
  Widget _buildPublicationSkeleton() {
    final double itemWidth = (MediaQuery.of(context).size.width - 24 - 30) / 3;
    const Color blockColor = Color(0xFFF0F1F3);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 15,
        runSpacing: 15,
        children: List.generate(9, (_) {
          return SizedBox(
            width: itemWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面占位
                Container(
                  width: itemWidth,
                  height: itemWidth * 130 / 90,
                  decoration: BoxDecoration(
                    color: blockColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                // 标题占位
                Container(
                  width: itemWidth * 0.8,
                  height: 11,
                  decoration: BoxDecoration(
                    color: blockColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                // 链码数占位
                Container(
                  width: itemWidth * 0.5,
                  height: 9,
                  decoration: BoxDecoration(
                    color: blockColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // 出版者加载骨架：两列灰色占位卡片，按可用高度动态生成卡片数量以占满全屏
  Widget _buildPublisherSkeleton() {
    final double itemWidth = (MediaQuery.of(context).size.width - 24 - 10) / 2;
    const Color blockColor = Color(0xFFF0F1F3);
    // 单行高度估算：内边距(8+8) + logo 45 + 间距(8+6) + 名称 11 + 数量 9 + 行间距 15
    const double rowHeight = 8 + 45 + 8 + 11 + 6 + 9 + 8 + 15;
    return LayoutBuilder(
      builder: (context, constraints) {
        final int rows = (constraints.maxHeight / rowHeight).ceil();
        final int itemCount = rows * 2;
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 10,
            runSpacing: 15,
            children: List.generate(itemCount, (_) {
              return Container(
                width: itemWidth,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // logo 占位
                    Container(
                      width: double.infinity,
                      height: 45,
                      decoration: BoxDecoration(
                        color: blockColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 名称占位
                    Container(
                      width: itemWidth * 0.6,
                      height: 11,
                      decoration: BoxDecoration(
                        color: blockColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 出版物数占位
                    Container(
                      width: itemWidth * 0.4,
                      height: 9,
                      decoration: BoxDecoration(
                        color: blockColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildPublicationCard(dynamic publication) {
    String? goodsId = publication['goodsId']?.toString();
    return GestureDetector(
      onTap: () {
        if (goodsId != null) {
          _goToPublicationDetail(goodsId);
        }
      },
      child: Container(
        margin: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 封面撑满网格列宽，高度按 90:130 比例自适应（列宽随屏宽动态）
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return BookCover(
                  imageUrl: _getPublicationImage(publication)!,
                  width: width,
                  height: width * 130 / 90,
                );
              },
            ),

            const SizedBox(height: 4),
            // 标题
            Text(
              publication['goodsName'] ?? '未知出版物',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // 链码数量
            if (publication.containsKey('suffixCodeCount'))
              Text(
                '链码: ${publication['suffixCodeCount']}',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublisherCard(PublisherModel publisher) {
    return GestureDetector(
      onTap: () {
        if (publisher.shopId.isNotEmpty) {
          context.push('/publisher-detail', extra: publisher);
        }
      },
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            // 柔和弥散阴影：大模糊半径、小偏移、低透明度，避免 Card 的硬边阴影
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                height: 45,
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: publisher.logo.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: publisher.logo,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => Container(
                          width: double.infinity,
                          height: 45,
                          color: Colors.white,
                          child: Center(
                            child: Text(
                              publisher.nameInitial,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: double.infinity,
                          height: 45,
                          color: Colors.white,
                          child: Center(
                            child: Text(
                              publisher.nameInitial,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          publisher.nameInitial,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                publisher.shopName.isNotEmpty ? publisher.shopName : '未知出版者',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              if (publisher.goodsCount.isNotEmpty)
                Text(
                  '出版物: ${publisher.goodsCount}',
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _getPublicationImage(dynamic publication) {
    if (publication == null) return null;

    // 检查多个可能的图片URL字段
    if (publication.containsKey('goodsImage') &&
        publication['goodsImage'] != null) {
      debugPrint('Found goodsImage: ${publication['goodsImage']}');
      return publication['goodsImage'];
    } else if (publication.containsKey('image_url') &&
        publication['image_url'] != null) {
      return publication['image_url'];
    } else if (publication.containsKey('imageUrl') &&
        publication['imageUrl'] != null) {
      return publication['imageUrl'];
    } else if (publication.containsKey('logo') && publication['logo'] != null) {
      return publication['logo'];
    }

    return null;
  }

  Widget _buildPublicationListTile(dynamic publication) {
    String? goodsId = publication['goodsId']?.toString();
    return GestureDetector(
      onTap: () {
        if (goodsId != null) {
          _goToPublicationDetail(goodsId);
        }
      },
      child: Column(
        children: [
          Container(
            color: Colors.white, // 列表背景色改为纯白
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  BookCover(
                    imageUrl: _getPublicationImage(publication) ?? '',
                    width: 100,
                    height: 140,
                  ),

                  const SizedBox(width: 12),
                  // 右侧信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 出版物名称
                        Text(
                          publication['goodsName'] ?? '未知出版物',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // 链码数量
                        if (publication.containsKey('suffixCodeCount'))
                          Text(
                            '链码数量: ${publication['suffixCodeCount']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        const SizedBox(height: 4),
                        // 编号
                        if (publication.containsKey('publication'))
                          Text(
                            '${_getPublicationType(publication['publication']['publicationType'])}: ${publication['publication']['publicationIdentifier'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        const SizedBox(height: 4),
                        // 出版社
                        if (publication.containsKey('publication') &&
                            publication['publication'].containsKey('publisher'))
                          Text(
                            '${publication['publication']['publisher'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 12,
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
          // 分割线，左侧与出版物信息对齐
          const Divider(
            height: 1,
            color: Color(0xFFEEEEEE), // 分割线颜色再淡一点
            indent: 100, // 80 (封面宽度) + 12 (间距) = 92，再加一点边距
          ),
        ],
      ),
    );
  }

  String _getPublicationType(int type) {
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
}
