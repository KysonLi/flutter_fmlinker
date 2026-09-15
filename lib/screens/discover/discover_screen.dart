import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/services/discover_service.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';
import 'package:fmlink/widgets/icon_text_widgets.dart';
import 'package:fmlink/widgets/skeletonizer.dart';
import 'package:fmlink/utils/error_handler.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _discoverData;
  List<dynamic> _bannerData = [];
  int _currentBannerIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDiscoverData();
  }

  void _loadDiscoverData() async {
    try {
      final response = await DiscoverService().getDiscoverData();

      if (response['status']) {
        setState(() {
          _discoverData = response['data'];
          // 获取banner数据
          if (_discoverData != null && _discoverData!['advertInfo'] != null) {
            var advertInfo = _discoverData!['advertInfo'];
            if (advertInfo['list'] != null && advertInfo['list'] is List) {
              _bannerData = advertInfo['list'];
            }
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        EasyLoading.showError(response['msg']);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      EasyLoading.showError(ErrorHandler().fromError(e, fallback: '加载失败'));
    }
  }

  void _handleBannerClick(String jumpUrl) {
    if (jumpUrl.contains('http')) {
      String linkUrl = jumpUrl.trim();

      if (!linkUrl.startsWith('http://') && !linkUrl.startsWith('https://')) {
        linkUrl = 'https://$linkUrl';
      }

      try {
        Uri.parse(linkUrl);
        context.push('/webview?url=${Uri.encodeComponent(linkUrl)}');
      } catch (e) {
        debugPrint('Invalid URL: $jumpUrl, error: $e');
        EasyLoading.showError('链接无效');
      }
    } else if (jumpUrl.contains('mpr:')) {
      String goodsId = jumpUrl.replaceAll('mpr:', '').trim();
      if (goodsId.isNotEmpty) {
        context.push('/publication-detail?goodsId=$goodsId');
      } else {
        EasyLoading.showError('商品ID无效');
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发现', style: TextStyle(fontSize: 14))),
      body: _isLoading
          ? ListView(
              children: [
                // Banner骨架
                Container(
                  height: 180,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Skeletonizer(
                    child: Container(
                      width: double.infinity,
                      height: 180,
                      color: Colors.grey[200],
                    ),
                  ),
                ),
                // 今日推荐骨架
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Colors.white,
                  child: Skeletonizer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 100,
                          height: 20,
                          color: Colors.grey[200],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 100,
                              height: 140,
                              color: Colors.grey[200],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 20,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 150,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // 热门关注骨架
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Skeletonizer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 100,
                          height: 20,
                          color: Colors.grey[200],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 100,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 80,
                                    height: 12,
                                    color: Colors.grey[200],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 100,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 80,
                                    height: 12,
                                    color: Colors.grey[200],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 100,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 80,
                                    height: 12,
                                    color: Colors.grey[200],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // 点赞最多骨架
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(top: 16, bottom: 32),
                  color: Colors.white,
                  child: Skeletonizer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 100,
                          height: 20,
                          color: Colors.grey[200],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 100,
                              height: 140,
                              color: Colors.grey[200],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 20,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 100,
                                    height: 15,
                                    color: Colors.grey[200],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : _discoverData == null
              ? const Center(child: Text('加载失败'))
              : ListView(
                  children: [
                    // Banner图片
                    if (_bannerData.isNotEmpty) ...[
                      Stack(
                        children: [
                          CarouselSlider(
                            options: CarouselOptions(
                              height: 180,
                              viewportFraction: 1.0,
                              autoPlay: true,
                              autoPlayInterval: const Duration(seconds: 3),
                              autoPlayAnimationDuration: const Duration(
                                milliseconds: 800,
                              ),
                              autoPlayCurve: Curves.fastOutSlowIn,
                              pauseAutoPlayOnTouch: true,
                              aspectRatio: 2.0,
                              onPageChanged: (index, reason) {
                                setState(() {
                                  _currentBannerIndex = index;
                                });
                              },
                            ),
                            items: _bannerData.map((bannerItem) {
                              return GestureDetector(
                                onTap: () {
                                  final jumpUrl = bannerItem['jumpUrl'];
                                  if (jumpUrl != null && jumpUrl.isNotEmpty) {
                                    _handleBannerClick(jumpUrl);
                                  }
                                },
                                child: CachedNetworkImage(
                                  imageUrl: bannerItem['imagePath'] ?? '',
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  placeholder: (context, url) => Container(
                                    width: double.infinity,
                                    height: 180,
                                    color: Colors.grey[200],
                                  ),
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    width: double.infinity,
                                    height: 180,
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.error),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          // Banner指示器
                          Positioned(
                            bottom: 10,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children:
                                  _bannerData.asMap().entries.map((entry) {
                                return Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentBannerIndex == entry.key
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ], // 当没有banner数据时，不显示任何内容
                    //今日推荐
                    if (_discoverData!['dailyRcommend'] != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(color: Colors.white),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const IconTextWidget(
                              iconPath: 'assets/icons/discover_today.png',
                              text: '今日推荐',
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () {
                                String goodsId = _discoverData!['dailyRcommend']
                                            ['goodsId']
                                        ?.toString() ??
                                    '';
                                if (goodsId.isNotEmpty) {
                                  context.push(
                                      '/publication-detail?goodsId=$goodsId');
                                }
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 左侧图书封面
                                  BookCover(
                                    imageUrl: _discoverData!['dailyRcommend']
                                        ['goodsImage'],
                                  ),

                                  const SizedBox(width: 16),
                                  // 右侧图书信息
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 图书名称
                                        Text(
                                          _discoverData!['dailyRcommend']
                                              ['goodsName'],
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        // 链码 | 资源数量
                                        Text(
                                          '链码 ${_discoverData!['dailyRcommend']['sourceCount']} | 资源 ${_discoverData!['dailyRcommend']['resourceCount'] ?? 0}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // 编号
                                        Text(
                                          '${_getPublicationType(_discoverData!['dailyRcommend']['publication']['publicationType'] ?? 1)}: ${_discoverData!['dailyRcommend']['publication']['publicationIdentifier'] ?? ''}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // 出版社名称
                                        Text(
                                          _discoverData!['dailyRcommend']
                                                      ['publication']
                                                  ['publisher'] ??
                                              '',
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
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // 热门关注
                    if (_discoverData!['readRankingList'] != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(color: Colors.white),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const IconTextWidget(
                              iconPath: 'assets/icons/discover_read.png',
                              text: '热门关注',
                            ),
                            const SizedBox(height: 16),
                            Column(
                              children: List.generate(
                                ((_discoverData!['readRankingList'] as List)
                                            .length +
                                        2) ~/
                                    3, // 计算行数
                                (rowIndex) {
                                  return Row(
                                    children: List.generate(3, (colIndex) {
                                      int itemIndex = rowIndex * 3 + colIndex;
                                      if (itemIndex >=
                                          (_discoverData!['readRankingList']
                                                  as List)
                                              .length) {
                                        return const Expanded(
                                          child: SizedBox(),
                                        ); // 空占位
                                      }
                                      var item =
                                          (_discoverData!['readRankingList']
                                              as List)[itemIndex];
                                      return Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            String goodsId = item['goodsInfo']
                                                        ['goodsId']
                                                    ?.toString() ??
                                                '';
                                            if (goodsId.isNotEmpty) {
                                              context.push(
                                                  '/publication-detail?goodsId=$goodsId');
                                            }
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 5,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                // 封面撑满列宽，高度按 90:130 比例自适应
                                                LayoutBuilder(
                                                  builder:
                                                      (context, constraints) {
                                                    final width =
                                                        constraints.maxWidth;
                                                    return BookCover(
                                                      imageUrl:
                                                          item['goodsInfo']
                                                              ['goodsImage'],
                                                      width: width,
                                                      height: width * 130 / 90,
                                                    );
                                                  },
                                                ),
                                                const SizedBox(height: 8),
                                                // 图书名称
                                                Text(
                                                  item['goodsInfo']
                                                      ['goodsName'],
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 4),
                                                // 浏览次数
                                                IconTextWidget(
                                                  iconPath:
                                                      'assets/icons/discover_read_num.png',
                                                  text:
                                                      '${item['goodsReadCount'] ?? ''}',
                                                  iconSize: 15,
                                                  textSize: 12,
                                                  textColor: Colors.grey,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // 点赞最多
                    if (_discoverData!['likeMost'] != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(color: Colors.white),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const IconTextWidget(
                              iconPath: 'assets/icons/discover_like.png',
                              text: '点赞最多',
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () {
                                String goodsId = _discoverData!['likeMost']
                                            ['goodsInfo']['goodsId']
                                        ?.toString() ??
                                    '';
                                if (goodsId.isNotEmpty) {
                                  context.push(
                                      '/publication-detail?goodsId=$goodsId');
                                }
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BookCover(
                                    imageUrl: _discoverData!['likeMost']
                                        ['goodsInfo']['goodsImage'],
                                  ),

                                  const SizedBox(width: 16),
                                  // 右侧图书信息
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 图书名称
                                        Text(
                                          _discoverData!['likeMost']
                                              ['goodsInfo']['goodsName'],
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        // 链码 | 资源数量
                                        Text(
                                          '链码 ${_discoverData!['likeMost']['goodsInfo']['sourceCount'] ?? 0} | 资源 ${_discoverData!['likeMost']['goodsInfo']['resourceCount'] ?? 0}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // 编号
                                        Text(
                                          '${_getPublicationType(_discoverData!['likeMost']['goodsInfo']['publication']['publicationType'] ?? 1)}: ${_discoverData!['likeMost']['goodsInfo']['publication']['publicationIdentifier'] ?? ''}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // 点赞数量
                                        Text(
                                          '点赞 ${_discoverData!['likeMost']['goodsLikeCount']}',
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
                          ],
                        ),
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}
